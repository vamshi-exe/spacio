// SPACIO admin dashboard — merchant management.
//
// A zero-build static SPA: it talks straight to Supabase with the public anon
// key. Every read/write is authorized server-side by RLS + the admin email
// allowlist (see supabase/schema.sql → "ADMIN"), so nothing sensitive is
// exposed here. Load order: config.js sets window.SPACIO_ADMIN_CONFIG first.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cfg = window.SPACIO_ADMIN_CONFIG;
const supabase = createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);

// Plans the mobile app knows about (lib/models/subscription_plan.dart) plus the
// free trial. Kept here only to drive the dropdown + allowance reset helper.
const PLANS = ['Free', 'SPACIO BYOD', 'SPACIO Standard', 'SPACIO Pro'];
const PLAN_ALLOWANCE = {
  'SPACIO BYOD': 300,
  'SPACIO Standard': 300,
  'SPACIO Pro': 400,
};
const allowanceFor = (plan) => PLAN_ALLOWANCE[plan] ?? 50;

// ── DOM helpers ─────────────────────────────────────────────────────────────
const $ = (id) => document.getElementById(id);
const show = (el) => el.classList.remove('hidden');
const hide = (el) => el.classList.add('hidden');
const esc = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]),
  );

let merchants = [];
let editing = null; // the merchant row currently open in the modal

// ── Views ───────────────────────────────────────────────────────────────────
function showView(name) {
  for (const v of ['loginView', 'deniedView', 'appView']) hide($(v));
  name === 'app' ? show($('topbar')) : hide($('topbar'));
  show($(name === 'login' ? 'loginView' : name === 'denied' ? 'deniedView' : 'appView'));
}

function toast(msg, isError = false) {
  const t = $('toast');
  t.textContent = msg;
  t.classList.toggle('err', isError);
  show(t);
  clearTimeout(toast._t);
  toast._t = setTimeout(() => hide(t), 3200);
}

// ── Auth flow ───────────────────────────────────────────────────────────────
async function boot() {
  const { data } = await supabase.auth.getSession();
  data.session ? await onSignedIn(data.session) : showView('login');
}

async function onSignedIn(session) {
  // Authorize: is this email on the admin allowlist? Enforced in the DB.
  const { data: isAdmin, error } = await supabase.rpc('is_admin');
  if (error) {
    toast('Could not verify admin access.', true);
    showView('denied');
    return;
  }
  if (!isAdmin) {
    showView('denied');
    return;
  }
  $('whoami').textContent = session.user.email;
  showView('app');
  await loadMerchants();
}

$('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('loginError').textContent = '';
  $('loginBtn').disabled = true;
  try {
    const { data, error } = await supabase.auth.signInWithPassword({
      email: $('email').value.trim(),
      password: $('password').value,
    });
    if (error) throw error;
    await onSignedIn(data.session);
  } catch (err) {
    $('loginError').textContent = err.message || 'Sign in failed.';
  } finally {
    $('loginBtn').disabled = false;
  }
});

async function signOut() {
  await supabase.auth.signOut();
  merchants = [];
  showView('login');
}
$('logoutBtn').addEventListener('click', signOut);
$('deniedLogout').addEventListener('click', signOut);
$('refreshBtn').addEventListener('click', () => loadMerchants());

// ── Data ────────────────────────────────────────────────────────────────────
async function loadMerchants() {
  show($('loading'));
  hide($('empty'));
  const { data, error } = await supabase
    .from('profiles')
    .select(
      'id, full_name, email, plan, renders_left, topup_renders_left, ' +
        'merchant_type, subscription_active_until, created_at',
    )
    .order('created_at', { ascending: false });
  hide($('loading'));
  if (error) {
    toast('Failed to load merchants: ' + error.message, true);
    return;
  }
  merchants = data ?? [];
  renderStats();
  render();
}

function subStatus(m) {
  if (m.merchant_type === 'device') return { cls: 'device', text: 'Preloaded' };
  const until = m.subscription_active_until
    ? new Date(m.subscription_active_until)
    : null;
  if (until && until > new Date()) {
    return { cls: 'ok', text: 'Active · ' + until.toLocaleDateString() };
  }
  if (until) return { cls: 'off', text: 'Expired · ' + until.toLocaleDateString() };
  return { cls: 'warn', text: 'None' };
}

function renderStats() {
  const total = merchants.length;
  const active = merchants.filter((m) => subStatus(m).cls === 'ok' || m.merchant_type === 'device').length;
  const byod = merchants.filter((m) => m.merchant_type !== 'device').length;
  const device = total - byod;
  const stats = [
    ['Merchants', total],
    ['Active subs', active],
    ['BYOD', byod],
    ['Device', device],
  ];
  $('stats').innerHTML = stats
    .map(([k, v]) => `<div class="stat"><div class="k">${k}</div><div class="v">${v}</div></div>`)
    .join('');
}

