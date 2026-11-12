-- Candidate for the website migration owner. Requires private saving and Certified-only access.
-- Existing version-1 Save/Load requests and IDs remain valid. Nothing starts shared.
create sequence private.weave_matching_version as bigint maxvalue 9007199254740991;
revoke all on sequence private.weave_matching_version from public, anon, authenticated;

create function private.weave_matching_summary(card jsonb) returns jsonb
language sql immutable strict set search_path = '' as $$
  select jsonb_build_object('name',card->'name','description',card->'description',
    'locations',card->'locations','isGlobal',card->'isGlobal','lenses',card->'lenses','themes',card->'themes');
$$;
create function private.weave_matching_terms(value jsonb) returns tsvector
language sql immutable strict set search_path = '' as $$
  select to_tsvector('pg_catalog.simple',coalesce(value->>'title','')||' '||
    coalesce(value->>'description','')||' '||coalesce(value->>'purpose',''));
$$;
revoke all on function private.weave_matching_summary(jsonb),private.weave_matching_terms(jsonb)
  from public, anon, authenticated;

alter table weave.initiatives add column matching_summary_revision bigint not null default 1;
do $$
declare t text;
begin
  foreach t in array array['needs','offers'] loop
    execute format('alter table weave.%1$I
      drop constraint %2$I, add constraint %2$I unique(initiative_id,position) deferrable initially immediate,
      add column matching_revision bigint not null default nextval(''private.weave_matching_version''::regclass),
      add column matching_share_version bigint not null default 0,
      add column matching_reviewed_revision bigint,
      add column matching_reviewed_summary_revision bigint,
      add column matching_audience text check(matching_audience is null or matching_audience=''weave_users''),
      add column matching_confirmed_at timestamptz,
      add column matching_expires_at timestamptz,
      add column matching_withdrawn boolean not null default false',
      t,t||'_initiative_id_position_key');
    execute format('create index on weave.%I using gin (private.weave_matching_terms(value))
      where matching_audience=''weave_users'' and not matching_withdrawn and value->>''status''=''open''',t);
  end loop;
end $$;

create function private.weave_reconcile_matching_entries(p_table regclass,p_id uuid,p_entries jsonb)
returns void language plpgsql set search_path = '' as $$
begin
  -- The caller locks the initiative before reconciling. A position swap must not
  -- delete either ID or compare the new positions against the old order.
  execute format('delete from %s n where n.initiative_id=$1 and not exists
    (select from jsonb_array_elements($2) a where (a->>''id'')::uuid=n.id)',p_table)
    using p_id,p_entries;
  execute format('insert into %1$s as n (initiative_id,id,position,value)
    select $1,(a->>''id'')::uuid,(ordinality-1)::integer,a->''value''
    from jsonb_array_elements($2) with ordinality as x(a,ordinality)
    on conflict(initiative_id,id) do update set position=excluded.position,value=excluded.value,
    matching_revision=case when n.value is distinct from excluded.value then excluded.matching_revision
      else n.matching_revision end
    where (n.position,n.value) is distinct from (excluded.position,excluded.value)',p_table)
    using p_id,p_entries;
end $$;
revoke all on function private.weave_reconcile_matching_entries(regclass,uuid,jsonb)
  from public, anon, authenticated;

create or replace function private.weave_save_initiative(p_id uuid,p_expected_revision integer,p_request_id uuid,p_document jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor uuid=private.weave_actor(); old private.weave_save_requests%rowtype; current weave.initiatives%rowtype; result jsonb; quota integer;
begin
  if actor is null then raise sqlstate 'PT401' using message='sign_in_required';end if;
  if p_id is null or p_request_id is null or p_expected_revision is null or p_expected_revision<0 or p_expected_revision>=2147483647 or not private.weave_valid_document(p_document) then raise sqlstate 'PT400' using message='invalid_data';end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':'||p_request_id::text,0));
  select * into old from private.weave_save_requests where actor_id=actor and request_id=p_request_id;
  if found then
    if old.initiative_id<>p_id or old.expected_revision<>p_expected_revision or old.response->'document'<>p_document then raise sqlstate 'PT409' using message='request_reused';end if;
    return old.response;
  end if;
  insert into private.weave_save_limits values(actor,date_trunc('hour',now()),1)
    on conflict(actor_id,window_start) do update set total=private.weave_save_limits.total+1 returning total into quota;
  if quota>30 then raise sqlstate 'PT429' using message='rate_limited';end if;
  delete from private.weave_save_limits where actor_id=actor and window_start<now()-interval '2 days';
  insert into weave.accounts(user_id) values(actor) on conflict do nothing;
  if p_expected_revision=0 then
    insert into weave.initiatives(id,owner_id,card,funding) values(p_id,actor,p_document->'initiative',p_document->'funding') on conflict do nothing returning * into current;
    if not found then raise sqlstate 'PT409' using message='revision_conflict';end if;
  else
    select * into current from weave.initiatives where id=p_id and owner_id=actor for update;
    if not found then raise sqlstate 'PT404' using message='not_found';end if;
    if current.revision<>p_expected_revision then raise sqlstate 'PT409' using message='revision_conflict';end if;
    update weave.initiatives set card=p_document->'initiative',funding=p_document->'funding',
      revision=revision+1,updated_at=now(),
      matching_summary_revision=matching_summary_revision +
        (private.weave_matching_summary(card) is distinct from private.weave_matching_summary(p_document->'initiative'))::integer
      where id=p_id returning * into current;
  end if;
  if private.weave_actor() is distinct from actor then
    raise sqlstate 'PT401' using message='sign_in_required';
  end if;
  set constraints weave.needs_initiative_id_position_key, weave.offers_initiative_id_position_key deferred;
  perform private.weave_reconcile_matching_entries('weave.needs',p_id,p_document->'needs');
  perform private.weave_reconcile_matching_entries('weave.offers',p_id,p_document->'offers');
  set constraints weave.needs_initiative_id_position_key, weave.offers_initiative_id_position_key immediate;
  -- Explicitly scoped: the invoker read RPC also enforces RLS for every caller.
  result=jsonb_build_object('id',p_id,'revision',current.revision,'updatedAt',current.updated_at,'document',p_document);
  insert into private.weave_save_requests(actor_id,request_id,initiative_id,expected_revision,response)
    values(actor,p_request_id,p_id,p_expected_revision,result);
  return result;
end $$;

create table private.weave_matching_reviews (
  id uuid primary key default gen_random_uuid(),
  initiative_id uuid not null references weave.initiatives(id) on delete cascade,
  initiative_revision integer not null,
  entries jsonb not null,
  expires_at timestamptz not null,
  valid_until timestamptz not null
);
create index on private.weave_matching_reviews(initiative_id,valid_until);
create table private.weave_matching_requests (
  actor_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  command jsonb not null,
  created_at timestamptz not null default now(),
  primary key(actor_id,request_id)
);
create table private.weave_matching_leads (
  initiative_id uuid not null references weave.initiatives(id) on delete cascade,
  kind text not null check(kind in ('need','offer')),
  entry_id uuid not null,
  candidate_id text not null,
  candidate_revision bigint,
  candidate_summary_revision bigint,
  disposition text not null check(disposition in ('saved','dismissed')),
  updated_at timestamptz not null default now(),
  primary key(initiative_id,kind,entry_id,candidate_id)
);
alter table private.weave_matching_reviews enable row level security;
alter table private.weave_matching_requests enable row level security;
alter table private.weave_matching_leads enable row level security;
revoke all on private.weave_matching_reviews,private.weave_matching_requests,private.weave_matching_leads
  from public, anon, authenticated;

-- These views are internal; neither table nor view grants cross-owner row access.
create view private.weave_matching_entries as
  select 'need'::text as kind, n.* from weave.needs n
  union all select 'offer'::text, o.* from weave.offers o;
create view private.weave_matching_current as
  select e.*, i.owner_id, i.matching_summary_revision, private.weave_matching_summary(i.card) as summary,
    private.weave_matching_terms(e.value) as terms
  from private.weave_matching_entries e join weave.initiatives i on i.id=e.initiative_id
  where e.matching_audience='weave_users' and not e.matching_withdrawn
    and e.matching_reviewed_revision=e.matching_revision
    and e.matching_reviewed_summary_revision=i.matching_summary_revision
    and e.value->>'status'='open' and e.matching_expires_at>now();
revoke all on private.weave_matching_entries,private.weave_matching_current from public, anon, authenticated;

create function private.weave_matching_owner(p_id uuid,p_lock boolean)
returns weave.initiatives language plpgsql set search_path = '' as $$
declare actor uuid=private.weave_actor(); result weave.initiatives;
begin
  if actor is null then raise sqlstate 'PT401' using message='sign_in_required'; end if;
  if p_id is null then raise sqlstate 'PT400' using message='invalid_data'; end if;
  if p_lock then
    select * into result from weave.initiatives where id=p_id and owner_id=actor for update;
  else
    select * into result from weave.initiatives where id=p_id and owner_id=actor;
  end if;
  if not found then raise sqlstate 'PT404' using message='not_found'; end if;
  if p_lock and private.weave_actor() is distinct from actor then
    raise sqlstate 'PT401' using message='sign_in_required';
  end if;
  return result;
end $$;

create function private.weave_matching_refs(p_entries jsonb,p_allow_key boolean default false)
returns table(kind text,id uuid,revision bigint,share_version bigint)
language plpgsql immutable set search_path = '' as $$
declare item jsonb; seen text[]='{}'; entry_key text;
begin
  if jsonb_typeof(p_entries) is distinct from 'array' then
    raise sqlstate 'PT400' using message='invalid_data';
  end if;
  if jsonb_array_length(p_entries) not between 1 and 10 then
    raise sqlstate 'PT400' using message='invalid_data';
  end if;
  for item in select * from jsonb_array_elements(p_entries) loop
    if jsonb_typeof(item) is distinct from 'object'
      or jsonb_typeof(item->'kind') is distinct from 'string' or item->>'kind' not in ('need','offer')
      or jsonb_typeof(item->'entryId') is distinct from 'string'
      or (item->>'entryId') !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    then raise sqlstate 'PT400' using message='invalid_data'; end if;
    kind=item->>'kind'; id=(item->>'entryId')::uuid;
    if p_allow_key and (item-array['kind','entryId'])='{}'::jsonb then
      revision=null; share_version=null;
    else
      if (item-array['kind','entryId','revision','shareVersion'])<>'{}'::jsonb
        or jsonb_typeof(item->'revision') is distinct from 'number' or (item->>'revision') !~ '^[1-9][0-9]{0,15}$'
        or jsonb_typeof(item->'shareVersion') is distinct from 'number' or (item->>'shareVersion') !~ '^[0-9]{1,16}$'
      then raise sqlstate 'PT400' using message='invalid_data'; end if;
      revision=(item->>'revision')::bigint; share_version=(item->>'shareVersion')::bigint;
    end if;
    entry_key=kind||':'||id::text;
    if entry_key=any(seen) or greatest(revision,share_version)>9007199254740991 then
      raise sqlstate 'PT400' using message='invalid_data';
    end if;
    seen=array_append(seen,entry_key);
    return next;
  end loop;
end $$;

create function private.weave_matching_selected(p_id uuid,p_entries jsonb)
returns setof private.weave_matching_entries language plpgsql stable set search_path = '' as $$
declare ref record; entry private.weave_matching_entries;
begin
  for ref in select * from private.weave_matching_refs(p_entries) loop
    select * into entry from private.weave_matching_entries e where e.initiative_id=p_id
      and (e.kind,e.id,e.matching_revision,e.matching_share_version)=(ref.kind,ref.id,ref.revision,ref.share_version);
    if not found then raise sqlstate 'PT409' using message='matching_conflict'; end if;
    return next entry;
  end loop;
end $$;

create function private.weave_matching_state(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare parent weave.initiatives=private.weave_matching_owner(p_id,false);
begin
  return jsonb_build_object('initiativeId',p_id,'initiativeRevision',parent.revision,'entries',coalesce((
    select jsonb_agg(jsonb_build_object('kind',e.kind,'entryId',e.id,'revision',e.matching_revision,
      'shareVersion',e.matching_share_version,'status',e.value->>'status','confirmedAt',e.matching_confirmed_at,
      'expiresAt',e.matching_expires_at,'sharing',case
        when e.matching_audience is null then 'private'
        when e.matching_withdrawn then 'withdrawn'
        when e.matching_reviewed_revision<>e.matching_revision or
          e.matching_reviewed_summary_revision<>parent.matching_summary_revision or e.value->>'status'<>'open'
          then 'needs_review'
        when e.matching_expires_at<=now() then 'expired' else 'shared' end)
      order by e.kind,e.position)
    from private.weave_matching_entries e where e.initiative_id=p_id),'[]'::jsonb));
end $$;

create function private.weave_matching_preview(p_id uuid,p_revision integer,p_entries jsonb,p_expires_at timestamptz)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare parent weave.initiatives=private.weave_matching_owner(p_id,true);
  expiration timestamptz=least(coalesce(p_expires_at,now()+interval '90 days'),now()+interval '90 days');
  selected jsonb; review_id uuid;
begin
  if p_revision is null or p_revision<1 or (p_expires_at is not null and not isfinite(p_expires_at)) or expiration<=now()
    then raise sqlstate 'PT400' using message='invalid_data'; end if;
  if parent.revision<>p_revision then raise sqlstate 'PT409' using message='matching_conflict'; end if;
  select jsonb_agg(jsonb_build_object('kind',e.kind,'entryId',e.id,'revision',e.matching_revision,
    'shareVersion',e.matching_share_version,'value',e.value) order by e.kind,e.position)
    into selected from private.weave_matching_selected(p_id,p_entries) e where e.value->>'status'='open';
  if coalesce(jsonb_array_length(selected),0)<>jsonb_array_length(p_entries) then
    raise sqlstate 'PT409' using message='matching_conflict';
  end if;
  delete from private.weave_matching_reviews where initiative_id=p_id and valid_until<=now();
  if (select count(*) from private.weave_matching_reviews where initiative_id=p_id)>=30
    then raise sqlstate 'PT429' using message='rate_limited'; end if;
  insert into private.weave_matching_reviews(initiative_id,initiative_revision,entries,expires_at,valid_until)
    values(p_id,p_revision,p_entries,expiration,least(expiration,now()+interval '15 minutes')) returning id into review_id;
  return jsonb_build_object('reviewId',review_id,'initiativeId',p_id,'initiativeRevision',p_revision,
    'audience','weave_users','expiresAt',expiration,'summary',private.weave_matching_summary(parent.card),'entries',selected);
end $$;

-- Each command shares the initiative row lock with Save and uses a separate
-- actor/request lock so concurrent reuse across initiatives is also deterministic.
create function private.weave_matching_retry(p_actor uuid,p_request uuid,p_command jsonb)
returns boolean language plpgsql set search_path = '' as $$
declare old private.weave_matching_requests;
begin
  if p_request is null then raise sqlstate 'PT400' using message='invalid_data'; end if;
  perform pg_advisory_xact_lock(hashtextextended('weave-matching:'||p_actor::text||':'||p_request::text,0));
  if private.weave_actor() is distinct from p_actor then
    raise sqlstate 'PT401' using message='sign_in_required';
  end if;
  select * into old from private.weave_matching_requests where actor_id=p_actor and request_id=p_request;
  if found then
    if old.command<>p_command then raise sqlstate 'PT409' using message='matching_conflict'; end if;
    return true;
  end if;
  return false;
end $$;

create function private.weave_matching_change(
  p_id uuid,p_action text,p_request_id uuid,p_review_id uuid,p_entries jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare parent weave.initiatives=private.weave_matching_owner(p_id,true);
  command jsonb=jsonb_build_array(p_id,p_action,p_review_id,p_entries);
  review private.weave_matching_reviews; entry private.weave_matching_entries; target regclass;
begin
  if p_action is null or p_action not in ('share','renew','withdraw')
    or (p_action='withdraw' and (p_review_id is not null or p_entries is null))
    or (p_action<>'withdraw' and (p_review_id is null or p_entries is not null))
    then raise sqlstate 'PT400' using message='invalid_data'; end if;
  if private.weave_matching_retry(parent.owner_id,p_request_id,command) then return private.weave_matching_state(p_id); end if;
  if p_action<>'withdraw' then
    select * into review from private.weave_matching_reviews
      where id=p_review_id and initiative_id=p_id and valid_until>clock_timestamp();
    if not found or review.initiative_revision<>parent.revision then
      raise sqlstate 'PT409' using message='matching_conflict';
    end if;
    p_entries=review.entries;
  end if;
  for entry in select * from private.weave_matching_selected(p_id,p_entries) loop
    target=case entry.kind when 'need' then 'weave.needs'::regclass else 'weave.offers'::regclass end;
    if p_action='withdraw' then
      if entry.matching_audience is null or entry.matching_withdrawn then
        raise sqlstate 'PT409' using message='matching_conflict';
      end if;
      execute format('update %s set matching_withdrawn=true,
        matching_share_version=nextval(''private.weave_matching_version'') where initiative_id=$1 and id=$2',target)
        using p_id,entry.id;
    else
      if entry.value->>'status'<>'open' or (p_action='renew' and (
        entry.matching_audience is null or entry.matching_withdrawn
        or entry.matching_reviewed_revision<>entry.matching_revision
        or entry.matching_reviewed_summary_revision<>parent.matching_summary_revision)) then
        raise sqlstate 'PT409' using message='matching_conflict';
      end if;
      execute format('update %s set matching_withdrawn=false,matching_audience=''weave_users'',
        matching_share_version=nextval(''private.weave_matching_version''),matching_reviewed_revision=matching_revision,
        matching_reviewed_summary_revision=$3,matching_confirmed_at=now(),matching_expires_at=$4
        where initiative_id=$1 and id=$2',target) using p_id,entry.id,parent.matching_summary_revision,review.expires_at;
    end if;
  end loop;
  if p_review_id is not null then delete from private.weave_matching_reviews where id=p_review_id; end if;
  insert into private.weave_matching_requests(actor_id,request_id,command) values(parent.owner_id,p_request_id,command);
  return private.weave_matching_state(p_id);
end $$;

create function private.weave_matching_projection(e private.weave_matching_current) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('initiativeId',e.initiative_id,'kind',e.kind,'entryId',e.id,
    'revision',e.matching_revision,'shareVersion',e.matching_share_version,'value',e.value,
    'confirmedAt',e.matching_confirmed_at,'expiresAt',e.matching_expires_at,'summary',e.summary);
$$;

create function private.weave_matching_shortlist(p_id uuid,p_entries jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare parent weave.initiatives=private.weave_matching_owner(p_id,false);
  query private.weave_matching_current; ts tsquery; result jsonb='[]'::jsonb;
  selected_count integer=0; public_evidence jsonb; public_result jsonb; public_model_version text; coverage jsonb;
  has_query_vectors boolean=to_regprocedure(
    'private.weave_matching_indexed_public_evidence(uuid,text,uuid,bigint,bigint)') is not null;
  has_index boolean=to_regprocedure('private.weave_public_project_shortlist(text,integer)') is not null
    and to_regprocedure('private.weave_public_project_coverage()') is not null;
begin
  if p_entries is not null then perform private.weave_matching_refs(p_entries); end if;
  for query in select e.* from private.weave_matching_current e where e.initiative_id=p_id
    and (p_entries is null or exists(select from private.weave_matching_refs(p_entries) r
      where (r.kind,r.id,r.revision,r.share_version)=(e.kind,e.id,e.matching_revision,e.matching_share_version)))
    order by e.kind,e.position
  loop
    selected_count=selected_count+1;
    select string_agg(quote_literal(term),' | ')::tsquery into ts
      from unnest(tsvector_to_array(query.terms)) term where length(term)>2;
    public_evidence='[]'::jsonb;
    public_model_version=null;
    if has_index then
      begin
        if has_query_vectors then
          execute 'select private.weave_matching_indexed_public_evidence($1,$2,$3,$4,$5)' into public_result
            using query.initiative_id,query.kind,query.id,query.matching_revision,query.matching_share_version;
          public_evidence=public_result->'evidence';
          public_model_version=public_result->>'modelVersion';
        else
          execute 'select private.weave_public_project_shortlist($1,80)' into public_evidence
            using concat_ws(' ',query.value->>'title',query.value->>'description',query.value->>'purpose');
        end if;
      exception when others then
        has_index=false;
        public_evidence='[]'::jsonb;
      end;
    end if;
    result=result||jsonb_build_array(jsonb_build_object('entry',private.weave_matching_projection(query),
      'publicEvidence',public_evidence,'publicModelVersion',public_model_version,'candidates',coalesce((
      select jsonb_agg(c.projection order by c.rank desc,c.confirmed_at desc,c.initiative_id,c.id)
      from (select private.weave_matching_projection(e) projection,ts_rank(e.terms,ts) rank,
        e.matching_confirmed_at confirmed_at,e.initiative_id,e.id from private.weave_matching_current e
        where e.owner_id<>parent.owner_id and e.kind<>query.kind and e.terms@@ts
        order by rank desc,e.matching_confirmed_at desc,e.initiative_id,e.id limit 75) c
    ),'[]'::jsonb)));
  end loop;
  if p_entries is not null and selected_count<>jsonb_array_length(p_entries) then
    raise sqlstate 'PT409' using message='matching_conflict';
  end if;
  if has_index then
    begin
      execute 'select private.weave_public_project_coverage()' into coverage;
    exception when others then
      coverage=null;
    end;
  end if;
  return jsonb_build_object('groups',result,'externalCoverage',coverage);
end $$;

create function private.weave_matching_weave_candidate(p_candidate text)
returns table(initiative_id uuid,kind text,id uuid) language sql immutable strict set search_path = '' as $$
  select split_part(p_candidate,':',2)::uuid,split_part(p_candidate,':',3),split_part(p_candidate,':',4)::uuid
  where p_candidate ~ '^weave:[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}:(need|offer):[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$';
$$;

create function private.weave_matching_public_status(p_candidate text) returns text
language plpgsql stable set search_path = '' as $$
declare result text;
begin
  if to_regprocedure('private.weave_public_project_status(text)') is null then return 'unknown'; end if;
  begin
    execute 'select private.weave_public_project_status($1)' into result using substring(p_candidate from 8);
  exception when others then return 'unknown';
  end;
  return case when result in ('current','unavailable') then result else 'unknown' end;
end $$;

create function private.weave_matching_leads(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare parent weave.initiatives=private.weave_matching_owner(p_id,false);
begin
  return jsonb_build_object('initiativeId',p_id,'leads',coalesce((
    select jsonb_agg(jsonb_build_object('kind',l.kind,'entryId',l.entry_id,'candidateId',l.candidate_id,
      'disposition',l.disposition,'updatedAt',l.updated_at,'evidenceStatus',case
      when not exists(select from private.weave_matching_entries q
        where (q.initiative_id,q.kind,q.id)=(l.initiative_id,l.kind,l.entry_id)) then 'unavailable'
      when l.candidate_id not like 'weave:%' then private.weave_matching_public_status(l.candidate_id)
      when exists(select from private.weave_matching_current q
        where (q.initiative_id,q.kind,q.id)=(l.initiative_id,l.kind,l.entry_id))
        and exists(select from private.weave_matching_weave_candidate(l.candidate_id) r
          join private.weave_matching_current c on (c.initiative_id,c.kind,c.id)=(r.initiative_id,r.kind,r.id)
          where c.owner_id<>parent.owner_id and c.kind<>l.kind and
            (c.matching_revision,c.matching_summary_revision)=(l.candidate_revision,l.candidate_summary_revision))
        then 'current'
      else 'unavailable' end)
      order by l.updated_at desc,l.kind,l.entry_id,l.candidate_id)
    from private.weave_matching_leads l where l.initiative_id=p_id),'[]'::jsonb));
end $$;

create function private.weave_matching_set_lead(
  p_id uuid,p_entry jsonb,p_candidate_id text,p_disposition text,p_request_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare parent weave.initiatives=private.weave_matching_owner(p_id,true);
  command jsonb;
  entry private.weave_matching_entries; ref record; candidate private.weave_matching_current;
begin
  if p_disposition is null or p_disposition not in ('saved','dismissed','removed')
    or p_candidate_id is null or length(p_candidate_id) not between 1 and 640
    or p_candidate_id ~ '[[:cntrl:][:space:]]'
    or (p_candidate_id !~ '^public:at://did:[a-z]+:[^/[:space:]]+/[a-zA-Z0-9.-]+/[a-zA-Z0-9._~:-]+$' and
        not exists(select from private.weave_matching_weave_candidate(p_candidate_id)))
    or p_candidate_id='public:'
    then raise sqlstate 'PT400' using message='invalid_data'; end if;
  if p_disposition='removed' then
    -- A lead outlives its query entry. Normalize both supported shapes for retries.
    select * into ref from private.weave_matching_refs(jsonb_build_array(p_entry),true);
    p_entry=jsonb_build_object('kind',ref.kind,'entryId',ref.id);
  end if;
  command=jsonb_build_array(p_id,'set_lead',p_entry,p_candidate_id,p_disposition);
  if private.weave_matching_retry(parent.owner_id,p_request_id,command) then return private.weave_matching_leads(p_id); end if;
  if p_disposition='removed' then
    delete from private.weave_matching_leads where initiative_id=p_id and kind=ref.kind
      and entry_id=ref.id and candidate_id=p_candidate_id;
  else
    select * into entry from private.weave_matching_selected(p_id,jsonb_build_array(p_entry));
    if p_candidate_id like 'weave:%' then
      select c.* into candidate from private.weave_matching_weave_candidate(p_candidate_id) r
        join private.weave_matching_current c on (c.initiative_id,c.kind,c.id)=(r.initiative_id,r.kind,r.id)
        where c.owner_id<>parent.owner_id and c.kind<>entry.kind and exists(
          select from private.weave_matching_current q where (q.initiative_id,q.kind,q.id)=(p_id,entry.kind,entry.id));
      if not found then raise sqlstate 'PT409' using message='matching_conflict'; end if;
    end if;
    if not exists(select from private.weave_matching_leads where initiative_id=p_id and kind=entry.kind
      and entry_id=entry.id and candidate_id=p_candidate_id)
      and (select count(*) from private.weave_matching_leads where initiative_id=p_id)>=500
      then raise sqlstate 'PT429' using message='rate_limited'; end if;
    insert into private.weave_matching_leads
      (initiative_id,kind,entry_id,candidate_id,candidate_revision,candidate_summary_revision,disposition)
      values(p_id,entry.kind,entry.id,p_candidate_id,candidate.matching_revision,candidate.matching_summary_revision,p_disposition)
      on conflict(initiative_id,kind,entry_id,candidate_id) do update set disposition=excluded.disposition,
        updated_at=now(),candidate_revision=excluded.candidate_revision,candidate_summary_revision=excluded.candidate_summary_revision;
  end if;
  -- Recalculate evidence status even when returning the result of a retry.
  insert into private.weave_matching_requests(actor_id,request_id,command) values(parent.owner_id,p_request_id,command);
  return private.weave_matching_leads(p_id);
end $$;

revoke all on function private.weave_matching_owner(uuid,boolean),private.weave_matching_refs(jsonb,boolean),
  private.weave_matching_selected(uuid,jsonb),private.weave_matching_retry(uuid,uuid,jsonb),
  private.weave_matching_projection(private.weave_matching_current),private.weave_matching_weave_candidate(text),
  private.weave_matching_public_status(text)
  from public,anon,authenticated;

-- The exposed schema has invoker wrappers only; all cross-owner table access
-- is confined to private functions and the verified projections above.
create function weave.matching_state(p_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select private.weave_matching_state(p_id) $$;
create function weave.matching_preview(p_id uuid,p_revision integer,p_entries jsonb,p_expires_at timestamptz)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.weave_matching_preview(p_id,p_revision,p_entries,p_expires_at)
$$;
create function weave.matching_change(p_id uuid,p_action text,p_request_id uuid,p_review_id uuid,p_entries jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.weave_matching_change(p_id,p_action,p_request_id,p_review_id,p_entries)
$$;
create function weave.matching_shortlist(p_id uuid,p_entries jsonb) returns jsonb
language sql stable security invoker set search_path = '' as $$ select private.weave_matching_shortlist(p_id,p_entries) $$;
create function weave.matching_leads(p_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select private.weave_matching_leads(p_id) $$;
create function weave.matching_set_lead(p_id uuid,p_entry jsonb,p_candidate_id text,p_disposition text,p_request_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.weave_matching_set_lead(p_id,p_entry,p_candidate_id,p_disposition,p_request_id)
$$;

do $$
declare s text; signature text;
begin
  foreach s in array array['private','weave'] loop
    foreach signature in array array['matching_state(uuid)','matching_preview(uuid,integer,jsonb,timestamptz)',
      'matching_change(uuid,text,uuid,uuid,jsonb)','matching_shortlist(uuid,jsonb)','matching_leads(uuid)',
      'matching_set_lead(uuid,jsonb,text,text,uuid)'] loop
      if s='private' then signature='weave_'||signature; end if;
      execute format('revoke all on function %I.%s from public,anon,authenticated',s,signature);
      execute format('grant execute on function %I.%s to authenticated',s,signature);
    end loop;
  end loop;
end $$;
