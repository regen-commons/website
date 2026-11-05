-- Private Weave saving only. No publishing, membership change or email dispatch.
create schema weave;
revoke all on schema weave from public, anon, authenticated;
grant usage on schema weave to authenticated;
alter default privileges in schema weave revoke all on tables from public, anon, authenticated;
alter default privileges in schema weave revoke execute on functions from public, anon, authenticated;

create function private.weave_actor() returns uuid
language sql stable security definer set search_path = '' as $$
  select auth.uid() where auth.uid() is not null
    and auth.jwt()->>'role' = 'authenticated'
    and coalesce(auth.jwt()->>'is_anonymous','false') = 'false'
    and exists(select 1 from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null)
    and exists(select 1 from auth.sessions s where s.user_id=auth.uid()
      and s.id::text=auth.jwt()->>'session_id' and (s.not_after is null or s.not_after>now()));
$$;
revoke all on function private.weave_actor() from public, anon, authenticated;
grant execute on function private.weave_actor() to authenticated;

create table weave.accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table weave.initiatives (
  id uuid primary key,
  owner_id uuid not null references weave.accounts(user_id) on delete cascade,
  visibility text not null default 'private' check(visibility='private'),
  revision integer not null default 1 check(revision>0),
  card jsonb not null check(jsonb_typeof(card)='object'),
  funding jsonb not null check(jsonb_typeof(funding)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index weave_initiatives_owner on weave.initiatives(owner_id,updated_at desc,id);
create table weave.needs (
  initiative_id uuid not null references weave.initiatives(id) on delete cascade,
  id uuid not null,
  position integer not null check(position between 0 and 4),
  value jsonb not null check(jsonb_typeof(value)='object'),
  primary key(initiative_id,id), unique(initiative_id,position)
);
create table weave.offers (like weave.needs including all);
alter table weave.offers add foreign key(initiative_id) references weave.initiatives(id) on delete cascade;
create table private.weave_save_requests (
  actor_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  initiative_id uuid not null references weave.initiatives(id) on delete cascade,
  expected_revision integer not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key(actor_id,request_id)
);
create table private.weave_save_limits (
  actor_id uuid not null references auth.users(id) on delete cascade,
  window_start timestamptz not null,
  total integer not null,
  primary key(actor_id,window_start)
);
alter table private.weave_save_limits enable row level security;
revoke all on private.weave_save_limits from public,anon,authenticated;
alter table private.weave_save_requests enable row level security;
revoke all on private.weave_save_requests from public,anon,authenticated;

do $$ declare t text; begin
  foreach t in array array['accounts','initiatives','needs','offers'] loop
    execute format('alter table weave.%I enable row level security',t);
    execute format('revoke all on weave.%I from public,anon,authenticated',t);
    execute format('grant select on weave.%I to authenticated',t);
  end loop;
end $$;
create policy owner_read on weave.accounts for select to authenticated
  using(user_id=(select private.weave_actor()));
create policy owner_read on weave.initiatives for select to authenticated
  using(owner_id=(select private.weave_actor()));
create policy owner_read on weave.needs for select to authenticated
  using(exists(select 1 from weave.initiatives i where i.id=initiative_id and i.owner_id=(select private.weave_actor())));
create policy owner_read on weave.offers for select to authenticated
  using(exists(select 1 from weave.initiatives i where i.id=initiative_id and i.owner_id=(select private.weave_actor())));

-- Validate direct RPC calls as well as the HTTP boundary. No unchecked extras,
-- conversations, file bytes, owner claims or visibility flags can be persisted.
create function private.weave_valid_document(d jsonb) returns boolean
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
      if field='lenses' and k not in ('art_culture','research','technology','place_based','funders') then return false; end if;
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
      if jsonb_typeof(v->'capitalForms')<>'array' or jsonb_array_length(v->'capitalForms') not between 1 and 8
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
revoke all on function private.weave_valid_document(jsonb) from public,anon,authenticated;

create function weave.account_access() returns boolean
language sql stable security invoker set search_path = '' as $$ select private.weave_actor() is not null $$;
create function weave.list_initiatives(p_offset integer default 0) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
begin
  if private.weave_actor() is null then raise sqlstate 'PT401' using message='sign_in_required';end if;
  if p_offset is null or p_offset<0 or p_offset>10000 then raise sqlstate 'PT400' using message='invalid_data';end if;
  return coalesce((select jsonb_agg(x.doc order by x.updated_at desc,x.id) from
    (select i.id,i.updated_at,jsonb_build_object('id',i.id,'revision',i.revision,'name',i.card->>'name','updatedAt',i.updated_at) doc from weave.initiatives i order by i.updated_at desc,i.id limit 20 offset p_offset) x),'[]'::jsonb);
end $$;
create function weave.load_initiative(p_id uuid) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare result jsonb;
begin
  if private.weave_actor() is null then raise sqlstate 'PT401' using message='sign_in_required';end if;
  select jsonb_build_object('id',i.id,'revision',i.revision,'updatedAt',i.updated_at,'document',jsonb_build_object('version',1,'initiative',i.card,'funding',i.funding,
    'needs',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'value',n.value) order by n.position) from weave.needs n where n.initiative_id=i.id),'[]'::jsonb),
    'offers',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'value',o.value) order by o.position) from weave.offers o where o.initiative_id=i.id),'[]'::jsonb))) into result from weave.initiatives i where i.id=p_id;
  if result is null then raise sqlstate 'PT404' using message='not_found';end if;return result;