function render() {
  const q = $('search').value.trim().toLowerCase();
  const rows = merchants.filter((m) => {
    if (!q) return true;
    return [m.full_name, m.email, m.plan].some((f) =>
      String(f ?? '').toLowerCase().includes(q),
    );
  });

  $('count').textContent = `${rows.length} of ${merchants.length}`;
  $('rows').innerHTML = rows
    .map((m) => {
      const s = subStatus(m);
      const renders = (m.renders_left ?? 0) + (m.topup_renders_left ?? 0);
      const name = esc(m.full_name || m.email || 'Unnamed');
      return `
        <tr>
          <td>
            <div class="m-name">${name}</div>
            <div class="m-mail">${esc(m.email || '—')}</div>
          </td>
          <td>${esc(m.plan || 'Free')}</td>
          <td><span class="badge ${m.merchant_type === 'device' ? 'device' : ''}">${
            m.merchant_type === 'device' ? 'Device' : 'BYOD'
          }</span></td>
          <td>${renders} <span class="muted small">(${m.renders_left ?? 0}+${m.topup_renders_left ?? 0})</span></td>
          <td><span class="badge ${s.cls}">${esc(s.text)}</span></td>
          <td><button class="btn btn-ghost sm" data-edit="${m.id}">Manage</button></td>
        </tr>`;
    })
    .join('');

  $('empty').classList.toggle('hidden', rows.length > 0);
  for (const b of $('rows').querySelectorAll('[data-edit]')) {
    b.addEventListener('click', () => openEditor(b.getAttribute('data-edit')));
  }
}

$('search').addEventListener('input', render);

// ── Edit modal ──────────────────────────────────────────────────────────────
function planOptions(selected) {
  const opts = new Set([...PLANS, selected].filter(Boolean));
  return [...opts]
    .map((p) => `<option value="${esc(p)}" ${p === selected ? 'selected' : ''}>${esc(p)}</option>`)
    .join('');
}

function toDateInput(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  // yyyy-mm-dd in local time for the <input type=date>.
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function openEditor(id) {
  const m = merchants.find((x) => x.id === id);
  if (!m) return;
  editing = m;
  $('mName').textContent = m.full_name || m.email || 'Merchant';
  $('mEmail').textContent = m.email || '';
  $('fPlan').innerHTML = planOptions(m.plan || 'Free');
  $('fType').value = m.merchant_type === 'device' ? 'device' : 'byod';
  $('fRenders').value = m.renders_left ?? 0;
  $('fTopup').value = m.topup_renders_left ?? 0;
  $('fUntil').value = toDateInput(m.subscription_active_until);
  $('fReset').checked = false;
  $('modalError').textContent = '';
  show($('modal'));
}

function closeEditor() {
  editing = null;
  hide($('modal'));
}
$('modalClose').addEventListener('click', closeEditor);
$('cancelBtn').addEventListener('click', closeEditor);
$('modal').addEventListener('click', (e) => {
  if (e.target === $('modal')) closeEditor();
});

// Quick-extend buttons: extend from the later of today or the current expiry.
for (const btn of document.querySelectorAll('[data-ext]')) {
  btn.addEventListener('click', () => {
    const days = Number(btn.getAttribute('data-ext'));
    const current = $('fUntil').value ? new Date($('fUntil').value) : null;
    const base = current && current > new Date() ? current : new Date();
    base.setDate(base.getDate() + days);
    $('fUntil').value = toDateInput(base.toISOString());
  });
}
$('fUntilClear').addEventListener('click', () => ($('fUntil').value = ''));

$('editForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!editing) return;
  $('modalError').textContent = '';
  $('saveBtn').disabled = true;

  const plan = $('fPlan').value;
  const patch = {
    plan,
    merchant_type: $('fType').value,
    renders_left: $('fReset').checked
      ? allowanceFor(plan)
      : Math.max(0, parseInt($('fRenders').value || '0', 10)),
    topup_renders_left: Math.max(0, parseInt($('fTopup').value || '0', 10)),
    subscription_active_until: $('fUntil').value
      ? new Date($('fUntil').value + 'T00:00:00').toISOString()
      : null,
  };

  const { data, error } = await supabase
    .from('profiles')
    .update(patch)
    .eq('id', editing.id)
    .select()
    .single();

  $('saveBtn').disabled = false;
  if (error) {
    $('modalError').textContent = error.message;
    return;
  }
  // Merge the saved row back into the cache and re-render.
  const i = merchants.findIndex((x) => x.id === editing.id);
  if (i !== -1) merchants[i] = { ...merchants[i], ...data };
  closeEditor();
  renderStats();
  render();
  toast('Merchant updated.');
});

// React to auth changes (e.g. token refresh / sign-out in another tab).
supabase.auth.onAuthStateChange((event) => {
  if (event === 'SIGNED_OUT') showView('login');
});

boot();
