-- JetSetter Pro — Supabase backend schema
--
-- Paste this whole file into the Supabase Dashboard → SQL Editor → New query,
-- and run it once. Idempotent (safe to re-run).
--
-- Design: each per-user collection is one table holding an opaque JSON `payload`
-- (the Swift model, encoded as-is), keyed by the model's UUID `id` and owned by
-- `user_id`. Row-Level Security restricts every row to its owner. This mirrors
-- the iOS app's SupabaseService, which stores/reads `payload` and never relies
-- on individual columns.

create extension if not exists "pgcrypto";

-- ── Tables ────────────────────────────────────────────────────────────────────
do $$
declare
  t text;
begin
  foreach t in array array['expenses','trips','wallet_items','packing_lists','disruption_events']
  loop
    execute format($f$
      create table if not exists public.%I (
        id          uuid primary key,
        user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
        payload     jsonb not null default '{}'::jsonb,
        updated_at  timestamptz not null default now()
      );
      create index if not exists %I on public.%I (user_id);
      alter table public.%I enable row level security;
    $f$, t, t || '_user_id_idx', t, t);

    -- One owner-only policy covering select/insert/update/delete.
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = t and policyname = 'own_rows'
    ) then
      execute format($p$
        create policy "own_rows" on public.%I
          for all
          using (auth.uid() = user_id)
          with check (auth.uid() = user_id);
      $p$, t);
    end if;
  end loop;
end $$;
