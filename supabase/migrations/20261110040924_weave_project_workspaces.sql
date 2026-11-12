begin;
-- Candidate for the migration owner. Apply after private saving and Certified access.
-- A dedicated server login inherits weave_workspace_runtime. The schema is not
-- exposed through PostgREST. The caller verifies the session and Certified
-- evidence before calling a command, then SQL binds them to the affected rows.
create schema weave_workspace;
revoke all on schema weave_workspace from public, anon, authenticated, service_role;
alter default privileges in schema weave_workspace revoke execute on functions from public;

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'weave_workspace_runtime') then
    create role weave_workspace_runtime nologin nosuperuser nobypassrls nocreatedb nocreaterole noreplication;
  end if;
end $$;
grant usage on schema weave_workspace to weave_workspace_runtime;

create function weave_workspace.valid_did(p_did text) returns boolean
language sql immutable strict set search_path = '' as $$
  select length(p_did) <= 2048 and p_did ~ '^did:[a-z]+:[A-Za-z0-9._:%-]+$';
$$;

create function weave_workspace.valid_rkey(p_rkey text) returns boolean
language sql immutable strict set search_path = '' as $$
  select length(p_rkey) <= 512 and p_rkey ~ '^[A-Za-z0-9._:~-]+$' and p_rkey not in ('.', '..');
$$;

create function weave_workspace.valid_project(p_uri text, p_repository text, p_cid text) returns boolean
language sql immutable strict set search_path = '' as $$
  select weave_workspace.valid_did(p_repository)
    and p_uri = 'at://' || p_repository || '/org.hypercerts.collection/' || split_part(p_uri, '/', 5)
    and weave_workspace.valid_rkey(split_part(p_uri, '/', 5))
    and p_cid ~ '^[A-Za-z0-9]{1,128}$';
$$;

-- A solo link uses the existing initiative UUID and ownership. A team workspace
-- has its own UUID. Setup and creation never copy a draft into the team.
create table weave_workspace.project_links (
  id uuid primary key,
  project_uri text not null unique,
  repository_did text not null,
  group_did text,
  solo_initiative_id uuid unique references weave.initiatives(id) on delete cascade,
  cid text not null,
  verified_at timestamptz not null default clock_timestamp(),
  linked_by uuid references auth.users(id) on delete set null,
  check (weave_workspace.valid_project(project_uri, repository_did, cid)),
  check ((group_did is null and solo_initiative_id is not null and solo_initiative_id = id)
    or (group_did is not null and group_did = repository_did and solo_initiative_id is null))
);
create index on weave_workspace.project_links(group_did) where group_did is not null;

create table weave_workspace.setup_requests (
  id uuid primary key default gen_random_uuid(),
  project_uri text not null,
  group_did text not null,
  requester_id uuid not null references auth.users(id) on delete cascade,
  requested_at timestamptz not null default clock_timestamp(),
  workspace_id uuid references weave_workspace.project_links(id),
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,
  unique(project_uri, requester_id),
  check ((workspace_id is null) = (decided_at is null))
);

