// Supabase Edge Function: claude-proxy
//
// Holds the Anthropic API key server-side so it NEVER ships in the iOS app
// binary (a client-side key is trivially extractable and can drain the account).
// The app POSTs the standard Anthropic Messages API body here; this function
// adds the real key and forwards to Anthropic, streaming the SSE response back
// unchanged so the app's token-by-token UI keeps working.
//
// Guardrails against a tampered client: a model allow-list and a max_tokens
// ceiling.
//
// Deploy:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy claude-proxy
//
// The app authenticates with the Supabase anon key (standard Edge Function auth)
// and points API_CLAUDE_PROXY_URL at this function's URL.

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

// Only models the app actually uses. Reject anything else so a tampered client
// can't run arbitrary/expensive models on our key.
const ALLOWED_MODELS = new Set<string>([
  "claude-sonnet-4-6",
  "claude-opus-4-8",
]);
const MAX_TOKENS_CEILING = 4096;

const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, anthropic-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "content-type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  if (!ANTHROPIC_API_KEY) return json({ error: "proxy not configured" }, 500);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  if (typeof body.model !== "string" || !ALLOWED_MODELS.has(body.model)) {
    return json({ error: `model not allowed: ${String(body.model)}` }, 400);
  }

  // Clamp max_tokens to the ceiling (or set it if the client omitted it).
  const requested = typeof body.max_tokens === "number" ? body.max_tokens : MAX_TOKENS_CEILING;
  body.max_tokens = Math.min(requested, MAX_TOKENS_CEILING);

  const upstream = await fetch(ANTHROPIC_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify(body),
  });

  // Pass the response body straight through. For `stream: true` this preserves
  // the text/event-stream so the app receives the same SSE deltas as before.
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      ...cors,
      "content-type": upstream.headers.get("content-type") ?? "application/json",
    },
  });
});