end $$;

create function private.weave_save_initiative(p_id uuid,p_expected_revision integer,p_request_id uuid,p_document jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor uuid=private.weave_actor(); old private.weave_save_requests%rowtype; current weave.initiatives%rowtype; result jsonb; a jsonb; position integer; quota integer;
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
    select * into current from weave.initiatives where id=p_id for update;
    if not found or current.owner_id<>actor then raise sqlstate 'PT404' using message='not_found';end if;
    if current.revision<>p_expected_revision then raise sqlstate 'PT409' using message='revision_conflict';end if;
    update weave.initiatives set card=p_document->'initiative',funding=p_document->'funding',revision=revision+1,updated_at=now() where id=p_id returning * into current;
    delete from weave.needs where initiative_id=p_id;
    delete from weave.offers where initiative_id=p_id;
  end if;
  position=0;for a in select * from jsonb_array_elements(p_document->'needs') loop insert into weave.needs values(p_id,(a->>'id')::uuid,position,a->'value');position=position+1;end loop;
  position=0;for a in select * from jsonb_array_elements(p_document->'offers') loop insert into weave.offers values(p_id,(a->>'id')::uuid,position,a->'value');position=position+1;end loop;
  -- Explicitly scoped: the invoker read RPC also enforces RLS for every caller.
  result=jsonb_build_object('id',p_id,'revision',current.revision,'updatedAt',current.updated_at,'document',p_document);
  insert into private.weave_save_requests(actor_id,request_id,initiative_id,expected_revision,response)
    values(actor,p_request_id,p_id,p_expected_revision,result);
  return result;
end $$;
revoke all on function private.weave_save_initiative(uuid,integer,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.weave_save_initiative(uuid,integer,uuid,jsonb) to authenticated;
create function weave.save_initiative(p_id uuid,p_expected_revision integer,p_request_id uuid,p_document jsonb) returns jsonb
language sql security invoker set search_path = '' as $$ select private.weave_save_initiative(p_id,p_expected_revision,p_request_id,p_document) $$;
revoke all on all functions in schema weave from public,anon,authenticated;
grant execute on function weave.account_access(),weave.list_initiatives(integer),weave.load_initiative(uuid),weave.save_initiative(uuid,integer,uuid,jsonb) to authenticated;

comment on schema weave is 'Private Weave account saving. Exposure via the Data API is an explicit release setting, not enabled by this migration.';
comment on table weave.accounts is 'An Auth account is not membership and creates no public profile or subscription.';
comment on table weave.initiatives is 'Checked card only. Source conversations, file bytes, unfinished edits and assistant records remain on the device.';
