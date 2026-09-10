-- 0001_init.sql
--
-- Schema-as-code for the JetSetter Pro shared backend. This MIRRORS the live
-- Supabase project's schema-v1 contract (public.trips, public.expenses) and its
-- RLS policies so the security-critical rules are reviewable in version control
-- and reproducible if the project is ever rebuilt.
--
-- Column shapes match the iOS wire rows in
-- Core/Services/SupabaseService.swift (TripRow / ExpenseRow). `user_id` defaults
-- to auth.uid() so the client never sends it; RLS keys off it.

-- ── trips ────────────────────────────────────────────────────────────────────
create table if not exists public.trips (
    id           uuid primary key,
    user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
    name         text not null,
    destination  text not null,
    start_date   date not null,
    end_date     date not null,
    items        jsonb not null default '[]'::jsonb,
    packing_list jsonb not null default '[]'::jsonb
);

create index if not exists trips_user_id_idx on public.trips (user_id);

-- ── expenses ─────────────────────────────────────────────────────────────────
create table if not exists public.expenses (
    id        uuid primary key,
    user_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
    amount    double precision not null,
    currency  text not null,
    category  text not null,          -- UPPERCASE enum string, e.g. 'FOOD'
    merchant  text not null,
    date      date not null,
    notes     text
);

create index if not exists expenses_user_id_idx on public.expenses (user_id);

-- ── Row-Level Security ───────────────────────────────────────────────────────
-- Every row is owned by exactly one auth user; a caller may only read/write
-- their own rows. This is THE control that makes the public anon key safe: even
-- with the key extracted from the app binary, no user can reach another's data.
alter table public.trips    enable row level security;
alter table public.expenses enable row level security;

drop policy if exists "trips_owner_all" on public.trips;
create policy "trips_owner_all" on public.trips
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "expenses_owner_all" on public.expenses;
create policy "expenses_owner_all" on public.expenses
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Grants ───────────────────────────────────────────────────────────────────
-- The `authenticated` role covers both email users and anonymous-first users
-- (anonymous sign-ins also assume the authenticated role). RLS still constrains
-- every statement to the caller's own rows.
grant select, insert, update, delete on public.trips    to authenticated;
grant select, insert, update, delete on public.expenses to authenticated;
