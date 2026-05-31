// Supabase Edge Function: claude-proxy
//
// Server-side proxy for the Anthropic Claude Messages API.
//
// WHY THIS EXISTS
// ───────────────
// The iOS app must never embed the Anthropic API key — anything shipped in the
// binary can be extracted and abused. This function holds the key in its server
// environment and forwards requests to Anthropic on the app's behalf, preserving
// both the JSON and SSE-streaming response shapes so the client code is unchanged
// apart from the URL it points at.
//
// DEPLOY
// ──────
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy claude-proxy
//
// The Supabase platform injects SUPABASE_URL / SUPABASE_ANON_KEY automatically
// and, by default, verifies the caller's anon (or user) JWT before this code
// runs — so only your app's clients can reach the proxy.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

// Restrict which models the proxy is willing to call, so a tampered client
// can't run up costs on an arbitrary (e.g. far more expensive) model.
const ALLOWED_MODELS = new Set<string>([
  "claude-sonnet-4-20250514",
]);

// Hard ceiling on output tokens regardless of what the client requests.
const MAX_OUTPUT_TOKENS = 4096;

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req: Request): Promise<Response> => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    return json({ error: "Server is not configured (missing ANTHROPIC_API_KEY)." }, 500);
  }

  // Parse and validate the client payload.
  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body." }, 400);
  }

  const model = typeof payload.model === "string" ? payload.model : "";
  if (!ALLOWED_MODELS.has(model)) {
    return json({ error: `Model "${model}" is not permitted.` }, 400);
  }

  if (!Array.isArray(payload.messages)) {
    return json({ error: "`messages` must be an array." }, 400);
  }

  // Clamp max_tokens to our ceiling.
  const requested = Number(payload.max_tokens);
  payload.max_tokens = Number.isFinite(requested)
    ? Math.min(Math.max(1, Math.trunc(requested)), MAX_OUTPUT_TOKENS)
    : 1024;

  const wantsStream = payload.stream === true;

  // Forward to Anthropic with the server-held key.
  let upstream: Response;
  try {
    upstream = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body: JSON.stringify(payload),
    });
  } catch (err) {
    return json({ error: `Upstream request failed: ${String(err)}` }, 502);
  }

  // Stream responses are piped straight back to preserve SSE token-by-token UX.
  if (wantsStream && upstream.body) {
    return new Response(upstream.body, {
      status: upstream.status,
      headers: {
        ...CORS_HEADERS,
        "Content-Type": upstream.headers.get("content-type") ?? "text/event-stream",
        "Cache-Control": "no-cache",
      },
    });
  }

  // Non-streaming: relay the body and status verbatim.
  const body = await upstream.text();
  return new Response(body, {
    status: upstream.status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": upstream.headers.get("content-type") ?? "application/json",
    },
  });
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}
