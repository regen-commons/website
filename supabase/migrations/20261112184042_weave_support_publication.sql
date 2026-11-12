-- Candidate only. Apply after weave-team-content; no hosted migration is implied.
-- Private Save, network sharing and AT publication remain independent states.
create table weave_workspace.support_listings (
  workspace_id uuid not null references weave_workspace.project_links(id) on delete cascade,
  kind text not null check(kind in ('need','offer')),
  entry_id uuid not null,
  rkey text not null check(rkey ~ '^[2-7a-j][2-7a-z]{12}$'),
  operation_id uuid not null,
  actor_id uuid references auth.users(id) on delete set null,
  entry_revision bigint not null,
  record_value jsonb not null,
  status text not null check(status in ('publish_pending','published','withdrawal_pending','withdrawn','conflict')),
  cid text check(cid ~ '^b[a-z2-7]{40,100}$'),
  attempted boolean not null default false,
  problem text,
  updated_at timestamptz not null default clock_timestamp(),
  primary key(workspace_id,kind,entry_id),
  unique(workspace_id,rkey)
);
create table weave_workspace.support_reviews (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null,
  workspace_id uuid not null references weave_workspace.project_links(id) on delete cascade,
  kind text not null check(kind in ('need','offer')),
  entry_id uuid not null,
  saved_revision integer not null,
  entry_revision bigint not null,
  record_value jsonb not null,
  audience text not null check(audience='public-atproto'),
  expires_at timestamptz not null
);
create table weave_workspace.support_requests (
  actor_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  command jsonb not null,
  workspace_id uuid not null,
  kind text not null,
  entry_id uuid not null,
  operation_id uuid not null,
  primary key(actor_id,request_id),
  foreign key(workspace_id,kind,entry_id) references weave_workspace.support_listings(workspace_id,kind,entry_id) on delete cascade
);
alter table weave_workspace.support_listings enable row level security;
alter table weave_workspace.support_reviews enable row level security;
alter table weave_workspace.support_requests enable row level security;
revoke all on weave_workspace.support_listings,weave_workspace.support_reviews,weave_workspace.support_requests
  from public,anon,authenticated,service_role,weave_workspace_runtime;

create function weave_workspace.support_result(p weave_workspace.support_listings) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object('kind',(p).kind,'entryId',(p).entry_id,'rkey',(p).rkey,'operationId',(p).operation_id,
    'status',(p).status,'record',(p).record_value,'cid',(p).cid,'attempted',(p).attempted,'problem',(p).problem);
$$;

-- Run in the private-save transaction. No new entry details enter the old public record.
create function weave_workspace.support_entry_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op='DELETE' or (old.value->'title',old.value->'description',old.value->'capitalForms',old.value->'status') is distinct from
      (new.value->'title',new.value->'description',new.value->'capitalForms',new.value->'status') then
    update weave_workspace.support_listings set status='withdrawal_pending',problem=null,updated_at=clock_timestamp()
      where workspace_id=old.initiative_id and kind=case tg_table_name when 'needs' then 'need' else 'offer' end
        and entry_id=old.id and status in ('publish_pending','published');
  end if;
  return null;
end $$;
create trigger support_entry_changed after update of value or delete on weave.needs
  for each row execute function weave_workspace.support_entry_changed();
create trigger support_entry_changed after update of value or delete on weave.offers
  for each row execute function weave_workspace.support_entry_changed();

-- Types of work are part of the reviewed public projection only when explicitly included.
-- Changing a published projection requests withdrawal; it never silently republishes the new types.
create function weave_workspace.support_lenses_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.card->'lenses' is distinct from new.card->'lenses' then
    update weave_workspace.support_listings set status='withdrawal_pending',problem=null,updated_at=clock_timestamp()
      where workspace_id=old.id and record_value ? 'lenses' and status in ('publish_pending','published');
  end if;
  return null;
end $$;
create trigger support_lenses_changed after update of card on weave.initiatives
  for each row execute function weave_workspace.support_lenses_changed();

-- matching_paused is set only for confirmed deletion/unlisting by the current API.
-- A provider outage never writes this flag. Existing pending requests survive retries.
create function weave_workspace.support_project_unlisted() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.matching_paused and not old.matching_paused then
    update weave_workspace.support_listings set status='withdrawal_pending',problem=null,updated_at=clock_timestamp()
      where workspace_id=new.id and status in ('publish_pending','published');
  end if;
  return null;
