-- Candidate for the migration owner. Apply after weave-project-workspaces.
-- Discovery runs through the existing restricted server role. This function is
-- not a Data API RPC, does not grant table access, and never reads saved content.
create index on weave_workspace.setup_requests(group_did, id)
  where workspace_id is null and decided_at is null;

create function weave_workspace.discovery(
  p_actor uuid, p_session uuid, p_actor_did text, p_action text, p_data jsonb
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  after_id uuid;
  selected_group_did text;
  result jsonb;
begin
  if p_actor_did is null or weave_workspace.weave_project_actor(p_actor, p_session) is distinct from p_actor_did then
    raise sqlstate 'PT401' using message = 'sign_in_required';
  end if;
  if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text) > 4000 then
    raise sqlstate 'PT400' using message = 'invalid_data';
  end if;
  if p_data ? 'cursor' then
    if jsonb_typeof(p_data->'cursor') is distinct from 'string' then
      raise sqlstate 'PT400' using message = 'invalid_data';
    end if;
    after_id := (p_data->>'cursor')::uuid;
  end if;
  if p_action = 'list_workspaces' then
    if p_data - array['cursor'] <> '{}'::jsonb then
      raise sqlstate 'PT400' using message = 'invalid_data';
    end if;
    with eligible as (
      select l.id, l.project_uri, l.repository_did, l.group_did,
        case when l.group_did is null then 'admin' else g.access_role end as access_role
      from weave_workspace.project_links l
      left join weave.initiatives i on i.id = l.solo_initiative_id and i.owner_id = p_actor
      left join weave_workspace.access_grants g on g.workspace_id = l.id and g.user_id = p_actor
        and g.member_did = p_actor_did and g.suspended_at is null
      where (after_id is null or l.id > after_id)
        and ((l.group_did is null and l.repository_did = p_actor_did and i.id is not null)
          or (l.group_did is not null and g.access_role is not null))
      order by l.id limit 26
    ), selected as (select * from eligible order by id limit 25)
    select jsonb_strip_nulls(jsonb_build_object(
      'entries', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'workspaceId', id, 'projectUri', project_uri, 'repositoryDid', repository_did, 'groupDid', group_did,
        'kind', case when group_did is null then 'personal' else 'group' end, 'accessRole', access_role
      )) order by id) from selected), '[]'::jsonb),
      'cursor', case when (select count(*) from eligible) > 25
        then (select id::text from selected order by id desc limit 1) end
    )) into result;
    return result;
  elsif p_action = 'list_setup_requests' then
    selected_group_did := p_data->>'groupDid';
    if p_data - array['cursor', 'groupDid', 'actorRole'] <> '{}'::jsonb
      or jsonb_typeof(p_data->'groupDid') is distinct from 'string'
      or weave_workspace.valid_did(selected_group_did) is distinct from true or selected_group_did = p_actor_did then
      raise sqlstate 'PT400' using message = 'invalid_data';
    end if;
    -- Only the trusted runtime supplies freshly verified Certified group roles.
    -- Membership alone never grants access to another person's pending request.
    if coalesce(p_data->>'actorRole', '') not in ('owner', 'admin') then
      raise sqlstate 'PT403' using message = 'group_admin_required';
    end if;
    with eligible as (
      select s.id, s.project_uri, s.group_did, s.requested_at
      from weave_workspace.setup_requests s
      where s.group_did = selected_group_did and s.workspace_id is null and s.decided_at is null
        and (after_id is null or s.id > after_id)
        and not exists (select 1 from weave_workspace.project_links l where l.project_uri = s.project_uri)
      order by s.id limit 26
    ), selected as (select * from eligible order by id limit 25)
    select jsonb_strip_nulls(jsonb_build_object(
      'entries', coalesce((select jsonb_agg(jsonb_build_object(
        'requestId', id, 'projectUri', project_uri, 'groupDid', selected.group_did,
        'requestedAt', to_char(requested_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      ) order by id) from selected), '[]'::jsonb),
      'cursor', case when (select count(*) from eligible) > 25
        then (select id::text from selected order by id desc limit 1) end
    )) into result;
    return result;
  end if;
  raise sqlstate 'PT400' using message = 'invalid_data';
exception
  when invalid_text_representation then
    raise sqlstate 'PT400' using message = 'invalid_data';
end $$;

revoke all on function weave_workspace.discovery(uuid, uuid, text, text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function weave_workspace.discovery(uuid, uuid, text, text, jsonb) to weave_workspace_runtime;
