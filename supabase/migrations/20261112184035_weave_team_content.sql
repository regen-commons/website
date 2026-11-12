-- Local candidate after Certified project workspaces and matching.
-- The matching cutover requires the workspace-aware API. Apply both together.
alter table weave_workspace.project_links add column matching_paused boolean not null default false;
alter table weave.initiatives alter column owner_id drop not null;
alter table weave.initiatives
  add column team_workspace_id uuid unique references weave_workspace.project_links(id) on delete cascade,
  add constraint weave_initiative_ownership check (
    (owner_id is not null and team_workspace_id is null)
    or (owner_id is null and team_workspace_id is not null and team_workspace_id=id)
  );

-- The existing owner RLS predicates keep team documents out of personal reads.
-- Share the checked-document validator and save transaction with the team path.
create or replace function private.weave_valid_document(d jsonb,p_allow_unclassified boolean) returns boolean
language plpgsql immutable security invoker set search_path = '' as $$
declare c jsonb; f jsonb; a jsonb; v jsonb; x jsonb; field text; seen text[]; k text; n numeric;
begin
  if d is null or jsonb_typeof(d)<>'object' or octet_length(d::text)>60000
     or not(d ?& array['version','initiative','needs','offers','funding'])
     or (d-array['version','initiative','needs','offers','funding'])<>'{}'::jsonb or d->'version'<>'1'::jsonb then return false; end if;
  c=d->'initiative';
  if jsonb_typeof(c)<>'object' or not(c ?& array['name','description','locations','isGlobal','links','stage','lenses','themes','beneficiaries','languages'])
    or (c-array['name','description','locations','isGlobal','links','stage','lenses','themes','beneficiaries','languages'])<>'{}'::jsonb
    or jsonb_typeof(c->'name')<>'string' or length(btrim(c->>'name')) not between 1 and 200
    or jsonb_typeof(c->'description')<>'string' or length(c->>'description')>800 or jsonb_typeof(c->'isGlobal')<>'boolean'
    or (c->'stage'<>'null'::jsonb and c->>'stage' not in ('seed','sprout','flowering','tree')) then return false; end if;
  foreach field in array array['locations','links','lenses','themes','beneficiaries','languages'] loop
    x=c->field;
    if jsonb_typeof(x)<>'array' or jsonb_array_length(x)>(case field when 'locations' then 8 when 'lenses' then 5 when 'themes' then 10 else 6 end) then return false; end if;
    seen='{}';
    for v in select * from jsonb_array_elements(x) loop
      k=v#>>'{}';
      if jsonb_typeof(v)<>'string' or length(k)=0 or k=any(seen) then return false; end if;seen=array_append(seen,k);
      if length(k)>(case field when 'locations' then 120 when 'links' then 2048 when 'themes' then 60 when 'beneficiaries' then 80 else 80 end) then return false; end if;
      if field='links' and (k !~* '^https?://' or k ~ '://[^/]*@') then return false; end if;
      if field='lenses' and k not in ('art_culture','research','technology','place_based','learning','funders') then return false; end if;
      if field='languages' and k !~ '^[a-z]{2}$' then return false; end if;
    end loop;
  end loop;
  foreach field in array array['needs','offers'] loop
    x=d->field;seen='{}';
    if jsonb_typeof(x)<>'array' or jsonb_array_length(x)>5 then return false; end if;
    for a in select * from jsonb_array_elements(x) loop
      if jsonb_typeof(a)<>'object' or not(a ?& array['id','value']) or (a-array['id','value'])<>'{}'::jsonb then return false; end if;
      if jsonb_typeof(a->'id')<>'string' then return false;end if;k=(a->>'id')::uuid::text;if k=any(seen) then return false;end if;seen=array_append(seen,k);
      v=a->'value';
      if jsonb_typeof(v)<>'object' or not(v ?& array['title','description','capitalForms','amount','timeframe','urgency','placeScope','exchangeTerms','purpose','capacity','audience','status'])
        or (v-array['title','description','capitalForms','amount','timeframe','urgency','placeScope','exchangeTerms','purpose','capacity','audience','status'])<>'{}'::jsonb
        or jsonb_typeof(v->'title')<>'string' or length(btrim(v->>'title')) not between 1 and 140 then return false;end if;
      foreach k in array array['description','timeframe','purpose','capacity','audience'] loop
        if v->k<>'null'::jsonb and (jsonb_typeof(v->k)<>'string' or length(v->>k)>(case k when 'description' then 600 when 'purpose' then 400 else 200 end)) then return false;end if;
      end loop;
      if jsonb_typeof(v->'capitalForms')<>'array' or jsonb_array_length(v->'capitalForms') not between (case when p_allow_unclassified then 0 else 1 end) and 8
        or exists(select 1 from jsonb_array_elements_text(v->'capitalForms') z where z not in ('living','material','intellectual','experiential','social','financial','cultural','spiritual'))
        or (select count(*)<>count(distinct z) from jsonb_array_elements_text(v->'capitalForms') z)
        or jsonb_typeof(v->'placeScope')<>'string' or jsonb_typeof(v->'status')<>'string' or v->>'placeScope' not in ('here','region','anywhere') or v->>'status' not in ('open','met','withdrawn','expired')
        or (v->'urgency'<>'null'::jsonb and v->>'urgency' not in ('now','this_quarter','this_year','ongoing')) then return false;end if;
      if jsonb_typeof(v->'exchangeTerms')<>'array' or jsonb_array_length(v->'exchangeTerms') not between 1 and 5
        or exists(select 1 from jsonb_array_elements_text(v->'exchangeTerms') z where z not in ('gift','exchange','paid','commitment','open'))
        or (select count(*)<>count(distinct z) from jsonb_array_elements_text(v->'exchangeTerms') z)
        or (v->'exchangeTerms' ? 'open' and jsonb_array_length(v->'exchangeTerms')<>1) then return false;end if;
      if v->'amount'<>'null'::jsonb then
        c=v->'amount';
        if not(v->'capitalForms' ? 'financial') or jsonb_typeof(c)<>'object' or not(c ?& array['min','max','currency'])
          or (c-array['min','max','currency'])<>'{}'::jsonb or jsonb_typeof(c->'currency')<>'string' or c->>'currency' !~ '^[A-Z]{3}$'
          or (c->'min'='null'::jsonb and c->'max'='null'::jsonb) then return false;end if;
        foreach k in array array['min','max'] loop if c->k<>'null'::jsonb then n=(c->>k)::numeric;if jsonb_typeof(c->k)<>'number' or n<0 or n>1.7976931348623157e308 then return false;end if;end if;end loop;
        if (c->>'min')::numeric>(c->>'max')::numeric then return false;end if;
      end if;
    end loop;
  end loop;
  f=d->'funding';c=f->'form';
  if jsonb_typeof(f)<>'object' or not(f ?& array['form','programAnswers']) or (f-array['form','programAnswers'])<>'{}'::jsonb
    or jsonb_typeof(c)<>'object' or not(c ?& array['workCountries','benefitCountries','applicantBaseCountry','registrationCountry','applicantType','fundingInstruments','goalMin','goalMax','currency','usWorkStates','usBenefitStates'])
    or (c-array['workCountries','benefitCountries','applicantBaseCountry','registrationCountry','applicantType','fundingInstruments','goalMin','goalMax','currency','usWorkStates','usBenefitStates'])<>'{}'::jsonb then return false;end if;
  foreach field in array array['workCountries','benefitCountries','applicantBaseCountry','registrationCountry','goalMin','goalMax','currency','usWorkStates','usBenefitStates'] loop
    if jsonb_typeof(c->field)<>'string' or length(c->>field)>(case field when 'workCountries' then 800 when 'benefitCountries' then 800 when 'applicantBaseCountry' then 2 when 'registrationCountry' then 2 when 'currency' then 3 when 'goalMin' then 60 when 'goalMax' then 60 else 200 end) then return false;end if;
  end loop;
  if jsonb_typeof(c->'applicantType')<>'string' or c->>'applicantType' not in ('unknown','nonprofit','informal','individual','business','university','public-body') or jsonb_typeof(c->'fundingInstruments')<>'array'
    or jsonb_array_length(c->'fundingInstruments')>5 or exists(select 1 from jsonb_array_elements_text(c->'fundingInstruments') z where z not in ('grant','prize','investment','fellowship','scholarship')) then return false;end if;
  if (select count(*)<>count(distinct z) from jsonb_array_elements_text(c->'fundingInstruments') z) or exists(select 1 from jsonb_array_elements(c->'fundingInstruments') z where jsonb_typeof(z)<>'string') then return false;end if;
  if jsonb_typeof(f->'programAnswers')<>'object' then return false;end if;
  for k,a in select key,value from jsonb_each(f->'programAnswers') loop
    if k !~ '^[a-zA-Z0-9_-]+::[a-zA-Z0-9_-]+::[a-zA-Z0-9_-]+$' or jsonb_typeof(a)<>'object' or not(a ?& array['answer','sourceCheckedOn'])
      or jsonb_typeof(a->'answer')<>'string' or jsonb_typeof(a->'sourceCheckedOn')<>'string' or (a-array['answer','sourceCheckedOn'])<>'{}'::jsonb or a->>'answer' not in ('yes','no') or a->>'sourceCheckedOn' !~ '^\d{4}-\d{2}-\d{2}$' then return false;end if;
    perform (a->>'sourceCheckedOn')::date;
  end loop;
  return true;
