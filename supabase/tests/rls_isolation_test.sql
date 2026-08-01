-- rls_isolation_test.sql
--
-- Proves the RLS policies in migrations/0001_init.sql actually isolate users.
--
-- This matters more than a normal test. The anon key is embedded in the shipped
-- app binary and is trivially extractable, so RLS is not defence-in-depth here —
-- it is the *only* thing standing between one traveller's itinerary and another's.
-- A policy edit that silently widens access would not fail any Swift test.
--
-- Every check raises on failure, so run under `psql -v ON_ERROR_STOP=1`.
--
-- Run order:  00_stubs.sql -> ../migrations/0001_init.sql -> this file

\set A '''aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'''
\set B '''bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'''

insert into auth.users (id) values (:A::uuid), (:B::uuid)
  on conflict do nothing;

-- ── Structure ────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['trips','expenses'] loop
    if not (select relrowsecurity from pg_class
            where oid = ('public.'||t)::regclass) then
      raise exception 'RLS is not enabled on public.%', t;
    end if;
    if not exists (select 1 from pg_policies
                   where schemaname='public' and tablename=t) then
      raise exception 'no RLS policy on public.%', t;
    end if;
  end loop;
end $$;

-- ── Ownership defaulting ─────────────────────────────────────────────────────
set role authenticated;
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

insert into public.trips (id, name, destination, start_date, end_date)
values ('11111111-1111-4111-8111-111111111111','Tokyo Q3','Tokyo',
        '2026-09-01','2026-09-10');
insert into public.expenses (id, amount, currency, category, merchant, date)
values ('33333333-3333-4333-8333-333333333333', 42.5,'USD','FOOD','Ichiran',
        '2026-09-02');

do $$ begin
  -- The client never sends user_id; the column default must supply it.
  if (select user_id from public.trips
      where id='11111111-1111-4111-8111-111111111111') <> auth.uid() then
    raise exception 'trips.user_id did not default to auth.uid()';
  end if;
end $$;

-- ── Isolation: B must not see A ──────────────────────────────────────────────
set request.jwt.claim.sub = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

do $$ begin
  if (select count(*) from public.trips) <> 0 then
    raise exception 'LEAK: user B can read user A''s trips';
  end if;
  if (select count(*) from public.expenses) <> 0 then
    raise exception 'LEAK: user B can read user A''s expenses';
  end if;
end $$;

-- B must not be able to write a row owned by A.
do $$ begin
  begin
    insert into public.trips (id, user_id, name, destination, start_date, end_date)
    values ('22222222-2222-4222-8222-222222222222',
            'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Forged','Nowhere',
            '2026-01-01','2026-01-02');
    raise exception 'FORGERY: user B inserted a row owned by user A';
  exception when insufficient_privilege or check_violation then
    null;  -- expected: the with-check clause rejected it
  end;
end $$;

-- B must not be able to modify or remove A's rows.
do $$
declare n int;
begin
  with u as (update public.trips set name='hijacked'
             where id='11111111-1111-4111-8111-111111111111' returning 1)
  select count(*) into n from u;
  if n <> 0 then raise exception 'TAMPER: user B updated user A''s trip'; end if;

  with d as (delete from public.trips
             where id='11111111-1111-4111-8111-111111111111' returning 1)
  select count(*) into n from d;
  if n <> 0 then raise exception 'TAMPER: user B deleted user A''s trip'; end if;
end $$;

-- ── A's data survived, and round-trips the shapes the app sends ──────────────
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

do $$ begin
  if (select name from public.trips
      where id='11111111-1111-4111-8111-111111111111') <> 'Tokyo Q3' then
    raise exception 'user A''s trip was altered';
  end if;
  -- ExpenseCategory encodes UPPERCASE on the wire ("FOOD"); the column is plain
  -- text precisely so adding a case in Swift does not need a migration.
  if (select category from public.expenses) <> 'FOOD' then
    raise exception 'expense category did not round-trip';
  end if;
end $$;

-- ── Account deletion removes the user's data (Guideline 5.1.1(v)) ────────────
-- delete-account only deletes the auth user; the cascade must do the rest.
reset role;
delete from auth.users where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

do $$ begin
  if (select count(*) from public.trips) <> 0
     or (select count(*) from public.expenses) <> 0 then
    raise exception 'account deletion left user rows behind';
  end if;
end $$;

\echo 'RLS isolation test: all checks passed'
