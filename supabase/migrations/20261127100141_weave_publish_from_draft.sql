-- Candidate only. Apply after weave-public-support-listings; no hosted migration is implied.
-- DL-155, step 3 of the removal plan in docs/platform/08-accounts-and-saving.md: a need or offer is
-- published from the device draft, with no private save first.
--
-- A personal project link no longer needs a saved card. The person whose verified Certified DID owns
-- the project's repository holds it, which is the identity the link was already bound to. Deleting a
-- saved card (only an account's deletion does; the API's delete guard refuses a linked card) no longer
-- cascades to its project link or to Weave's record of its published listings.
-- Listings published from a private save keep their entry checks and edit triggers until saves retire;
-- listings published from a draft are checked when reviewed and never follow later edits, since Weave
-- never sees the draft again. Every function keeps its owner and grants through create or replace.
-- Apply this before deploying the API and app that send card-less links and draft reviews, and merge
-- that code only afterwards, since Weave deploys on merge. On the older functions that API's card-less
-- link and draft review are refused, so nothing is published, but Make It Public may already have
-- created the person's Certified project. The API and app before it keep working here: the saved-card
-- commands are unchanged.
-- `discovery` stays as applied: `list_workspaces` lists a personal link only with the saved card it is
-- anchored on, because the app opens a listed personal workspace as that card. A card-less link is
-- reached by its project instead, through `lookup` and `link`, under the same verified-DID rule.

do $$
begin
  if to_regprocedure('private.weave_public_support_listings(text)') is null
      or to_regclass('weave_workspace.support_listings') is null then
    raise exception 'apply weave-support-publication and weave-public-support-listings first';
  end if;
end;
$$;

alter table weave_workspace.project_links drop constraint project_links_check1;
alter table weave_workspace.project_links add constraint project_links_owner_check check (
  (group_did is null and (solo_initiative_id is null or solo_initiative_id = id))
  or (group_did is not null and group_did = repository_did and solo_initiative_id is null));
alter table weave_workspace.project_links drop constraint project_links_solo_initiative_id_fkey;
alter table weave_workspace.project_links add constraint project_links_solo_initiative_id_fkey
  foreign key (solo_initiative_id) references weave.initiatives(id) on delete set null;

-- A saved card's ID is chosen by the browser. A personal link no card anchors (one made from a draft,
-- or one whose card was deleted) keeps its ID, so a new card is refused there: it would otherwise read
-- as that project's workspace to the matching view and to the saved review. A team save is a group
-- link's own row, and a card already anchoring its link conflicts on its key as before.
create function weave_workspace.initiative_link_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists(select from weave_workspace.project_links l where l.id = new.id and l.group_did is null
      and l.solo_initiative_id is distinct from new.id) then
    raise sqlstate 'PT409' using message = 'revision_conflict';
  end if;
  return new;
end $$;
create trigger initiative_link_guard before insert on weave.initiatives
  for each row execute function weave_workspace.initiative_link_guard();
revoke all on function weave_workspace.initiative_link_guard()
  from public, anon, authenticated, service_role, weave_workspace_runtime;

alter table weave_workspace.support_reviews
  add column source text not null default 'saved' check (source in ('saved','draft'));
alter table weave_workspace.support_listings
  add column source text not null default 'saved' check (source in ('saved','draft'));

create or replace function weave_workspace.link_result(
  p_link weave_workspace.project_links, p_actor uuid, p_actor_did text, p_actor_role text
) returns jsonb
language plpgsql stable set search_path = '' as $$
declare access_role text;
begin
  if p_link.id is null then return jsonb_build_object('status', 'unlinked'); end if;
  if p_link.group_did is null then
    -- DL-155: whoever's verified Certified DID owns the repository holds a personal link, with or
    -- without a saved card. Every caller has already checked p_actor_did against the session.
    if p_link.repository_did = p_actor_did then access_role := 'admin'; end if;
  elsif p_actor_role in ('owner', 'admin', 'member') then
    select g.access_role into access_role from weave_workspace.access_grants g
    where g.workspace_id = p_link.id and g.user_id = p_actor and g.member_did = p_actor_did and g.suspended_at is null;
  end if;
  if access_role is null then return jsonb_build_object('status', 'access_required'); end if;
  return jsonb_build_object('status', 'linked', 'workspaceId', p_link.id, 'accessRole', access_role,
    'projectUri', p_link.project_uri, 'cid', p_link.cid);