end $$;
create trigger support_project_unlisted after update of matching_paused on weave_workspace.project_links
  for each row execute function weave_workspace.support_project_unlisted();

create function weave_workspace.support_command(
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
  if p_action='support_review' then
    if parent.id is null or parent.revision is distinct from (p_data->>'expectedRevision')::integer then
      raise sqlstate 'PT409' using message='revision_conflict';
    end if;
    select * into entry from private.weave_matching_entries e where (e.initiative_id,e.kind,e.id)=(p_id,k,eid);
    if not found or entry.matching_revision is distinct from (p_data->>'expectedEntryRevision')::bigint
      or entry.value->>'status'<>'open' or jsonb_array_length(entry.value->'capitalForms')<1 then
      raise sqlstate 'PT409' using message='entry_conflict';
    end if;
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
      'title',entry.value->'title','capitalForms',entry.value->'capitalForms','status','open',
      'createdAt',to_char(created at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'updatedAt',to_char(updated at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
    if expiry is not null then public_record=public_record||jsonb_build_object('expiresAt',
      to_char(expiry at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')); end if;
    if entry.value->'description'<>'null'::jsonb then public_record=public_record||jsonb_build_object('description',entry.value->'description'); end if;
    if jsonb_array_length(parent.card->'lenses')>0 then public_record=public_record||jsonb_build_object('lenses',parent.card->'lenses'); end if;
    delete from weave_workspace.support_reviews where expires_at<=clock_timestamp();
    if (select count(*) from weave_workspace.support_reviews where actor_id=p_actor)>=100 then
      raise sqlstate 'PT429' using message='rate_limited';
    end if;
    insert into weave_workspace.support_reviews(actor_id,session_id,workspace_id,kind,entry_id,saved_revision,entry_revision,record_value,audience,expires_at)
      values(p_actor,p_session,p_id,k,eid,parent.revision,entry.matching_revision,public_record,'public-atproto',clock_timestamp()+interval '10 minutes')
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
    if not found or parent.revision is distinct from review.saved_revision then raise sqlstate 'PT409' using message='review_expired'; end if;
    k=review.kind; eid=review.entry_id;
    select * into entry from private.weave_matching_entries e where (e.initiative_id,e.kind,e.id)=(p_id,k,eid);
    if not found or entry.matching_revision<>review.entry_revision or entry.value->>'status'<>'open'
      or (review.record_value->>'expiresAt')::timestamptz<=clock_timestamp() then raise sqlstate 'PT409' using message='entry_conflict'; end if;
    select * into publication from weave_workspace.support_listings where (workspace_id,kind,entry_id)=(p_id,k,eid);
    if found and publication.status<>'withdrawn' then raise sqlstate 'PT409' using message='withdrawal_required'; end if;
    key=publication.rkey;
    if key is null then
      -- A TID is persisted before the first outbound write. Random low bits avoid cross-process clock collisions.
      stamp=floor(extract(epoch from clock_timestamp())*1000000)::bigint;
      key_value=(stamp<<10)|floor(random()*1024)::bigint; key='';
      for i in 1..13 loop key=substr(alphabet,(key_value&31)::integer+1,1)||key; key_value=key_value>>5; end loop;
    end if;
    insert into weave_workspace.support_listings(workspace_id,kind,entry_id,rkey,operation_id,actor_id,entry_revision,record_value,status)
      values(p_id,k,eid,key,request,p_actor,review.entry_revision,review.record_value,'publish_pending')
      on conflict(workspace_id,kind,entry_id) do update set operation_id=excluded.operation_id,actor_id=excluded.actor_id,
        entry_revision=excluded.entry_revision,record_value=excluded.record_value,status='publish_pending',cid=null,attempted=false,problem=null,updated_at=clock_timestamp()
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
      select * into entry from private.weave_matching_entries e where (e.initiative_id,e.kind,e.id)=(p_id,k,eid);
      if not found or entry.matching_revision<>publication.entry_revision or entry.value->>'status'<>'open' or link.matching_paused
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

revoke all on function weave_workspace.support_result(weave_workspace.support_listings),
  weave_workspace.support_entry_changed(),weave_workspace.support_lenses_changed(),weave_workspace.support_project_unlisted(),
  weave_workspace.support_command(uuid,uuid,text,uuid,text,text,text,jsonb)
  from public,anon,authenticated,service_role,weave_workspace_runtime;
grant execute on function weave_workspace.support_command(uuid,uuid,text,uuid,text,text,text,jsonb) to weave_workspace_runtime;
