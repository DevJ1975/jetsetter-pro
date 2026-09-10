# Supabase backend (schema-as-code)

These files **mirror the live Supabase project** that backs JetSetter Pro. The
remote project is the source of truth at runtime; this directory version-controls
its security-critical structure (tables, RLS policies, Edge Functions) so it is
reviewable in PRs and reproducible if the project is ever rebuilt.

The iOS client talks to Supabase via a hand-rolled REST + GoTrue actor —
`JetSetter Pro/Core/Services/SupabaseService.swift` — not the `supabase-swift`
SDK. See `IOS_PARITY_NOTES.md`.

## Layout

| Path | Purpose |
|------|---------|
| `migrations/0001_init.sql` | `public.trips` + `public.expenses` tables, indexes, **RLS policies**, and grants. Column shapes match `TripRow` / `ExpenseRow` in `SupabaseService.swift`. |
| `functions/delete-account/index.ts` | Edge Function that deletes the caller's GoTrue auth user (needs `service_role`, which must never ship in the app). Invoked by `SupabaseService.deleteAccount()`. |

## Applying

Using the Supabase CLI against the live project:

```bash
supabase link --project-ref <your-project-ref>
supabase db push                       # apply migrations/
supabase functions deploy delete-account
```

> The migration is written with `if not exists` / `drop policy if exists` so it
> is safe to run against the existing project — it converges the schema to this
> definition rather than assuming an empty database.

## Security model (why this matters)

- **RLS is the control that makes the public anon key safe.** The anon key is
  embedded in the app binary and is extractable; data isolation depends entirely
  on the `*_owner_all` policies keying off `auth.uid() = user_id`. If RLS were
  disabled, any user could read/write every row. Keep these policies intact.
- **Anonymous-first:** every fresh install creates an anonymous GoTrue user
  (`SupabaseService.signInAnonymously`). These accumulate remotely — add a
  scheduled server-side job to prune anonymous users with no linked email after
  a retention window. (Not app code; not in this repo.)
- **`service_role` never leaves the server.** Account deletion is delegated to
  the Edge Function above precisely so the client never holds that key.

## Not synced (intentional)

Wallet items, packing lists, disruption events, and IRIS travel signals are
persisted **device-locally** in `UserDefaults` by `SupabaseService` and have no
schema-v1 table — they do not sync across devices and are lost on device loss.
This is a deliberate product decision pending a schema bump; see the header of
`SupabaseService.swift`.
