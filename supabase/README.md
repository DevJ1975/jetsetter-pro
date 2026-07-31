# Supabase backend (schema-as-code)

These files define the Supabase backend that JetSetter Pro expects: tables, RLS
policies, and Edge Functions, version-controlled so they are reviewable in PRs
and reproducible.

> **Status: no live project is currently attached.** As of 2026-07-31 the
> Supabase account connected to this repo hosts nine projects, none of them
> JetSetter Pro. Treat this directory as the *definition* to create a project
> from — not as a mirror of something already running. If a live project does
> exist under a different Supabase login, verify its schema against
> `migrations/0001_init.sql` before pointing the app at it, and update this note.

Until a project exists and `API_SUPABASE_URL` / `API_SUPABASE_ANON_KEY` are set,
`SupabaseService` has no endpoint to reach: sign-in, cross-device sync, and
account deletion are inert, and the app runs on device-local and mock data only.

The iOS client talks to Supabase via a hand-rolled REST + GoTrue actor —
`JetSetter Pro/Core/Services/SupabaseService.swift` — not the `supabase-swift`
SDK. See `IOS_PARITY_NOTES.md`.

## Layout

| Path | Purpose |
|------|---------|
| `migrations/0001_init.sql` | `public.trips` + `public.expenses` tables, indexes, **RLS policies**, and grants. Column shapes match `TripRow` / `ExpenseRow` in `SupabaseService.swift`. |
| `functions/delete-account/index.ts` | Edge Function that deletes the caller's GoTrue auth user (needs `service_role`, which must never ship in the app). Invoked by `SupabaseService.deleteAccount()`. |
| `tests/00_stubs.sql` | Stand-ins for the Supabase-managed `auth` schema, so the migration can be applied to a plain Postgres. Never apply to a real project. |
| `tests/rls_isolation_test.sql` | Proves the RLS policies actually isolate users. Runs in CI on every push. |

## Verifying the schema

The migration and its policies are exercised against a real Postgres 16 in CI
(the **Supabase schema + RLS isolation** job). Locally:

```bash
psql -h localhost -U postgres -v ON_ERROR_STOP=1 -q \
  -f supabase/tests/00_stubs.sql \
  -f supabase/migrations/0001_init.sql \
  -f supabase/tests/rls_isolation_test.sql
```

It asserts that RLS is enabled and policied on both tables; that `user_id`
defaults to `auth.uid()` (the client never sends it); that a second user cannot
read, forge, update, or delete the first user's rows; that the UPPERCASE
`ExpenseCategory` wire value round-trips; and that deleting an `auth.users` row
cascades away the owner's trips and expenses — which is what makes
`delete-account` satisfy App Store Guideline 5.1.1(v).

The test was itself checked against deliberately broken migrations: relaxing a
policy to `using (true)`, dropping `enable row level security`, and removing the
`on delete cascade` each fail it.

## Applying

If a project already exists, link and push:

```bash
supabase link --project-ref <your-project-ref>
supabase db push                       # apply migrations/
supabase functions deploy delete-account
```

If one does not (see the status note above), create it first. A new project in
the current org is **$10/month**:

```bash
supabase projects create "JetSetter Pro" --org-id <org> --region us-west-1
supabase link --project-ref <new-ref>
supabase db push
supabase functions deploy delete-account
```

Then read the credentials out and put them in `Secrets.xcconfig` — the anon key,
never the service_role key:

```bash
supabase projects api-keys --project-ref <ref>   # copy the "anon" key only
```

Afterwards confirm RLS is actually on, because the anon key is extractable from
the app binary and RLS is the only thing standing between one user's data and
another's. In the dashboard: Advisors → Security should report no "RLS disabled
in public" findings for `trips` or `expenses`.

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
