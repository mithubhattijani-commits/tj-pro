import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Earn/spend history for the TJ Pro coins screen.
///
/// Body: { limit?: number } (default 50, max 100).
/// Returns { entries: [{ id, amount_coins, type, provider, ref_id,
/// created_at }] } — most recent first — for the logged-in user only.
/// The app falls back to its on-device history cache when this
/// function is unreachable.
///
/// Deploy:
///   supabase functions deploy tjpro-history --project-ref znyaxxkhhopdqrvxhxmb
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

  let limit = 50;
  try {
    const body = await req.json();
    if (typeof body?.limit === 'number') {
      limit = Math.min(100, Math.max(1, Math.floor(body.limit)));
    }
  } catch {
    // No/invalid body: default limit.
  }

  const { data: rows, error } = await supabase
    .from('ledger')
    .select('id, amount_coins, type, provider, ref_id, created_at')
    .eq('user_id', user.id)
    .like('type', 'tjpro_%')
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error) {
    return json({ error: 'db_error' }, 500);
  }

  return json({ entries: rows ?? [] }, 200);
});
