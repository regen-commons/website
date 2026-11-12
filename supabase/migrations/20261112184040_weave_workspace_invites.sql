-- Candidate for the migration owner. Apply after weave-project-workspaces.
-- A pending invitation links a future signed-in DID to a review queue. Claiming
-- never joins a Certified group and never grants private workspace access.
create table weave_workspace.pending_invites (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references weave_workspace.project_links(id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[a-f0-9]{64}$'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default statement_timestamp(),
  expires_at timestamptz not null default statement_timestamp() + interval '7 days',
  claimed_by uuid references auth.users(id) on delete set null,
  claimed_did text check (weave_workspace.valid_did(claimed_did)),
  claimed_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  approved_role text check (approved_role in ('viewer','editor','admin')),
  check (expires_at > created_at and expires_at <= created_at + interval '7 days'),
  check ((claimed_did is null) = (claimed_at is null)),
  check ((approved_at is null) = (approved_role is null)),
  check (approved_at is null or (claimed_at is not null and revoked_at is null))
);
create index on weave_workspace.pending_invites(workspace_id,id);
alter table weave_workspace.pending_invites enable row level security;
revoke all on weave_workspace.pending_invites from public,anon,authenticated,service_role,weave_workspace_runtime;

create function weave_workspace.invitation_summary(p_invite weave_workspace.pending_invites) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'inviteId',p_invite.id,
    'status',case when p_invite.revoked_at is not null then 'revoked'
      when p_invite.approved_at is not null then 'approved'
      when p_invite.expires_at <= statement_timestamp() then 'expired'
      when p_invite.claimed_at is not null then 'claimed' else 'pending' end,
    'createdAt',to_char(p_invite.created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'expiresAt',to_char(p_invite.expires_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'claimedDid',p_invite.claimed_did,
    'claimedAt',to_char(p_invite.claimed_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'approvedAt',to_char(p_invite.approved_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'revokedAt',to_char(p_invite.revoked_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  ));
$$;

create function weave_workspace.invitation(
  p_actor uuid,p_session uuid,p_actor_did text,p_action text,p_data jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  invitation weave_workspace.pending_invites;
  link weave_workspace.project_links;
  access jsonb;
  result jsonb;
  token_hash text;
  after_id uuid;
  workspace uuid;
begin
  if p_actor_did is null or weave_workspace.weave_project_actor(p_actor,p_session) is distinct from p_actor_did then
    raise sqlstate 'PT401' using message = 'sign_in_required';
  end if;
  if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text) > 12000 then
    raise sqlstate 'PT400' using message = 'invalid_data';
  end if;
  if p_action = 'claim' then
    if p_data - array['tokenHash'] <> '{}'::jsonb or coalesce(p_data->>'tokenHash','') !~ '^[a-f0-9]{64}$' then
      raise sqlstate 'PT400' using message = 'invalid_data';
    end if;
    select * into invitation from weave_workspace.pending_invites i where i.token_hash = p_data->>'tokenHash' for update;
    if p_actor_did is null or weave_workspace.weave_project_actor(p_actor,p_session) is distinct from p_actor_did then
      raise sqlstate 'PT401' using message = 'sign_in_required';
    end if;
    if invitation.id is null or invitation.expires_at <= clock_timestamp()
      or invitation.revoked_at is not null or invitation.approved_at is not null
      or (invitation.claimed_at is not null and (invitation.claimed_did is distinct from p_actor_did
        or invitation.claimed_by is distinct from p_actor)) then
      raise sqlstate 'PT404' using message = 'invitation_not_found';
    end if;
    if invitation.claimed_at is null then
      update weave_workspace.pending_invites set claimed_by = p_actor,claimed_did = p_actor_did,claimed_at = clock_timestamp()
      where id = invitation.id;
    end if;
    return jsonb_build_object('status','pending_review','inviteId',invitation.id,
      'expiresAt',to_char(invitation.expires_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
  end if;
  if p_data - array['workspaceId','projectUri','repositoryDid','groupDid','cid','actorRole',
      'tokenHash','cursor','inviteId','recipientDid','accessRole','recipientRole','observedAt'] <> '{}'::jsonb then
    raise sqlstate 'PT400' using message = 'invalid_data';
  end if;
  workspace := (p_data->>'workspaceId')::uuid;
  -- Share the canonical project lock with access changes and invitation approval.
  perform pg_advisory_xact_lock(hashtextextended('weave-project:' || (p_data->>'projectUri'),0));
  if weave_workspace.weave_project_actor(p_actor,p_session) is distinct from p_actor_did then
    raise sqlstate 'PT401' using message = 'sign_in_required';
  end if;
  access := weave_workspace.command(p_actor,p_session,p_actor_did,'lookup',p_data);
  if access->>'workspaceId' is distinct from workspace::text or access->>'accessRole' is distinct from 'admin' then
    raise sqlstate 'PT403' using message = 'workspace_admin_required';
  end if;
  select * into link from weave_workspace.project_links where id = workspace and group_did is not null;
  if link.id is null then raise sqlstate 'PT403' using message = 'group_required'; end if;
  if p_action = 'create' then
    token_hash := p_data->>'tokenHash';
    if token_hash is null or token_hash !~ '^[a-f0-9]{64}$' then raise sqlstate 'PT400' using message = 'invalid_data'; end if;
    if (select count(*) from weave_workspace.pending_invites i where i.workspace_id = workspace
      and i.revoked_at is null and i.approved_at is null and i.expires_at > clock_timestamp()) >= 25 then
      raise sqlstate 'PT429' using message = 'invitation_limit_reached';
    end if;
    insert into weave_workspace.pending_invites(workspace_id,token_hash,created_by)
      values(workspace,token_hash,p_actor) returning * into invitation;
    return jsonb_build_object('status','pending','inviteId',invitation.id,
      'expiresAt',to_char(invitation.expires_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
  elsif p_action = 'list' then
    if p_data ? 'cursor' then
      if jsonb_typeof(p_data->'cursor') is distinct from 'string' then raise sqlstate 'PT400' using message = 'invalid_data'; end if;
      after_id := (p_data->>'cursor')::uuid;
    end if;
    with eligible as (
      select i.* from weave_workspace.pending_invites i where i.workspace_id = workspace
        and (after_id is null or i.id > after_id) order by i.id limit 26
    ), selected as (select * from eligible order by id limit 25)
    select jsonb_strip_nulls(jsonb_build_object(
      'invitations',coalesce((select jsonb_agg(weave_workspace.invitation_summary(i) order by i.id)
        from selected s join weave_workspace.pending_invites i using(id)),'[]'::jsonb),
      'cursor',case when (select count(*) from eligible) > 25 then (select id::text from selected order by id desc limit 1) end
    )) into result;
    return result;
  elsif p_action not in ('check','approve','revoke') then
    raise sqlstate 'PT400' using message = 'invalid_data';
  end if;
  select * into invitation from weave_workspace.pending_invites i
    where i.id = (p_data->>'inviteId')::uuid and i.workspace_id = workspace for update;
  if invitation.id is null then raise sqlstate 'PT404' using message = 'invitation_not_found'; end if;
  if p_action = 'revoke' then
    if invitation.approved_at is not null then return jsonb_build_object('status','already_reviewed','inviteId',invitation.id); end if;
    update weave_workspace.pending_invites set revoked_at = coalesce(revoked_at,clock_timestamp()),revoked_by = p_actor
      where id = invitation.id;
    return jsonb_build_object('status','revoked','inviteId',invitation.id);
  end if;
  if invitation.revoked_at is not null or invitation.expires_at <= clock_timestamp()
    or invitation.claimed_at is null or invitation.claimed_did is distinct from p_data->>'recipientDid'
    or invitation.claimed_by is null then raise sqlstate 'PT404' using message = 'invitation_not_found'; end if;
  if invitation.approved_at is not null then return jsonb_build_object('status','already_reviewed','inviteId',invitation.id); end if;
  if p_action = 'check' then return jsonb_build_object('status','verified','inviteId',invitation.id); end if;
  -- The existing command owns unique Certified account resolution, freshness,
  -- explicit grant rules and role validation. Approval and grant commit together.
  perform weave_workspace.command(p_actor,p_session,p_actor_did,'grant_access',p_data);
  update weave_workspace.pending_invites set approved_at = clock_timestamp(),approved_by = p_actor,
    approved_role = p_data->>'accessRole' where id = invitation.id;
  return jsonb_build_object('status','granted','inviteId',invitation.id);
exception
  when invalid_text_representation or unique_violation then
    raise sqlstate 'PT400' using message = 'invalid_data';
end $$;

revoke all on function weave_workspace.invitation_summary(weave_workspace.pending_invites)
  from public,anon,authenticated,service_role,weave_workspace_runtime;
revoke all on function weave_workspace.invitation(uuid,uuid,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function weave_workspace.invitation(uuid,uuid,text,text,jsonb) to weave_workspace_runtime;