exception when others then return false;
end $$;

create or replace function private.weave_save_document(p_id uuid,p_expected_revision integer,p_request_id uuid,p_document jsonb,p_team boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor uuid=private.weave_actor(); old private.weave_save_requests%rowtype; current weave.initiatives%rowtype; result jsonb; quota integer;
begin
  if actor is null then raise sqlstate 'PT401' using message='sign_in_required';end if;
  if p_id is null or p_request_id is null or p_expected_revision is null or p_expected_revision<0 or p_expected_revision>=2147483647 or not private.weave_valid_document(p_document,true) then raise sqlstate 'PT400' using message='invalid_data';end if;
  if not p_team and exists(select 1 from weave_workspace.project_links where id=p_id and group_did is not null) then
    raise sqlstate 'PT404' using message='not_found';
  end if;
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
  if not p_team then insert into weave.accounts(user_id) values(actor) on conflict do nothing; end if;
  if p_expected_revision=0 then
    insert into weave.initiatives(id,owner_id,team_workspace_id,card,funding)
    values(p_id,case when not p_team then actor end,case when p_team then p_id end,p_document->'initiative',p_document->'funding') on conflict do nothing returning * into current;
    if not found then raise sqlstate 'PT409' using message='revision_conflict';end if;
  else
    select * into current from weave.initiatives where id=p_id and ((p_team and team_workspace_id=p_id) or (not p_team and owner_id=actor)) for update;
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

create or replace function private.weave_valid_document(d jsonb) returns boolean
language sql immutable set search_path = '' as $$ select private.weave_valid_document(d,false) $$;

create or replace function private.weave_save_initiative(p_id uuid,p_expected_revision integer,p_request_id uuid,p_document jsonb)
returns jsonb language sql security definer set search_path = '' as $$
  select private.weave_save_document(p_id,p_expected_revision,p_request_id,p_document,false);
$$;

revoke all on function private.weave_valid_document(jsonb,boolean),
  private.weave_save_document(uuid,integer,uuid,jsonb,boolean) from public,anon,authenticated,service_role,weave_workspace_runtime;

create or replace view private.weave_matching_current as
  select e.*, i.owner_id, i.matching_summary_revision, private.weave_matching_summary(i.card) as summary,
    private.weave_matching_terms(e.value) as terms
  from private.weave_matching_entries e join weave.initiatives i on i.id=e.initiative_id
  join weave_workspace.project_links l on l.id=i.id
  where not l.matching_paused and e.matching_audience='weave_users' and not e.matching_withdrawn
    and e.matching_reviewed_revision=e.matching_revision
    and e.matching_reviewed_summary_revision=i.matching_summary_revision
    and e.value->>'status'='open' and jsonb_array_length(e.value->'capitalForms')>0
    and e.matching_expires_at>now();

create or replace function private.weave_matching_owner(p_id uuid,p_lock boolean)
returns weave.initiatives language plpgsql set search_path = '' as $$
declare actor uuid=private.weave_actor(); result weave.initiatives;
begin
  if actor is null then raise sqlstate 'PT401' using message='sign_in_required'; end if;
  if p_id is null then raise sqlstate 'PT400' using message='invalid_data'; end if;
  if p_lock then
    select * into result from weave.initiatives where id=p_id and (owner_id=actor or exists(
      select from weave_workspace.access_grants g where g.workspace_id=team_workspace_id
        and g.user_id=actor and g.suspended_at is null and g.access_role in ('editor','admin'))) for update;
  else
    select * into result from weave.initiatives where id=p_id and (owner_id=actor or exists(
      select from weave_workspace.access_grants g where g.workspace_id=team_workspace_id
        and g.user_id=actor and g.suspended_at is null));
  end if;
  if not found then raise sqlstate 'PT404' using message='not_found'; end if;
  if p_lock and private.weave_actor() is distinct from actor then
    raise sqlstate 'PT401' using message='sign_in_required';
  end if;
  return result;
end $$;

create or replace function private.weave_matching_preview(p_id uuid,p_revision integer,p_entries jsonb,p_expires_at timestamptz)
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
    into selected from private.weave_matching_selected(p_id,p_entries) e where e.value->>'status'='open' and jsonb_array_length(e.value->'capitalForms')>0;
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

create or replace function private.weave_matching_change(
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
  if private.weave_matching_retry(private.weave_actor(),p_request_id,command) then return private.weave_matching_state(p_id); end if;
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
      if entry.value->>'status'<>'open' or jsonb_array_length(entry.value->'capitalForms')=0 or (p_action='renew' and (
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
  insert into private.weave_matching_requests(actor_id,request_id,command) values(private.weave_actor(),p_request_id,command);
  return private.weave_matching_state(p_id);
end $$;

create or replace function private.weave_matching_shortlist(p_id uuid,p_entries jsonb) returns jsonb
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
        where e.initiative_id<>p_id and (parent.owner_id is null or e.owner_id is distinct from parent.owner_id) and e.kind<>query.kind and e.terms@@ts
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

create or replace function private.weave_matching_leads(p_id uuid) returns jsonb
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
          where c.initiative_id<>p_id and (parent.owner_id is null or c.owner_id is distinct from parent.owner_id) and c.kind<>l.kind and
            (c.matching_revision,c.matching_summary_revision)=(l.candidate_revision,l.candidate_summary_revision))
        then 'current'
      else 'unavailable' end)
      order by l.updated_at desc,l.kind,l.entry_id,l.candidate_id)
    from private.weave_matching_leads l where l.initiative_id=p_id),'[]'::jsonb));
