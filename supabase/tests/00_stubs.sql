-- 00_stubs.sql — minimal stand-ins for the Supabase-managed pieces.
--
-- Applied before migrations/0001_init.sql when testing against a plain Postgres
-- (CI, or a local instance). Supabase provides all of this on a real project;
-- none of it should ever be applied there.
--
-- auth.uid() normally derives from the caller's JWT `sub` claim. Here it reads a
-- session GUC so a test can impersonate different users on one connection.

create schema if not exists auth;

create table if not exists auth.users (id uuid primary key);

create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated;
  end if;
end $$;

grant usage on schema public to authenticated;

-- Real Supabase grants this too. Without it, an RLS *policy* still evaluates
-- auth.uid() fine (policy expressions run as the table owner), but a direct
-- call from a test running as `authenticated` fails on schema permissions.
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
