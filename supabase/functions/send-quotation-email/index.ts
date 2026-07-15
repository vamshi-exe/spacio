// Spacio — email a quotation PDF to a client.
//
// Uses Resend (https://resend.com) to deliver a branded email with the
// quotation PDF attached. The PDF is hosted on Cloudinary first (same as the
// WhatsApp flow), and Resend fetches it via the attachment `path`.
//
// ── Deploy ──────────────────────────────────────────────────────────────────
//   supabase functions deploy send-quotation-email
//
// ── Secrets (set once) ──────────────────────────────────────────────────────
//   supabase secrets set \
//     RESEND_API_KEY="re_...your-key" \
//     EMAIL_FROM="Spacio <quotations@yourdomain.com>"
//   (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.)
//   EMAIL_FROM must be an address on a domain verified in Resend.
//
// The app invokes this with:
//   { toEmail, clientName, attachments: [{ filename, content }], summary }
// where `content` is the base64-encoded PDF (sent inline so nothing needs to be
// publicly hosted). A hosted `{ url }` / legacy `{ pdfUrl }` shape also works.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

function isEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    // 1. Authenticate the caller via their Supabase JWT.
    const jwt = (req.headers.get('Authorization') ?? '').replace('Bearer ', '');
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userData.user) return json({ error: 'Unauthorized' }, 401);
    const userId = userData.user.id;
    const senderEmail = userData.user.email ?? null;

    // 2. Validate input. Accept a list of attachments, or the legacy single
    //    { pdfUrl, filename } shape.
    const { toEmail, clientName, attachments, pdfUrl, filename, summary } =
      await req.json();
    const to = String(toEmail ?? '').trim();
    if (!isEmail(to)) return json({ error: 'toEmail is not a valid address' }, 400);

    // Each Resend attachment carries either inline base64 `content` (preferred)
    // or a hosted `path` URL.
    const files: Record<string, string>[] = [];
    if (Array.isArray(attachments)) {
      for (const a of attachments) {
        const name = a?.filename ?? 'Quotation.pdf';
        if (a?.content) {
          files.push({ filename: name, content: a.content });
        } else if (a?.url ?? a?.path) {
          files.push({ filename: name, path: a.url ?? a.path });
        }
      }
    } else if (pdfUrl) {
      files.push({ filename: filename ?? 'Quotation.pdf', path: pdfUrl });
    }
    if (files.length === 0) {
      return json({ error: 'At least one attachment is required' }, 400);
    }

    // 3. Build the Resend request.
    const apiKey = Deno.env.get('RESEND_API_KEY');
    const from = Deno.env.get('EMAIL_FROM');
    if (!apiKey || !from) {
      return json({ error: 'Email secrets are not configured.' }, 500);
    }

    const name = clientName ? String(clientName) : 'there';
    const safeName = escapeHtml(name);
    const safeSummary = summary ? escapeHtml(String(summary)) : null;
    const subject = clientName
      ? `Your tile quotation from Spacio, ${name}`
      : 'Your tile quotation from Spacio';

    const html = `
      <div style="font-family:Helvetica,Arial,sans-serif;color:#111112;line-height:1.5">
        <p>Hi ${safeName},</p>
        <p>Please find your tile quotation from <strong>Spacio</strong> attached as a PDF.</p>
        ${safeSummary ? `<p style="color:#6b6b70">${safeSummary}</p>` : ''}
        <p style="color:#6b6b70;font-size:13px">
          This is an approximate estimate — final cost may vary with site
          conditions, layout, grouting and labour.
        </p>
        <p>Thank you,<br/>Spacio</p>
      </div>
    `;

    const payload: Record<string, unknown> = {
      from,
      to: [to],
      subject,
      html,
      attachments: files,
    };
    // Route client replies back to the merchant who sent it.
    if (senderEmail) payload.reply_to = senderEmail;

    const resp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
    const result = await resp.json();
    const ok = resp.ok;
    const messageId = result?.id ?? null;

    // 4. Log the attempt (service role bypasses RLS). Non-fatal: a logging
    //    failure must not fail an otherwise-successful send.
    try {
      await admin.from('email_sends').insert({
        user_id: userId,
        to_email: to,
        client_name: clientName ?? null,
        pdf_url: files.map((f) => f.path ?? f.filename).join(' , '),
        summary: summary ?? null,
        status: ok ? 'sent' : 'failed',
        provider_message_id: messageId,
        error: ok ? null : JSON.stringify(result),
      });
    } catch (logErr) {
      console.error('email_sends log failed:', logErr);
    }

    if (!ok) return json({ error: 'Email send failed', details: result }, 502);
    return json({ status: 'sent', messageId });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
