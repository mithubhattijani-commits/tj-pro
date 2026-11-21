import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Spend coins for a News Studio feature (TJ Pro).
///
/// Body: { amount_coins: number, reason: string, idempotency_key?: string }
/// The function re-validates the balance server-side (SUM of the
/// ledger) and only then inserts a negative entry (type
/// 'tjpro_spend'). A modded app cannot spend more than its ledger
/// balance. Idempotent per caller-supplied idempotency_key when given.
///
/// ADMIN BYPASS (server-side, never client-side): when the logged-in
/// user's email is one of the 3 admin emails, the spend is waived —
/// { ok: true, admin: true } with NO ledger insert and NO debit.
/// The client hides the Watch Ads button for admins, but the bypass
/// lives here: flipping a client flag cannot grant free features.
///
/// To change the admin list, edit ADMIN_EMAILS here AND in
/// tjpro-is-admin and redeploy both functions.
///
/// Deploy:
///   supabase functions deploy tjpro-spend-coins --project-ref znyaxxkhhopdqrvxhxmb
const ADMIN_EMAILS = [
  'mithubhattijani@gmail.com',
  'ghulamjillani019@gmail.com',
  'jaanirecords2@gmail.com',
];

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const json = (body: unknown, status: number) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const authHeader = req.headers.get('Authorization') ?? '';
  const { data: { user }, error: authError } = await supabase.auth.getUser(
    authHeader.replace('Bearer ', ''),
  );
  if (authError || !user) {
    return json({ error: 'unauthorized' }, 401);
  }

  let body: { amount_coins?: unknown; reason?: unknown; idempotency_key?: unknown } = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid_json' }, 400);
  }

  const amount = typeof body.amount_coins === 'number'
    ? Math.floor(body.amount_coins)
    : 0;
  if (amount <= 0) {
    return json({ error: 'invalid_amount' }, 400);
  }
  const reason = typeof body.reason === 'string' ? body.reason : 'feature';

  // --- Balance from the server ledger (never trust the client) ---
  const { data: rows, error: sumError } = await supabase
    .from('ledger')
    .select('amount_coins')
    .eq('user_id', user.id);
  if (sumError) {
    return json({ error: 'db_error' }, 500);
  }
  const balance = (rows ?? []).reduce(
    (sum: number, r: { amount_coins: number }) => sum + r.amount_coins,
    0,
  );

  // --- Admin bypass (server-side only) ---
  const email = typeof user.email === 'string' ? user.email : null;
  if (email !== null && ADMIN_EMAILS.includes(email.toLowerCase())) {
    return json({ ok: true, admin: true, balance }, 200);
  }

  if (balance < amount) {
    return json({ error: 'insufficient_balance', balance }, 409);
  }

  const idemKey = typeof body.idempotency_key === 'string' &&
      body.idempotency_key.length > 0
    ? body.idempotency_key
    : `tjpro_spend:${user.id}:${Date.now()}:${amount}`;

  const { data, error: insertError } = await supabase
    .from('ledger')
    .insert({
      user_id: user.id,
      amount_coins: -amount,
      type: 'tjpro_spend',
      provider: 'tj_pro',
      ref_id: reason,
      idempotency_key: idemKey,
    })
    .select('id')
    .single();

  if (insertError) {
    if ((insertError as { code?: string }).code === '23505') {
      return json({ ok: true, balance: balance - amount, duplicate: true }, 200);
    }
    return json({ error: 'db_error' }, 500);
  }

  return json({ ok: true, balance: balance - amount, id: data.id }, 200);
});
