# claude-proxy

Supabase Edge Function that holds the **Anthropic API key server-side** so it
never ships in the iOS app. A client-side key is extractable from the binary and
can drain the account, so it lives only here — in the `ANTHROPIC_API_KEY`
function secret.

The app POSTs the standard Anthropic Messages API body (including
`stream: true`); this function adds the key, forwards to Anthropic, and streams
the SSE response back unchanged. It enforces a **model allow-list** and a
**`max_tokens` ceiling (4096)** against a tampered client.

## Deploy

```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase functions deploy claude-proxy
```

## Wire the app

In `Config/Secrets.xcconfig`, point the app at the deployed function URL:

```
API_CLAUDE_PROXY_URL = https://<project-ref>.supabase.co/functions/v1/claude-proxy
```

The app authenticates with the Supabase anon key (already set as
`API_SUPABASE_ANON_KEY`), so no extra secret is required. Leave
`API_CLAUDE_PROXY_URL` blank and the app falls back to demo/mock AI responses
(or, in dev only, a direct `API_ANTHROPIC` key).

## Call shape

`POST {API_CLAUDE_PROXY_URL}` with `Authorization: Bearer <anon key>` and the
Anthropic Messages JSON body. Used by `AIService` (IRIS chat) and
`PackingListService` (Smart Packing List) via `Endpoints.Claude`.