create table weave_workspace.access_grants (
  workspace_id uuid not null references weave_workspace.project_links(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  member_did text not null check (weave_workspace.valid_did(member_did)),
  access_role text not null check (access_role in ('viewer', 'editor', 'admin')),
  granted_by uuid references auth.users(id) on delete set null,
  granted_at timestamptz not null default clock_timestamp(),
  suspended_at timestamptz,
  suspended_by uuid references auth.users(id) on delete set null,
  suspension_reason text check (suspension_reason in ('membership_removed', 'revoked')),
  check ((suspended_at is null) = (suspension_reason is null)),
  primary key(workspace_id, user_id),
  unique(workspace_id, member_did)
);
create index on weave_workspace.access_grants(user_id);
create index on weave_workspace.access_grants(workspace_id) where access_role = 'admin' and suspended_at is null;

create table weave_workspace.create_intents (
  actor_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  initiative_id uuid not null references weave.initiatives(id) on delete cascade,
  expected_revision integer not null check (expected_revision > 0),
  group_handle text not null,
  project_rkey text not null check (weave_workspace.valid_rkey(project_rkey)),
  created_at timestamptz not null,
  title text not null check (length(btrim(title)) between 1 and 200),
  description text not null check (length(description) <= 800),
  status text not null default 'prepared' check (status in (
    'prepared', 'group_pending', 'group_rejected', 'group_confirmed', 'project_pending', 'project_confirmed', 'linked'
  )),
  group_did text check (weave_workspace.valid_did(group_did)),
  group_reconcile_after timestamptz,
  registration_did text check (weave_workspace.valid_did(registration_did)),
  project_uri text,
  cid text,
  workspace_id uuid references weave_workspace.project_links(id),
  updated_at timestamptz not null default clock_timestamp(),
  primary key(actor_id, request_id),
  check ((group_reconcile_after is null) = (status = 'prepared')),
  check (registration_did is null or (status not in ('prepared', 'group_rejected') and (group_did is null or group_did = registration_did))),
  check ((group_did is not null) = (status in ('group_confirmed', 'project_pending', 'project_confirmed', 'linked'))),
  check ((project_uri is not null) = (status in ('project_confirmed', 'linked')) and (project_uri is null) = (cid is null)),
  check (project_uri is null or weave_workspace.valid_project(project_uri, group_did, cid)),
  check ((workspace_id is not null) = (status = 'linked'))
);
-- A second browser request with a different request ID cannot start a second
-- registration for the same save or contend for its still unresolved handle.
create unique index on weave_workspace.create_intents(initiative_id) where status <> 'group_rejected';
create unique index on weave_workspace.create_intents(group_handle) where status not in ('linked', 'group_rejected');

alter table weave_workspace.project_links enable row level security;
alter table weave_workspace.setup_requests enable row level security;
alter table weave_workspace.access_grants enable row level security;
alter table weave_workspace.create_intents enable row level security;
revoke all on all tables in schema weave_workspace from public, anon, authenticated, service_role, weave_workspace_runtime;

create function weave_workspace.weave_project_actor(p_user_id uuid, p_session_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select min(split_part(i.provider_id, '|', 2))
  from auth.users u
  join auth.sessions s on s.user_id = u.id
  join auth.identities i on i.user_id = u.id and i.provider = 'custom:certified'
  where u.id = p_user_id and s.id = p_session_id
    and coalesce(u.is_anonymous, false) = false
    and (u.banned_until is null or u.banned_until <= statement_timestamp())
    and (s.not_after is null or s.not_after > statement_timestamp())
    and i.provider_id = 'https://certified.one|' || split_part(i.provider_id, '|', 2)
    and weave_workspace.valid_did(split_part(i.provider_id, '|', 2))
  having count(distinct i.provider_id) = 1;
$$;

create function weave_workspace.lock_save(p_actor uuid, p_id uuid, p_revision integer) returns void
language plpgsql set search_path = '' as $$
declare current_revision integer;
begin
  if p_id is null or p_revision is null or p_revision < 1 then
    raise sqlstate 'PT400' using message = 'invalid_data';
  end if;
  select revision into current_revision from weave.initiatives where id = p_id and owner_id = p_actor for update;
  if not found then raise sqlstate 'PT404' using message = 'not_found'; end if;
  if current_revision <> p_revision then raise sqlstate 'PT409' using message = 'revision_conflict'; end if;
end $$;

create function weave_workspace.link_result(
  p_link weave_workspace.project_links, p_actor uuid, p_actor_did text, p_actor_role text
) returns jsonb
language plpgsql stable set search_path = '' as $$
declare access_role text;
begin
  if p_link.id is null then return jsonb_build_object('status', 'unlinked'); end if;
  if p_link.group_did is null then
    select 'admin' into access_role from weave.initiatives where id = p_link.solo_initiative_id and owner_id = p_actor;
  elsif p_actor_role in ('owner', 'admin', 'member') then
    select g.access_role into access_role from weave_workspace.access_grants g
    where g.workspace_id = p_link.id and g.user_id = p_actor and g.member_did = p_actor_did and g.suspended_at is null;
  end if;
  if access_role is null then return jsonb_build_object('status', 'access_required'); end if;
  return jsonb_build_object('status', 'linked', 'workspaceId', p_link.id, 'accessRole', access_role,
    'projectUri', p_link.project_uri, 'cid', p_link.cid);
end $$;

create function weave_workspace.activate_group(
  p_actor uuid, p_actor_did text, p_project_uri text, p_group_did text, p_cid text
) returns weave_workspace.project_links
language plpgsql set search_path = '' as $$
declare linked weave_workspace.project_links;
begin
  -- The caller holds the canonical URI lock. The unique URI is the final
  -- guard even if a future command uses a different coordination path.
  insert into weave_workspace.project_links(id, project_uri, repository_did, group_did, cid, linked_by)
  values(gen_random_uuid(), p_project_uri, p_group_did, p_group_did, p_cid, p_actor)
  returning * into linked;
  insert into weave_workspace.access_grants(workspace_id, user_id, member_did, access_role, granted_by)
  values(linked.id, p_actor, p_actor_did, 'admin', p_actor);
  return linked;
end $$;

create function weave_workspace.creation(
  p_actor uuid, p_actor_did text, p_action text, p_data jsonb
) returns jsonb
language plpgsql set search_path = '' as $$
declare
  request uuid := (p_data->>'requestId')::uuid;
  initiative uuid := (p_data->>'initiativeId')::uuid;
  revision integer := (p_data->>'expectedRevision')::integer;
  handle text := p_data->>'groupHandle';
  rkey text := p_data->>'projectRkey';
  created_at timestamptz;
  profile jsonb := p_data->'publicProfile';
  group_did text := p_data->>'groupDid';
  uri text := p_data->>'projectUri';
  cid text := p_data->>'cid';
  intent weave_workspace.create_intents;
  linked weave_workspace.project_links;
  claimed boolean := false;
begin
  if request is null then raise sqlstate 'PT400' using message = 'invalid_data'; end if;
  perform pg_advisory_xact_lock(hashtextextended('weave-create:' || p_actor::text || ':' || request::text, 0));
  select * into intent from weave_workspace.create_intents
  where actor_id = p_actor and request_id = request for update;
  if p_action = 'begin_create' then
    if handle is null or length(handle) > 253
      or handle !~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\.[a-z]([a-z0-9-]{0,61}[a-z0-9])?$'
      or jsonb_typeof(profile) is distinct from 'object'
      or not (profile ?& array['title', 'description'])
      or profile - array['title', 'description'] <> '{}'::jsonb
      or jsonb_typeof(profile->'title') <> 'string' or length(btrim(profile->>'title')) not between 1 and 200
      or jsonb_typeof(profile->'description') <> 'string' or length(profile->>'description') > 800 then
      raise sqlstate 'PT400' using message = 'invalid_data';
    end if;
    if intent.request_id is null then
      created_at := (p_data->>'createdAt')::timestamptz;
      if weave_workspace.valid_rkey(rkey) is distinct from true or created_at is null
        or created_at < statement_timestamp() - interval '1 day'
        or created_at > statement_timestamp() + interval '5 seconds' then
        raise sqlstate 'PT400' using message = 'invalid_data';
      end if;
      perform weave_workspace.lock_save(p_actor, initiative, revision);
      if exists(select 1 from weave_workspace.project_links where solo_initiative_id = initiative) then
        raise sqlstate 'PT409' using message = 'workspace_already_linked';
      end if;
      insert into weave_workspace.create_intents(actor_id, request_id, initiative_id, expected_revision, group_handle, project_rkey, created_at, title, description)
      values(p_actor, request, initiative, revision, handle, rkey, created_at, profile->>'title', profile->>'description')
      on conflict do nothing returning * into intent;
      if intent.request_id is null then raise sqlstate 'PT409' using message = 'creation_exists'; end if;
    elsif (intent.initiative_id, intent.expected_revision, intent.group_handle, intent.title, intent.description)
      is distinct from (initiative, revision, handle, profile->>'title', profile->>'description') then
      raise sqlstate 'PT409' using message = 'request_reused';
    end if;
  elsif intent.request_id is null then
    raise sqlstate 'PT404' using message = 'not_found';
  elsif p_action = 'abandon_prepared_create' then
    if intent.status <> 'prepared' then raise sqlstate 'PT409' using message = 'creation_conflict'; end if;
    delete from weave_workspace.create_intents where actor_id = p_actor and request_id = request;
    return jsonb_build_object('status', 'abandoned');
  elsif p_action = 'claim_create_step' then
    if p_data->>'step' = 'group' and intent.status = 'prepared' then
      perform weave_workspace.lock_save(p_actor, intent.initiative_id, intent.expected_revision);
      intent.status := 'group_pending';
      -- A concurrent retry must not reconcile an occupied handle while the
      -- initial provider call can still return a definitive conflict.
      intent.group_reconcile_after := clock_timestamp() + interval '45 seconds';
      claimed := true;
    elsif p_data->>'step' = 'project' and intent.status = 'group_confirmed' then
      intent.status := 'project_pending';
      claimed := true;
    elsif coalesce(p_data->>'step', '') not in ('group', 'project') then
      raise sqlstate 'PT400' using message = 'invalid_data';
    end if;
  elsif p_action = 'reject_group_claim' then
    if intent.status = 'group_pending' and intent.registration_did is null then
      intent.status := 'group_rejected';
    elsif intent.status <> 'group_rejected' then
      raise sqlstate 'PT409' using message = 'creation_conflict';
    end if;
  elsif p_action = 'record_registration_receipt' then
    if handle is distinct from intent.group_handle
      or weave_workspace.valid_did(group_did) is distinct from true or group_did = p_actor_did then
      raise sqlstate 'PT403' using message = 'project_verification_required';
    end if;
    if intent.registration_did is null and (intent.status = 'group_pending' or intent.group_did = group_did) then
      intent.registration_did := group_did;
    elsif intent.registration_did is distinct from group_did then
      raise sqlstate 'PT409' using message = 'creation_conflict';
    end if;
  elsif p_action = 'record_group' then
    if handle is distinct from intent.group_handle or p_data->>'actorRole' is distinct from 'owner'
      or weave_workspace.valid_did(group_did) is distinct from true or group_did = p_actor_did then
      raise sqlstate 'PT403' using message = 'group_owner_required';
    end if;
    if intent.registration_did is not null and intent.registration_did <> group_did then
      raise sqlstate 'PT409' using message = 'creation_conflict';
    end if;
    if intent.status = 'group_pending' then
      if intent.registration_did is null and clock_timestamp() < intent.group_reconcile_after then
        raise sqlstate 'PT409' using message = 'group_registration_pending';
      end if;
      intent.group_did := group_did;
      intent.status := 'group_confirmed';
    elsif intent.group_did is distinct from group_did then
      raise sqlstate 'PT409' using message = 'creation_conflict';
    end if;
  elsif p_action in ('record_project', 'finish_create') then
    if intent.group_did is null or group_did is distinct from intent.group_did
      or p_data->>'repositoryDid' is distinct from intent.group_did
      or p_data->>'actorRole' is distinct from 'owner'
      or uri is distinct from ('at://' || intent.group_did || '/org.hypercerts.collection/' || intent.project_rkey)
      or weave_workspace.valid_project(uri, group_did, cid) is distinct from true then
      raise sqlstate 'PT403' using message = 'project_verification_required';
    end if;
    if p_action = 'record_project' and intent.status = 'project_pending' then
      intent.project_uri := uri;
      intent.cid := cid;
      intent.status := 'project_confirmed';
    elsif p_action = 'finish_create' and intent.status = 'project_confirmed' then
      -- The approved public snapshot is durable. Edits to the separate
      -- private save after approval do not strand the confirmed project.
      perform pg_advisory_xact_lock(hashtextextended('weave-project:' || uri, 0));
      perform 1 from weave.initiatives where id = intent.initiative_id and owner_id = p_actor for update;
      if not found then raise sqlstate 'PT404' using message = 'not_found'; end if;
      select * into linked from weave_workspace.project_links where project_uri = uri;
      if linked.id is null then
        linked := weave_workspace.activate_group(p_actor, p_actor_did, uri, group_did, cid);
      elsif weave_workspace.link_result(linked, p_actor, p_actor_did, 'owner')->>'status' <> 'linked' then
        return jsonb_build_object('status', 'access_required');
      end if;
      intent.workspace_id := linked.id;
      intent.cid := cid;
      intent.status := 'linked';
    elsif intent.status not in ('project_confirmed', 'linked') then
      raise sqlstate 'PT409' using message = 'creation_conflict';
    end if;
  end if;
  if p_action not in ('begin_create', 'get_create') then
    update weave_workspace.create_intents set status = intent.status, group_did = intent.group_did,
      project_uri = intent.project_uri, cid = intent.cid, workspace_id = intent.workspace_id,
      registration_did = intent.registration_did, group_reconcile_after = intent.group_reconcile_after,
      updated_at = clock_timestamp()
    where actor_id = p_actor and request_id = request;
  end if;
  return jsonb_strip_nulls(jsonb_build_object('requestId', intent.request_id, 'initiativeId', intent.initiative_id,
    'expectedRevision', intent.expected_revision, 'groupHandle', intent.group_handle, 'projectRkey', intent.project_rkey,
    'createdAt', to_char(intent.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'publicProfile', jsonb_build_object('title', intent.title, 'description', intent.description), 'status', intent.status,
    'groupDid', intent.group_did, 'registrationDid', intent.registration_did,
    'groupReconcileAfter', to_char(intent.group_reconcile_after at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'projectUri', intent.project_uri, 'cid', intent.cid, 'workspaceId', intent.workspace_id,
    'claimed', case when p_action = 'claim_create_step' then claimed end));
end $$;

create function weave_workspace.command(
  p_actor uuid, p_session uuid, p_actor_did text, p_action text, p_data jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uri text;
  repository text;
  group_did text;
  actor_role text;
  cid text;
  initiative uuid;
  recipient_did text;
  recipient_ids uuid[];
  access_role text;
  observed_at timestamptz;
  self_suspension boolean;
  link weave_workspace.project_links;
  setup weave_workspace.setup_requests;
begin
  if p_actor_did is null or weave_workspace.weave_project_actor(p_actor, p_session) is distinct from p_actor_did then
    raise sqlstate 'PT401' using message = 'sign_in_required';
  end if;
  if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text) > 12000 then
    raise sqlstate 'PT400' using message = 'invalid_data';
  end if;
  if p_action in ('begin_create', 'get_create', 'abandon_prepared_create', 'claim_create_step', 'record_registration_receipt', 'reject_group_claim', 'record_group', 'record_project', 'finish_create') then
    return weave_workspace.creation(p_actor, p_actor_did, p_action, p_data);
  end if;

  uri := p_data->>'projectUri';
  repository := p_data->>'repositoryDid';
  group_did := p_data->>'groupDid';
  actor_role := p_data->>'actorRole';
  recipient_did := p_data->>'recipientDid';
  self_suspension := p_action = 'suspend_access' and recipient_did is not distinct from p_actor_did
    and p_data->>'recipientRole' is not distinct from 'absent'
    and coalesce(actor_role, 'absent') = 'absent';
  if self_suspension then actor_role := 'absent'; end if;
  cid := p_data->>'cid';
  if weave_workspace.valid_project(uri, repository, cid) is distinct from true
    or (group_did is null and repository <> p_actor_did)
    or (group_did is not null and (group_did <> repository or group_did = p_actor_did
      or coalesce(actor_role, '') not in ('owner', 'admin', 'member', 'absent'))) then
    raise sqlstate 'PT403' using message = 'project_verification_required';
  end if;
  if p_action = 'lookup' then
    select * into link from weave_workspace.project_links where project_uri = uri;
    if link.id is not null and link.group_did is distinct from group_did then
      return jsonb_build_object('status', 'access_required');
    end if;
    return weave_workspace.link_result(link, p_actor, p_actor_did, actor_role);
  end if;

  -- Serialize activation and grant changes at the canonical URI, including
  -- when no row exists yet. Keep project and setup mutations in this order.
  perform pg_advisory_xact_lock(hashtextextended('weave-project:' || uri, 0));
  select * into link from weave_workspace.project_links where project_uri = uri;
  if link.id is not null and link.group_did is distinct from group_did then
    return jsonb_build_object('status', 'access_required');
  end if;

  if p_action = 'link' and group_did is null then
    initiative := (p_data->>'initiativeId')::uuid;
    perform weave_workspace.lock_save(p_actor, initiative, (p_data->>'expectedRevision')::integer);
    if link.id is null then
      if exists(select 1 from weave_workspace.create_intents where initiative_id = initiative and status <> 'group_rejected') then
        raise sqlstate 'PT409' using message = 'creation_exists';
      end if;
      insert into weave_workspace.project_links(id, project_uri, repository_did, solo_initiative_id, cid, linked_by)
      values(initiative, uri, repository, initiative, cid, p_actor) on conflict do nothing returning * into link;
      if link.id is null then raise sqlstate 'PT409' using message = 'workspace_already_linked'; end if;
    end if;
    return weave_workspace.link_result(link, p_actor, p_actor_did, actor_role);
  end if;
  if group_did is null then raise sqlstate 'PT403' using message = 'group_required'; end if;

  if p_action = 'request_setup' then
    if actor_role = 'absent' then raise sqlstate 'PT403' using message = 'group_membership_required'; end if;
    if link.id is not null then return weave_workspace.link_result(link, p_actor, p_actor_did, actor_role); end if;
    insert into weave_workspace.setup_requests(project_uri, group_did, requester_id)
    values(uri, group_did, p_actor) on conflict(project_uri, requester_id) do nothing;
    select * into setup from weave_workspace.setup_requests where project_uri = uri and requester_id = p_actor;
    return jsonb_build_object('status', 'pending', 'requestId', setup.id);
  elsif p_action in ('approve_setup', 'link') then
    if actor_role not in ('admin', 'owner') then raise sqlstate 'PT403' using message = 'group_admin_required'; end if;
    if p_action = 'approve_setup' then
      select * into setup from weave_workspace.setup_requests
      where id = (p_data->>'requestId')::uuid and project_uri = uri and setup_requests.group_did = repository
      for update;
      if setup.id is null then raise sqlstate 'PT404' using message = 'not_found'; end if;
    end if;
    if link.id is not null then return weave_workspace.link_result(link, p_actor, p_actor_did, actor_role); end if;
    link := weave_workspace.activate_group(p_actor, p_actor_did, uri, group_did, cid);
    if setup.id is not null then
      update weave_workspace.setup_requests set workspace_id = link.id, decided_by = p_actor,
        decided_at = clock_timestamp() where id = setup.id;
    end if;
    return weave_workspace.link_result(link, p_actor, p_actor_did, actor_role);
  end if;

  if (self_suspension or (p_action = 'suspend_access' and actor_role = 'owner')) and link.id is null then
    return jsonb_build_object('status', 'suspended');
  end if;
  if link.id is null or (link.id is distinct from (p_data->>'workspaceId')::uuid
      and not (p_data->>'workspaceId' is null and (self_suspension
        or (p_action in ('suspend_access', 'recover_admin') and actor_role = 'owner')))) then
    raise sqlstate 'PT404' using message = 'not_found';
  end if;
  if p_action = 'recover_admin' then
    if actor_role <> 'owner' then raise sqlstate 'PT403' using message = 'group_owner_required'; end if;
    if exists (select 1 from weave_workspace.access_grants g
        where g.workspace_id = link.id and g.access_role = 'admin' and g.suspended_at is null) then
      raise sqlstate 'PT409' using message = 'active_workspace_admin';
    end if;
    insert into weave_workspace.access_grants(workspace_id, user_id, member_did, access_role, granted_by)
    values(link.id, p_actor, p_actor_did, 'admin', p_actor)
    on conflict(workspace_id, user_id) do update set member_did = excluded.member_did, access_role = 'admin',
      granted_by = p_actor, granted_at = clock_timestamp(), suspended_at = null,
      suspended_by = null, suspension_reason = null;
    return weave_workspace.link_result(link, p_actor, p_actor_did, actor_role);
  end if;
  if not (self_suspension or (p_action = 'suspend_access' and actor_role = 'owner'))
    and weave_workspace.link_result(link, p_actor, p_actor_did, actor_role)->>'accessRole' is distinct from 'admin' then
    raise sqlstate 'PT403' using message = 'workspace_admin_required';
  end if;
  if weave_workspace.valid_did(recipient_did) is distinct from true then
    raise sqlstate 'PT400' using message = 'invalid_data';
  end if;
  if p_action in ('check_recipient', 'grant_access') then
    select array_agg(u.id) into recipient_ids from auth.users u
    where coalesce(u.is_anonymous, false) = false and (u.banned_until is null or u.banned_until <= statement_timestamp())
      and exists(select 1 from auth.identities i where i.user_id = u.id
        and i.provider = 'custom:certified' and i.provider_id = 'https://certified.one|' || recipient_did);
    if cardinality(recipient_ids) is distinct from 1 then
      raise sqlstate 'PT404' using message = 'recipient_not_found';
    end if;
    if p_action = 'check_recipient' then return jsonb_build_object('status', 'verified'); end if;
  end if;
  -- A verification observed before a concurrent change must not undo it.
  observed_at := (p_data->>'observedAt')::timestamptz;
  if p_action = 'revoke_access' then observed_at := clock_timestamp(); end if;
  if observed_at is null or observed_at < statement_timestamp() - interval '1 minute'
    or observed_at > statement_timestamp() + interval '5 seconds' then
    raise sqlstate 'PT409' using message = 'membership_evidence_stale';
  end if;
  if p_action = 'grant_access' then
    access_role := p_data->>'accessRole';
    if coalesce(p_data->>'recipientRole', '') not in ('member', 'admin', 'owner') then
      raise sqlstate 'PT403' using message = 'group_membership_required';
    end if;
    if coalesce(access_role, '') not in ('viewer', 'editor', 'admin') then
      raise sqlstate 'PT400' using message = 'invalid_data';
    end if;
    insert into weave_workspace.access_grants(workspace_id, user_id, member_did, access_role, granted_by, granted_at)
    values(link.id, recipient_ids[1], recipient_did, access_role, p_actor, observed_at)
    on conflict(workspace_id, user_id) do update set member_did = excluded.member_did,
      access_role = excluded.access_role, granted_by = p_actor, granted_at = excluded.granted_at, suspended_at = null,
      suspended_by = null, suspension_reason = null
    where excluded.granted_at > greatest(access_grants.granted_at, access_grants.suspended_at);
    if not found then raise sqlstate 'PT409' using message = 'membership_evidence_stale'; end if;
    return jsonb_build_object('status', 'granted');
  elsif p_action in ('suspend_access', 'revoke_access') then
    if p_action = 'suspend_access' and p_data->>'recipientRole' is distinct from 'absent' then
      raise sqlstate 'PT403' using message = 'group_removal_unconfirmed';
    end if;
    update weave_workspace.access_grants g set suspended_at = greatest(observed_at, g.granted_at, g.suspended_at),
      suspended_by = p_actor, suspension_reason = case when p_action = 'revoke_access' then 'revoked' else 'membership_removed' end
    where g.workspace_id = link.id and g.member_did = recipient_did
      and (p_action = 'revoke_access' or observed_at > greatest(g.granted_at, g.suspended_at));
    return jsonb_build_object('status', case when p_action = 'revoke_access' then 'revoked' else 'suspended' end);
  end if;
  raise sqlstate 'PT400' using message = 'invalid_data';
exception
  when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
    raise sqlstate 'PT400' using message = 'invalid_data';
end $$;

-- Internal helpers are never an entry point. Grant the server only the two
-- checked operations and no table access, even in the dedicated schema.
revoke all on all functions in schema weave_workspace from public, anon, authenticated, service_role, weave_workspace_runtime;
grant execute on function weave_workspace.weave_project_actor(uuid, uuid),
  weave_workspace.command(uuid, uuid, text, text, jsonb) to weave_workspace_runtime;

commit;
