// Supabase Edge Function: inbound-email
//
// Webhook receiver for the Email Intelligence forwarding pipeline. An inbound
// email provider (Postmark inbound, SendGrid Inbound Parse [JSON mode via a
// relay], or a Cloudflare Email Worker) POSTs each email sent to
// <alias>@in.<your-domain> here. We resolve the alias to a user and store the
// raw email in `inbound_emails`; the iOS app fetches it, parses it ON-DEVICE,
// and deletes the row — the raw email is never retained after processing.
//
// Security: requests must carry the shared secret header configured in the
// provider:  x-inbound-secret: <INBOUND_EMAIL_SECRET>
//
// Deploy:
//   supabase secrets set INBOUND_EMAIL_SECRET=<long random string>
//   supabase functions deploy inbound-email --no-verify-jwt
// (--no-verify-jwt because the caller is the mail provider, not a user; the
//  shared secret is the auth. SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are
//  injected automatically.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAX_RAW_BYTES = 200_000; // cap stored email size (~200 KB of text)

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }

  const secret = Deno.env.get("INBOUND_EMAIL_SECRET");
  if (!secret || req.headers.get("x-inbound-secret") !== secret) {
    return json({ error: "Unauthorized" }, 401);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Body must be JSON" }, 400);
  }

  const recipient = extractRecipient(payload);
  if (!recipient) {
    return json({ error: "No recipient found in payload" }, 400);
  }
  const alias = recipient.split("@")[0].toLowerCase();

  const rawEmail = extractText(payload);
  if (!rawEmail) {
    return json({ error: "No email text found in payload" }, 400);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Resolve alias → user
  const { data: aliasRow, error: aliasErr } = await admin
    .from("email_aliases")
    .select("user_id")
    .eq("alias", alias)
    .maybeSingle();

  if (aliasErr) {
    return json({ error: aliasErr.message }, 500);
  }
  if (!aliasRow) {
    // Unknown alias — accept silently (200) so providers don't retry/bounce
    // in a way that leaks which aliases exist.
    return json({ stored: false });
  }

  const { error: insertErr } = await admin.from("inbound_emails").insert({
    user_id: aliasRow.user_id,
    raw_email: rawEmail.slice(0, MAX_RAW_BYTES),
  });
  if (insertErr) {
    return json({ error: insertErr.message }, 500);
  }

  return json({ stored: true });
});

/** Recipient across common provider payload shapes. */
function extractRecipient(p: Record<string, unknown>): string | null {
  // Postmark: ToFull: [{ Email }]
  const toFull = p["ToFull"];
  if (Array.isArray(toFull) && toFull[0]?.Email) return String(toFull[0].Email);
  // Cloudflare Email Worker relay / generic
  for (const key of ["to", "To", "recipient", "envelopeTo"]) {
    const v = p[key];
    if (typeof v === "string" && v.includes("@")) {
      // May be "Name <addr@x>" or a comma list — take the first address.
      const match = v.match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/);
      if (match) return match[0];
    }
  }
  const envelope = p["envelope"];
  if (envelope && typeof envelope === "object") {
    const to = (envelope as Record<string, unknown>)["to"];
    if (Array.isArray(to) && typeof to[0] === "string") return to[0];
    if (typeof to === "string") return to;
  }
  return null;
}

/** Email body text across common provider payload shapes (prefer plain text). */
function extractText(p: Record<string, unknown>): string | null {
  const parts: string[] = [];
  const subject = p["Subject"] ?? p["subject"];
  if (typeof subject === "string" && subject) parts.push(`Subject: ${subject}`);

  for (const key of ["TextBody", "text", "plain", "raw", "content", "body"]) {
    const v = p[key];
    if (typeof v === "string" && v.trim()) {
      parts.push(v);
      return parts.join("\n\n");
    }
  }
  // Fall back to HTML with tags stripped.
  for (const key of ["HtmlBody", "html"]) {
    const v = p[key];
    if (typeof v === "string" && v.trim()) {
      parts.push(v.replace(/<style[\s\S]*?<\/style>/gi, "")
        .replace(/<[^>]+>/g, " ")
        .replace(/&nbsp;/g, " ")
        .replace(/\s{3,}/g, "\n"));
      return parts.join("\n\n");
    }
  }
  return parts.length > 1 ? parts.join("\n\n") : null;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
