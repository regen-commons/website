-- Disposable local Postgres only. These stubs do not verify hosted Supabase Auth.
do $$ begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
end $$;
create schema auth;
grant usage on schema auth to anon,authenticated;
create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb);
create table auth.sessions(id uuid primary key,user_id uuid references auth.users(id),created_at timestamptz,updated_at timestamptz,not_after timestamptz);
create function auth.uid() returns uuid language sql stable as $$select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb)$$;
