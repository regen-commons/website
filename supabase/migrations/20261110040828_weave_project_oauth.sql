-- Candidate for the website migration owner. This schema is never exposed through the Data API.
-- Provision a dedicated login and password separately; grant that login only the role below.
begin;
create schema weave_project_oauth;
revoke all on schema weave_project_oauth from public, anon, authenticated;
create table weave_project_oauth.records (
  kind text not null check (kind in ('state', 'receipt', 'grant')),
  key_hash text not null check (key_hash ~ '^[0-9a-f]{64}$'),
  encrypted_payload text not null,
  expires_at timestamptz not null,
  primary key (kind, key_hash)
);
create index project_oauth_expiry on weave_project_oauth.records(expires_at);
alter table weave_project_oauth.records enable row level security;
revoke all on weave_project_oauth.records from public, anon, authenticated;
do $$ begin
  if not exists(select 1 from pg_roles where rolname = 'weave_project_oauth_runtime') then
    create role weave_project_oauth_runtime nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
  end if;
end $$;
grant usage on schema weave_project_oauth to weave_project_oauth_runtime;
grant select, insert, update, delete on weave_project_oauth.records to weave_project_oauth_runtime;
create policy project_oauth_runtime on weave_project_oauth.records to weave_project_oauth_runtime using(true) with check(true);
commit;
-- Schedule pruning through the private database: delete from weave_project_oauth.records where expires_at <= now().