end $$;

create or replace function private.weave_matching_set_lead(
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
  if private.weave_matching_retry(private.weave_actor(),p_request_id,command) then return private.weave_matching_leads(p_id); end if;
  if p_disposition='removed' then
    delete from private.weave_matching_leads where initiative_id=p_id and kind=ref.kind
      and entry_id=ref.id and candidate_id=p_candidate_id;
  else
    select * into entry from private.weave_matching_selected(p_id,jsonb_build_array(p_entry));
    if p_candidate_id like 'weave:%' then
      select c.* into candidate from private.weave_matching_weave_candidate(p_candidate_id) r
        join private.weave_matching_current c on (c.initiative_id,c.kind,c.id)=(r.initiative_id,r.kind,r.id)
        where c.initiative_id<>p_id and (parent.owner_id is null or c.owner_id is distinct from parent.owner_id) and c.kind<>entry.kind and exists(
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
  insert into private.weave_matching_requests(actor_id,request_id,command) values(private.weave_actor(),p_request_id,command);
  return private.weave_matching_leads(p_id);
end $$;

-- Target discovery is limited to the actor's current local grant. The server
-- checks Certified before returning any workspace content or matching state.
create function weave_workspace.content_target(p_actor uuid,p_session uuid,p_did text,p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare link weave_workspace.project_links; access jsonb;
begin
  if p_did is null or weave_workspace.weave_project_actor(p_actor,p_session) is distinct from p_did then
    raise sqlstate 'PT401' using message='sign_in_required';
  end if;
  select * into link from weave_workspace.project_links where id=p_id;
  access := weave_workspace.link_result(link,p_actor,p_did,'member');
  if access->>'status' <> 'linked' then raise sqlstate 'PT404' using message='not_found'; end if;
  return access || jsonb_build_object('groupDid',link.group_did,'repositoryDid',link.repository_did);
end $$;

create function weave_workspace.content_command(
  p_actor uuid,p_session uuid,p_did text,p_id uuid,p_group_role text,p_cid text,p_action text,p_data jsonb
) returns jsonb language plpgsql security definer set search_path = ''
  set "request.jwt.claims" = '' set "request.jwt.claim.sub" = '' as $$
declare link weave_workspace.project_links; access jsonb;
begin
  if p_did is null or weave_workspace.weave_project_actor(p_actor,p_session) is distinct from p_did then
    raise sqlstate 'PT401' using message='sign_in_required';
  end if;
  select * into link from weave_workspace.project_links where id=p_id;
  if not found then raise sqlstate 'PT404' using message='not_found'; end if;
  -- Same lock as setup, grant and suspension. Check authority again after it.
  perform pg_advisory_xact_lock(hashtextextended('weave-project:'||link.project_uri,0));
  if weave_workspace.weave_project_actor(p_actor,p_session) is distinct from p_did then
    raise sqlstate 'PT401' using message='sign_in_required';
  end if;
  select * into link from weave_workspace.project_links where id=p_id;
  access := weave_workspace.link_result(link,p_actor,p_did,p_group_role);
  if access->>'status' <> 'linked' then raise sqlstate 'PT404' using message='not_found'; end if;
  if p_action in ('team_save','matching_preview','matching_change','matching_set_lead')
    and access->>'accessRole' not in ('editor','admin') then
    raise sqlstate 'PT403' using message='workspace_edit_required';
  end if;

  if p_action in ('team_load','team_save') and link.group_did is null then
    raise sqlstate 'PT404' using message='not_found';
  end if;
  if p_action='pause_matching' then
    if not link.matching_paused then
      update weave_workspace.project_links set matching_paused=true where id=p_id;
      update weave.initiatives set matching_summary_revision=matching_summary_revision+1 where id=p_id;
      delete from private.weave_matching_reviews where initiative_id=p_id;
    end if;
    return null;
  end if;
  if p_action not in ('team_load','team_save') then
    if not coalesce(weave_workspace.valid_project(link.project_uri,link.repository_did,p_cid),false) then
      raise sqlstate 'PT403' using message='project_verification_required';
    end if;
    if link.matching_paused or link.cid<>p_cid then
      update weave_workspace.project_links set matching_paused=false,cid=p_cid,verified_at=clock_timestamp() where id=p_id;
    end if;
  end if;

  -- Only this restricted command can enter the old matching functions.
  -- They reuse the checked actor for locking and mutation receipts.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'session_id',p_session,
    'role','authenticated','exp',extract(epoch from clock_timestamp()+interval '1 minute'))::text,true);
  perform set_config('request.jwt.claim.sub',p_actor::text,true);
  case p_action
    when 'team_load' then
      return jsonb_build_object('accessRole',access->>'accessRole','saved',
        case when exists(select from weave.initiatives where team_workspace_id=p_id)
          then weave.load_initiative(p_id) end);
    when 'team_save' then
      return private.weave_save_document(p_id,(p_data->>'expectedRevision')::integer,
        (p_data->>'requestId')::uuid,p_data->'document',true);
    when 'public_evidence' then
      return private.weave_public_project_snapshot(link.project_uri) || jsonb_build_object('workspaceId',p_id);
    when 'matching_state' then return private.weave_matching_state(p_id);
    when 'matching_preview' then return private.weave_matching_preview(p_id,(p_data->>'p_revision')::integer,
      p_data->'p_entries',(p_data->>'p_expires_at')::timestamptz);
    when 'matching_change' then return private.weave_matching_change(p_id,p_data->>'p_action',
      (p_data->>'p_request_id')::uuid,(p_data->>'p_review_id')::uuid,nullif(p_data->'p_entries','null'::jsonb));
    when 'matching_shortlist' then return private.weave_matching_shortlist(p_id,nullif(p_data->'p_entries','null'::jsonb));
    when 'matching_leads' then return private.weave_matching_leads(p_id);
    when 'matching_set_lead' then return private.weave_matching_set_lead(p_id,p_data->'p_entry',
      p_data->>'p_candidate_id',p_data->>'p_disposition',(p_data->>'p_request_id')::uuid);
    else raise sqlstate 'PT400' using message='invalid_data';
  end case;
end $$;

revoke all on function weave_workspace.content_target(uuid,uuid,text,uuid),
  weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)
  from public,anon,authenticated,service_role,weave_workspace_runtime;
grant execute on function weave_workspace.content_target(uuid,uuid,text,uuid),
  weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb) to weave_workspace_runtime;

-- A bearer token alone has no fresh upstream authority and cannot bypass the API.
do $$
declare signature text;
begin
  foreach signature in array array['matching_state(uuid)','matching_preview(uuid,integer,jsonb,timestamptz)',
    'matching_change(uuid,text,uuid,uuid,jsonb)','matching_shortlist(uuid,jsonb)','matching_leads(uuid)',
    'matching_set_lead(uuid,jsonb,text,text,uuid)'] loop
    execute format('revoke all on function weave.%s from public,anon,authenticated,service_role',signature);
    execute format('revoke all on function private.weave_%s from public,anon,authenticated,service_role',signature);
  end loop;
end $$;
