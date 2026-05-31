# claude-proxy

Server-side proxy for the Anthropic Claude Messages API, deployed as a Supabase
Edge Function.

## Why

The iOS app must **never** embed the Anthropic API key. Any secret shipped in a
client binary can be extracted from the app bundle and abused to run up charges
on your account. This function keeps the key in its server environment and
forwards requests to Anthropic, so the key never leaves the server.

The proxy preserves Anthropic's request and response shapes — including SSE
streaming — so the app's existing Claude code works unchanged; only the URL it
points at differs (`<SUPABASE_URL>/functions/v1/claude-proxy`).

## Deploy

```bash
# 1. Store the Anthropic key as a function secret (never committed)
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...

# 2. Deploy the function
supabase functions deploy claude-proxy
```

`SUPABASE_URL` and `SUPABASE_ANON_KEY` are injected by the platform
automatically. By default the function verifies the caller's anon/user JWT
before running, so only your app's clients can reach it.

## Client configuration

In `JetSetter Pro/Secrets.plist` (copied from `Secrets.example.plist`):

- Set `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- The app derives the proxy URL as `<SUPABASE_URL>/functions/v1/claude-proxy`
  automatically. Override it with `CLAUDE_PROXY_URL` only if you host it
  elsewhere.

## Guardrails

The proxy intentionally limits what a tampered client can do:

- **Model allow-list** — only models in `ALLOWED_MODELS` are forwarded.
- **Token ceiling** — `max_tokens` is clamped to `MAX_OUTPUT_TOKENS` (4096).

Update `ALLOWED_MODELS` when you adopt a new model.
