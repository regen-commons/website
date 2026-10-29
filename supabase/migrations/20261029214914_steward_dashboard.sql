-- Read-only steward pilot. No acceptance, publication, intake, or role-grant API.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table private.steward_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  active boolean not null default false,
  granted_at timestamptz not null default now()
);
alter table private.steward_roles enable row level security;
revoke all on private.steward_roles from public, anon, authenticated;

-- A narrowly scoped internal lookup requires elevated access to server-owned
-- roles and Auth sessions. Never accepts a user ID from its caller.
create function private.is_active_steward() returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from private.steward_roles r
    join auth.sessions s on s.user_id = r.user_id
    where r.user_id = auth.uid() and r.active
      and s.id::text = (auth.jwt() ->> 'session_id')
      and (s.not_after is null or s.not_after > now())
  );
$$;
revoke all on function private.is_active_steward() from public, anon, authenticated;
grant execute on function private.is_active_steward() to authenticated;

create function public.steward_access() returns boolean
language sql stable security invoker set search_path = '' as $$
  select private.is_active_steward();
$$;
revoke all on function public.steward_access() from public, anon;
grant execute on function public.steward_access() to authenticated;

create table public.members (
  id uuid primary key default gen_random_uuid(),
  source_notion_id text unique,
  name text not null,
  member_type text not null check (member_type in ('individual', 'organization')),
  publication_state text not null default 'draft' check (publication_state in ('draft', 'published', 'hidden')),
  location text not null default '',
  summary text not null default '',
  website text,
  focus_areas text[] not null default '{}',
  contribution_areas text[] not null default '{}',
  created_at timestamptz not null default now()
);
create table public.applications (
  id uuid primary key default gen_random_uuid(),
  source_notion_id text unique,
  request_id uuid unique,
  display_name text not null,
  applicant_type text not null check (applicant_type in ('individual', 'organization')),
  email text not null,
  submitted_at timestamptz not null default now(),
  review_state text not null default 'pending',
  cohort text,
  nominator text,
  revision integer not null default 1 check (revision > 0),
  answers_schema_version integer not null default 1 check (answers_schema_version > 0),
  original_answers jsonb not null check (jsonb_typeof(original_answers) = 'object'),
  member_id uuid unique references public.members(id)
);
comment on column public.applications.review_state is 'Descriptive review state; this slice defines no decision transitions or authority.';
comment on column public.applications.member_id is 'Optional curated profile draft. Linking a profile does not accept an application or publish a member.';
create index applications_submitted on public.applications(submitted_at desc, id);
create table public.affiliations (
  member_id uuid not null references public.members(id),
  organization_id uuid not null references public.members(id),
  primary key (member_id, organization_id),
  check (member_id <> organization_id)
);
create index affiliations_organization on public.affiliations(organization_id);
create table public.contributions (
  id uuid primary key default gen_random_uuid(),
  source_notion_id text unique,
  title text not null,
  publication_state text not null default 'draft' check (publication_state in ('draft', 'published', 'hidden')),
  description text not null default '',
  contribution_type text,
  stage text,
  capital_forms text[] not null default '{}',
  tier text,
  terms text,
  license text,
  tags text[] not null default '{}',
  contributed_at timestamptz
);
create table public.contribution_members (
  contribution_id uuid not null references public.contributions(id),
  member_id uuid not null references public.members(id),
  primary key (contribution_id, member_id)
);
create index contribution_members_member on public.contribution_members(member_id);
create table public.review_events (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications(id),
  actor_id uuid references auth.users(id),
  event_type text not null,
  reviewed_revision integer not null check (reviewed_revision > 0),
  note text not null default '',
  created_at timestamptz not null default now()
);
create index review_events_application on public.review_events(application_id, created_at);
create index review_events_actor on public.review_events(actor_id);

-- Explicit grants override project defaults. Even active stewards can only read.
-- Public publication is not activated: the existing public site still uses Notion.
do $$
declare t text;
begin
  foreach t in array array['applications','members','affiliations','contributions','contribution_members','review_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create policy steward_read on public.%I for select to authenticated using ((select private.is_active_steward()))', t);
  end loop;
end $$;
