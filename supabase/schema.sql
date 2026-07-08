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

-- ── Email Intelligence (forwarding inbox) ────────────────────────────────────
-- A per-user forwarding alias plus a holding table for forwarded emails.
-- Rows are INSERTED only by the `inbound-email` Edge Function (service role);
-- the signed-in user can read and delete their own rows (the app deletes each
-- raw email immediately after parsing it on-device).

create table if not exists public.email_aliases (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  alias       text not null unique,
  created_at  timestamptz not null default now()
);
alter table public.email_aliases enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'email_aliases' and policyname = 'own_alias'
  ) then
    create policy "own_alias" on public.email_aliases
      for all
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
end $$;

create table if not exists public.inbound_emails (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  raw_email   text not null,
  received_at timestamptz not null default now(),
  processed   boolean not null default false
);
create index if not exists inbound_emails_user_id_idx on public.inbound_emails (user_id);
alter table public.inbound_emails enable row level security;

do $$
begin
  -- Users read + delete their own forwarded mail; inserts come only from the
  -- service-role Edge Function, so no insert policy is defined for users.
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'inbound_emails' and policyname = 'own_inbound_select'
  ) then
    create policy "own_inbound_select" on public.inbound_emails
      for select using (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'inbound_emails' and policyname = 'own_inbound_delete'
  ) then
    create policy "own_inbound_delete" on public.inbound_emails
      for delete using (auth.uid() = user_id);
  end if;
end $$;
