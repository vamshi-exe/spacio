// Spacio — send a quotation PDF to a client over WhatsApp.
//
// Uses the Meta WhatsApp Cloud API. Business-initiated messages must use a
// pre-approved template, so this sends a TEMPLATE with a document header
// (the quotation PDF) and one body parameter (the client's name).
//
// ── Deploy ──────────────────────────────────────────────────────────────────
//   supabase functions deploy send-whatsapp-quotation
//
// ── Secrets (set once) ──────────────────────────────────────────────────────
//   supabase secrets set \
//     WHATSAPP_TOKEN="EAAB...your-permanent-token" \
//     WHATSAPP_PHONE_NUMBER_ID="1234567890" \
//     WHATSAPP_TEMPLATE_NAME="spacio_quotation" \
//     WHATSAPP_TEMPLATE_LANG="en"
//   (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.)
//
// ── Template ────────────────────────────────────────────────────────────────
//   Create & get approval in Meta Business Manager for a template named
//   WHATSAPP_TEMPLATE_NAME with:
//     • Header: Document
//     • Body:   e.g. "Hi {{1}}, here is your tile quotation from Spacio."
//
// The app invokes this with: { toPhone, clientName, pdfUrl, filename, summary }

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

    // 2. Validate input.
    const { toPhone, clientName, pdfUrl, filename, summary } = await req.json();
    if (!toPhone || !pdfUrl) {
      return json({ error: 'toPhone and pdfUrl are required' }, 400);
    }
    const to = String(toPhone).replace(/[^0-9]/g, ''); // E.164 digits only

    // 3. Build the Meta Cloud API request.
    const token = Deno.env.get('WHATSAPP_TOKEN');
    const phoneNumberId = Deno.env.get('WHATSAPP_PHONE_NUMBER_ID');
    if (!token || !phoneNumberId) {
      return json({ error: 'WhatsApp secrets are not configured.' }, 500);
    }
    const templateName = Deno.env.get('WHATSAPP_TEMPLATE_NAME') ?? 'spacio_quotation';
    const templateLang = Deno.env.get('WHATSAPP_TEMPLATE_LANG') ?? 'en';

    const payload = {
      messaging_product: 'whatsapp',
      to,
      type: 'template',
      template: {
        name: templateName,
        language: { code: templateLang },
        components: [
          {
            type: 'header',
            parameters: [
              {
                type: 'document',
                document: { link: pdfUrl, filename: filename ?? 'Quotation.pdf' },
              },
            ],
          },
          {
            type: 'body',
            parameters: [{ type: 'text', text: clientName ?? 'there' }],
          },
        ],
      },
    };

    const resp = await fetch(
      `https://graph.facebook.com/v21.0/${phoneNumberId}/messages`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      },
    );
    const result = await resp.json();
    const ok = resp.ok;
    const messageId = result?.messages?.[0]?.id ?? null;

    // 4. Log the attempt (service role bypasses RLS). Non-fatal: a logging
    //    failure must not fail an otherwise-successful send.
    try {
      await admin.from('whatsapp_sends').insert({
        user_id: userId,
        to_phone: to,
        client_name: clientName ?? null,
        pdf_url: pdfUrl,
        summary: summary ?? null,
        status: ok ? 'sent' : 'failed',
        provider_message_id: messageId,
        error: ok ? null : JSON.stringify(result),
      });
    } catch (logErr) {
      console.error('whatsapp_sends log failed:', logErr);
    }

    if (!ok) return json({ error: 'WhatsApp send failed', details: result }, 502);
    return json({ status: 'sent', messageId });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
