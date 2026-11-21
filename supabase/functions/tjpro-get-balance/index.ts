import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Server balance for TJ Pro News Studio (SUM of the caller's ledger
/// rows). The app uses this as the source of truth; until the
/// functions are deployed it runs on its local balance.
///
/// Also returns the server-side admin flag so the app can hide the
/// Watch Ads button for admins. The admin list lives ONLY here (and
/// in tjpro-spend-coins) — never in the client.
///
/// Deploy:
///   supabase functions deploy tjpro-get-balance --project-ref znyaxxkhhopdqrvxhxmb
/// (or the supabase_api.py deploy-function helper — see the task report.)
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

  const { data: rows, error } = await supabase
    .from('ledger')
    .select('amount_coins')
    .eq('user_id', user.id);
  if (error) {
    return json({ error: 'db_error' }, 500);
  }

  const balance = (rows ?? []).reduce(
    (sum: number, r: { amount_coins: number }) => sum + r.amount_coins,
    0,
  );
  const isAdmin = typeof user.email === 'string' &&
    ADMIN_EMAILS.includes(user.email.toLowerCase());
  return json({ balance_coins: balance, is_admin: isAdmin }, 200);
});
