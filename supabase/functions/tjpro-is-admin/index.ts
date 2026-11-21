import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

/// Server-side admin check for TJ Pro News Studio.
///
/// Returns { is_admin: boolean, email: string | null } for the
/// logged-in user. The admin list lives ONLY on the server (this
/// function + tjpro-spend-coins) — the client NEVER decides admin
/// status from a local email list, and the coin bypass is enforced
/// server-side in tjpro-spend-coins, so a modded client cannot grant
/// itself free features by flipping a flag.
///
/// Admins (20 Nov 2026): mithubhattijani@gmail.com,
/// ghulamjillani019@gmail.com, jaanirecords2@gmail.com. To change the
/// list, edit ADMIN_EMAILS here AND in tjpro-spend-coins and redeploy
/// both functions.
///
/// Deploy:
///   supabase functions deploy tjpro-is-admin --project-ref znyaxxkhhopdqrvxhxmb
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

  const email = typeof user.email === 'string' ? user.email : null;
  const isAdmin = email !== null &&
    ADMIN_EMAILS.includes(email.toLowerCase());
  return json({ is_admin: isAdmin, email }, 200);
});
