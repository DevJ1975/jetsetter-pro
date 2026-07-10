// supabase/functions/delete-account/index.ts
//
// Deletes the calling user's GoTrue auth account. This requires the service_role
// key, which must NEVER ship in the iOS client — so the privileged operation is
// performed here, server-side, after verifying the caller's own JWT.
//
// The iOS app calls this from SupabaseService.deleteAccount() (App Store
// Guideline 5.1.1(v) account deletion). Owned rows in public.trips / public.
// expenses are removed by the ON DELETE CASCADE foreign key on user_id, and the
// app additionally deletes them explicitly before invoking this function.
//
// Deploy:  supabase functions deploy delete-account
// Env (auto-injected by Supabase): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "Missing bearer token" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Function is misconfigured" }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  // Resolve the caller from their own access token — never trust a uid from the body.
  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  if (userErr || !userData.user) return json({ error: "Invalid or expired token" }, 401);

  const uid = userData.user.id;
  const { error: deleteErr } = await admin.auth.admin.deleteUser(uid);
  if (deleteErr) return json({ error: deleteErr.message }, 500);

  return json({ deleted: uid }, 200);
});
