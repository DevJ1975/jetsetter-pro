// Supabase Edge Function: delete-user
//
// Permanently deletes the calling user's auth account. The user's data rows are
// removed automatically by the `on delete cascade` foreign keys in schema.sql
// (the iOS client also pre-deletes them as belt-and-suspenders).
//
// The iOS app calls this with the signed-in user's JWT in the Authorization
// header; we resolve the caller from that token, then delete them using the
// service-role key (never shipped to the client).
//
// Deploy:  supabase functions deploy delete-user
// (SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected
//  automatically by the Edge Functions runtime.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing Authorization header" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Identify the caller from their JWT.
  const asUser = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userErr } = await asUser.auth.getUser();
  if (userErr || !user) {
    return json({ error: "Invalid or expired session" }, 401);
  }

  // Delete the auth user with the service-role (admin) client. The cascade FK
  // removes their rows in every per-user table.
  const admin = createClient(url, serviceKey);
  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) {
    return json({ error: error.message }, 500);
  }

  return json({ deleted: true });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