end $$;


create or replace function weave_workspace.command(
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

  if p_action = 'link' and group_did is null and not (p_data ? 'initiativeId') then
    -- DL-155: publishing from a draft links the person's own project without a saved card.
    if link.id is null then
      insert into weave_workspace.project_links(id, project_uri, repository_did, cid, linked_by)
      values(gen_random_uuid(), uri, repository, cid, p_actor) on conflict do nothing returning * into link;
      if link.id is null then raise sqlstate 'PT409' using message = 'workspace_already_linked'; end if;
    end if;
    return weave_workspace.link_result(link, p_actor, p_actor_did, actor_role);
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


create or replace function weave_workspace.support_entry_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op='DELETE' or (old.value->'title',old.value->'description',old.value->'capitalForms',old.value->'status') is distinct from
      (new.value->'title',new.value->'description',new.value->'capitalForms',new.value->'status') then
    update weave_workspace.support_listings set status='withdrawal_pending',problem=null,updated_at=clock_timestamp()
      where workspace_id=old.initiative_id and kind=case tg_table_name when 'needs' then 'need' else 'offer' end
        and entry_id=old.id and source='saved' and status in ('publish_pending','published');
  end if;
  return null;
end $$;


create or replace function weave_workspace.support_lenses_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.card->'lenses' is distinct from new.card->'lenses' then
    update weave_workspace.support_listings set status='withdrawal_pending',problem=null,updated_at=clock_timestamp()
      where workspace_id=old.id and source='saved' and record_value ? 'lenses' and status in ('publish_pending','published');
  end if;
  return null;
end $$;


create or replace function weave_workspace.support_command(
  p_actor uuid,p_session uuid,p_did text,p_id uuid,p_group_role text,p_cid text,p_action text,p_data jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  link weave_workspace.project_links; access jsonb; parent weave.initiatives;
  entry private.weave_matching_entries; publication weave_workspace.support_listings;
  review weave_workspace.support_reviews; receipt weave_workspace.support_requests;
  k text=p_data->>'kind'; eid uuid=(p_data->>'entryId')::uuid;
  request uuid=(p_data->>'requestId')::uuid; public_record jsonb; key text; event text; claimed boolean=false;
  created timestamptz; updated timestamptz; expiry timestamptz; stamp bigint; key_value bigint; alphabet text='234567abcdefghijklmnopqrstuvwxyz';
  page jsonb; total integer; last_kind text; last_entry text;
  observed timestamptz;
  draft jsonb=p_data->'entry'; details jsonb; source text; stale boolean=false;
begin
  if p_did is null or weave_workspace.weave_project_actor(p_actor,p_session) is distinct from p_did then
    raise sqlstate 'PT401' using message='sign_in_required';
  end if;
  select * into link from weave_workspace.project_links where id=p_id;
  if not found then raise sqlstate 'PT404' using message='not_found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('weave-project:'||link.project_uri,0));
  select * into link from weave_workspace.project_links where id=p_id;
  if weave_workspace.weave_project_actor(p_actor,p_session) is distinct from p_did then
    raise sqlstate 'PT401' using message='sign_in_required';
  end if;
  if p_action='support_membership_absent' then
    if link.group_did is null or p_group_role is not null then raise sqlstate 'PT403' using message='invalid_membership_evidence'; end if;
    observed=(p_data->>'observedAt')::timestamptz;
    if observed is null or observed<clock_timestamp()-interval '1 minute' or observed>clock_timestamp()+interval '5 seconds' then
      raise sqlstate 'PT409' using message='membership_evidence_stale';
    end if;
    update weave_workspace.access_grants g set suspended_at=observed,suspended_by=p_actor,suspension_reason='membership_removed'
      where workspace_id=p_id and user_id=p_actor and member_did=p_did and suspended_at is null
        and observed>greatest(g.granted_at,g.suspended_at);
    return null;
  end if;
  access=weave_workspace.link_result(link,p_actor,p_did,p_group_role);
  if access->>'status'<>'linked' or (link.group_did is null and link.repository_did<>p_did) then
    raise sqlstate 'PT404' using message='not_found';
  end if;
  if p_action='support_state' then
    if (p_data->>'afterKind' is null)<>(p_data->>'afterEntryId' is null)
      or (p_data->>'afterKind' is not null and p_data->>'afterKind' not in ('need','offer')) then
      raise sqlstate 'PT400' using message='invalid_support_cursor';
    end if;
    select coalesce(jsonb_agg(weave_workspace.support_result(q.s) order by (q.s).kind,(q.s).entry_id)
      filter(where q.n<=100),'[]'::jsonb),count(*)::integer,
      max((q.s).kind) filter(where q.n=100),max((q.s).entry_id::text) filter(where q.n=100)
      into page,total,last_kind,last_entry
      from (select s,row_number() over(order by s.kind,s.entry_id) n from weave_workspace.support_listings s
        where s.workspace_id=p_id and (p_data->>'afterKind' is null or
          (s.kind,s.entry_id)>(p_data->>'afterKind',(p_data->>'afterEntryId')::uuid))
        order by s.kind,s.entry_id limit 101) q;
    return jsonb_build_object('listings',page,'next',case when total>100 then
      jsonb_build_object('kind',last_kind,'entryId',last_entry) else null end);
  end if;
  if p_action='support_project_ineligible' then
    select * into parent from weave.initiatives where id=p_id for update;
    if not link.matching_paused then
      update weave_workspace.project_links set matching_paused=true where id=p_id;
      update weave.initiatives set matching_summary_revision=matching_summary_revision+1 where id=p_id;
      delete from private.weave_matching_reviews where initiative_id=p_id;
    end if;
    update weave_workspace.support_listings set status='withdrawal_pending',problem=null,updated_at=clock_timestamp()
      where workspace_id=p_id and status in ('publish_pending','published');
    return null;
  end if;
  if access->>'accessRole' not in ('editor','admin') then raise sqlstate 'PT403' using message='workspace_edit_required'; end if;
  -- Use the same lock order as team_save. Entry triggers queue withdrawals while this lock is held.
  select * into parent from weave.initiatives where id=p_id for update;
  if p_action in ('support_review','support_publish') then
    if not coalesce(weave_workspace.valid_project(link.project_uri,link.repository_did,p_cid),false) then
      raise sqlstate 'PT403' using message='project_verification_required';
    end if;
    -- A fresh verified project permits a new review; old publications never restart automatically.
    update weave_workspace.project_links set matching_paused=false,cid=p_cid,verified_at=clock_timestamp() where id=p_id;
  end if;
  if p_action='support_review' and draft is not null then
    -- DL-155: the need or offer comes from the device draft; nothing is read from a private save.
    -- The API also checks graphemes; this bounds bytes, values and duplicates at the owning boundary.
    if k is null or k not in ('need','offer') or eid is null or jsonb_typeof(draft) is distinct from 'object'
      or draft - array['title','description','capitalForms','lenses'] <> '{}'::jsonb
      or jsonb_typeof(draft->'title') is distinct from 'string' or btrim(draft->>'title')=''
      or octet_length(draft->>'title')>1400
      or (draft ? 'description' and jsonb_typeof(draft->'description') <> 'null'
        and (jsonb_typeof(draft->'description') <> 'string' or octet_length(draft->>'description')>6000))
      or jsonb_typeof(draft->'capitalForms') is distinct from 'array'
      or jsonb_array_length(draft->'capitalForms') not between 1 and 8
      or exists(select from jsonb_array_elements(draft->'capitalForms') f where jsonb_typeof(f)<>'string' or f#>>'{}' not in ('living','material','intellectual','experiential','social','financial','cultural','spiritual'))
      or (select count(distinct f) from jsonb_array_elements_text(draft->'capitalForms') f)<>jsonb_array_length(draft->'capitalForms')
      or (draft ? 'lenses' and (jsonb_typeof(draft->'lenses') is distinct from 'array' or jsonb_array_length(draft->'lenses')>5
        or exists(select from jsonb_array_elements(draft->'lenses') l where jsonb_typeof(l)<>'string' or l#>>'{}' not in ('art_culture','research','technology','place_based','learning','funders'))
        or (select count(distinct l) from jsonb_array_elements_text(draft->'lenses') l)<>jsonb_array_length(draft->'lenses'))) then
      raise sqlstate 'PT400' using message='invalid_support_entry';
    end if;
    source='draft'; details=draft;
  elsif p_action='support_review' then
    -- A personal link's saved card is the one it is anchored on, read only by its owner: the DID rule
    -- holds the link, never another account's private save.
    if parent.id is null or parent.revision is distinct from (p_data->>'expectedRevision')::integer
      or (link.group_did is null and (link.solo_initiative_id is distinct from p_id or parent.owner_id is distinct from p_actor)) then
      raise sqlstate 'PT409' using message='revision_conflict';
    end if;
    select * into entry from private.weave_matching_entries e where (e.initiative_id,e.kind,e.id)=(p_id,k,eid);
    if not found or entry.matching_revision is distinct from (p_data->>'expectedEntryRevision')::bigint
      or entry.value->>'status'<>'open' or jsonb_array_length(entry.value->'capitalForms')<1 then
      raise sqlstate 'PT409' using message='entry_conflict';
    end if;
    source='saved';
    details=jsonb_build_object('title',entry.value->'title','description',entry.value->'description',
      'capitalForms',entry.value->'capitalForms','lenses',parent.card->'lenses');
  end if;
  if p_action='support_review' then
    select * into publication from weave_workspace.support_listings where (workspace_id,kind,entry_id)=(p_id,k,eid);
    if found and publication.status not in ('withdrawn') then raise sqlstate 'PT409' using message='withdrawal_required'; end if;
    created=coalesce((publication.record_value->>'createdAt')::timestamptz,clock_timestamp());
    -- Distinct reviewed publications need distinct CIDs, even when all details match.
    -- Otherwise a late delete for an old identical CID could remove its replacement.
    updated=greatest(clock_timestamp(),coalesce((publication.record_value->>'updatedAt')::timestamptz,created)+interval '1 millisecond',
      coalesce((select max((r.record_value->>'updatedAt')::timestamptz) from weave_workspace.support_reviews r
        where (r.workspace_id,r.kind,r.entry_id)=(p_id,k,eid)),created)+interval '1 millisecond');
    expiry=(p_data->>'expiresAt')::timestamptz;
    if expiry is not null and (expiry<=clock_timestamp() or expiry<=created) then raise sqlstate 'PT400' using message='invalid_expiry'; end if;
    public_record=jsonb_build_object('$type','com.regencommons.weave.supportListing','projectUri',link.project_uri,'kind',k,
      'title',details->'title','capitalForms',details->'capitalForms','status','open',
      'createdAt',to_char(created at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'updatedAt',to_char(updated at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
    if expiry is not null then public_record=public_record||jsonb_build_object('expiresAt',
      to_char(expiry at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')); end if;
    if details ? 'description' and details->'description'<>'null'::jsonb then public_record=public_record||jsonb_build_object('description',details->'description'); end if;
    if jsonb_typeof(details->'lenses')='array' and jsonb_array_length(details->'lenses')>0 then public_record=public_record||jsonb_build_object('lenses',details->'lenses'); end if;
    delete from weave_workspace.support_reviews where expires_at<=clock_timestamp();
    if (select count(*) from weave_workspace.support_reviews where actor_id=p_actor)>=100 then
      raise sqlstate 'PT429' using message='rate_limited';
    end if;
    -- A draft review names no saved revision, even where the workspace also has a saved card.
    insert into weave_workspace.support_reviews(actor_id,session_id,workspace_id,kind,entry_id,saved_revision,entry_revision,record_value,audience,expires_at,source)
      values(p_actor,p_session,p_id,k,eid,case when source='draft' then 0 else parent.revision end,
        case when source='draft' then 0 else entry.matching_revision end,public_record,'public-atproto',clock_timestamp()+interval '10 minutes',source)
      returning * into review;
    return jsonb_build_object('reviewId',review.id,'audience',review.audience,'destination',link.repository_did,
      'record',review.record_value,'expectedRevision',review.saved_revision,'expectedEntryRevision',review.entry_revision,'reviewExpiresAt',review.expires_at);
  end if;
  if p_action in ('support_publish','support_withdraw') then
    if request is null then raise sqlstate 'PT400' using message='invalid_request'; end if;
    perform pg_advisory_xact_lock(hashtextextended('weave-support:'||p_actor||':'||request,0));
    select * into receipt from weave_workspace.support_requests where actor_id=p_actor and request_id=request;
    if found then
      if receipt.command is distinct from p_data or receipt.workspace_id<>p_id then raise sqlstate 'PT409' using message='request_reused'; end if;
      select * into publication from weave_workspace.support_listings where
        (workspace_id,kind,entry_id,operation_id)=(p_id,receipt.kind,receipt.entry_id,receipt.operation_id);
      if not found then raise sqlstate 'PT409' using message='superseded_operation'; end if;
      return weave_workspace.support_result(publication);
    end if;
  end if;
  if p_action='support_publish' then
    if p_data->>'audience' is distinct from 'public-atproto' or p_data->'confirmPublic' is distinct from 'true'::jsonb then
      raise sqlstate 'PT400' using message='public_consent_required';
    end if;
    select * into review from weave_workspace.support_reviews where id=(p_data->>'reviewId')::uuid
      and actor_id=p_actor and session_id=p_session and workspace_id=p_id and expires_at>clock_timestamp();
    if not found or (review.source='saved' and parent.revision is distinct from review.saved_revision) then
      raise sqlstate 'PT409' using message='review_expired';
    end if;
    k=review.kind; eid=review.entry_id;
    if review.source='saved' then
      select * into entry from private.weave_matching_entries e where (e.initiative_id,e.kind,e.id)=(p_id,k,eid);
      stale=not found or entry.matching_revision<>review.entry_revision or entry.value->>'status'<>'open';
    end if;
    if stale or (review.record_value->>'expiresAt')::timestamptz<=clock_timestamp() then raise sqlstate 'PT409' using message='entry_conflict'; end if;
    select * into publication from weave_workspace.support_listings where (workspace_id,kind,entry_id)=(p_id,k,eid);
    if found and publication.status<>'withdrawn' then raise sqlstate 'PT409' using message='withdrawal_required'; end if;
    key=publication.rkey;
    if key is null then
      -- A TID is persisted before the first outbound write. Random low bits avoid cross-process clock collisions.
      stamp=floor(extract(epoch from clock_timestamp())*1000000)::bigint;
      key_value=(stamp<<10)|floor(random()*1024)::bigint; key='';
      for i in 1..13 loop key=substr(alphabet,(key_value&31)::integer+1,1)||key; key_value=key_value>>5; end loop;
    end if;
    insert into weave_workspace.support_listings(workspace_id,kind,entry_id,rkey,operation_id,actor_id,entry_revision,record_value,status,source)
      values(p_id,k,eid,key,request,p_actor,review.entry_revision,review.record_value,'publish_pending',review.source)
      on conflict(workspace_id,kind,entry_id) do update set operation_id=excluded.operation_id,actor_id=excluded.actor_id,
        entry_revision=excluded.entry_revision,record_value=excluded.record_value,status='publish_pending',cid=null,attempted=false,problem=null,
        source=excluded.source,updated_at=clock_timestamp()
      returning * into publication;
    delete from weave_workspace.support_reviews where id=review.id;
  elsif p_action='support_withdraw' then
    select * into publication from weave_workspace.support_listings where (workspace_id,kind,entry_id)=(p_id,k,eid);
    if not found then raise sqlstate 'PT404' using message='not_found'; end if;
    if publication.status<>'withdrawn' then
      update weave_workspace.support_listings set status='withdrawal_pending',problem=null,updated_at=clock_timestamp()
        where (workspace_id,kind,entry_id)=(p_id,k,eid) returning * into publication;
    end if;
  elsif p_action='support_get' then
    select * into publication from weave_workspace.support_listings where (workspace_id,kind,entry_id)=(p_id,k,eid);
    if not found then raise sqlstate 'PT404' using message='not_found'; end if;
  elsif p_action='support_checkpoint' then
    select * into publication from weave_workspace.support_listings where
      (workspace_id,kind,entry_id,operation_id)=(p_id,k,eid,(p_data->>'operationId')::uuid) for update;
    if not found then raise sqlstate 'PT409' using message='superseded_operation'; end if;
    event=p_data->>'event';
    if event='sending' and publication.status='publish_pending' then
      if publication.source='saved' then
        select * into entry from private.weave_matching_entries e where (e.initiative_id,e.kind,e.id)=(p_id,k,eid);
        stale=not found or entry.matching_revision<>publication.entry_revision or entry.value->>'status'<>'open';
      end if;
      if stale or link.matching_paused
        or (publication.record_value->>'expiresAt')::timestamptz<=clock_timestamp() then
        publication.status='withdrawal_pending';
      elsif not publication.attempted then publication.attempted=true; claimed=true; end if;
    elsif event in ('observed','published') and publication.status in ('publish_pending','withdrawal_pending') then
      if p_data->>'cid' is null or p_data->>'cid' !~ '^b[a-z2-7]{40,100}$'
        or (publication.cid is not null and publication.cid<>p_data->>'cid') then raise sqlstate 'PT409' using message='cid_conflict'; end if;
      publication.cid=p_data->>'cid'; publication.problem=null;
      if event='published' and publication.status='publish_pending' then publication.status='published'; end if;
    elsif event='withdrawn' and publication.status='withdrawal_pending' then
      publication.status='withdrawn'; publication.problem=null;
    elsif event='external_withdrawn' and publication.status='published' then
      -- Public read-back never changes matching_audience, matching_withdrawn, entry.value or its revision.
      publication.status='withdrawn'; publication.problem=null;
    elsif event='conflict' then publication.status='conflict'; publication.problem='public_record_changed';
    elsif event in ('problem','rejected') then
      if length(p_data->>'problem') not between 1 and 80 or p_data->>'problem' !~ '^[a-z_]+$' then raise sqlstate 'PT400' using message='invalid_problem'; end if;
      publication.problem=p_data->>'problem';
      if event='rejected' then
        if publication.cid is not null or publication.status not in ('publish_pending','withdrawal_pending')
          or publication.problem not in ('authorization_required','forbidden','invalid_input','unsupported') then
          raise sqlstate 'PT409' using message='invalid_rejection';
        end if;
        -- A definitive rejection performed no write. Its sole claim can safely be retried after authorization changes.
        publication.attempted=false;
      end if;
    elsif event<>'sending' then raise sqlstate 'PT409' using message='invalid_checkpoint'; end if;
    update weave_workspace.support_listings set status=publication.status,cid=publication.cid,attempted=publication.attempted,
      problem=publication.problem,updated_at=clock_timestamp() where (workspace_id,kind,entry_id)=(p_id,k,eid)
      returning * into publication;
  else raise sqlstate 'PT400' using message='invalid_support_command';
  end if;
  if p_action in ('support_publish','support_withdraw') then
    insert into weave_workspace.support_requests(actor_id,request_id,command,workspace_id,kind,entry_id,operation_id)
      values(p_actor,request,p_data,p_id,k,eid,publication.operation_id);
  end if;
  return weave_workspace.support_result(publication)||case when event='sending' then jsonb_build_object('claimed',claimed) else '{}'::jsonb end;
end $$;
