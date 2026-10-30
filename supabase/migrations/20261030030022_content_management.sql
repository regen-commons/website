-- Content moderation and the Supabase-only public data boundary.
alter table public.members add column vision text not null default '',
  add column avatar text, add column applied_at date;
alter table public.contributions add column revision integer not null default 1 check (revision > 0),
  add column created_at timestamptz not null default now(),
  add column updated_at timestamptz not null default now();
-- Legacy exports may lack application evidence. Preserve absence rather than invent it.
alter table public.applications alter column email drop not null,
  alter column submitted_at drop not null,
  drop constraint applications_member_id_key;

-- Match the existing browser/API UTF-16 length contract, including emoji.
create function private.utf16_length(value text) returns integer
language sql immutable strict security invoker set search_path='' as $$
 select coalesce(sum(case when ascii(character)>65535 then 2 else 1 end),0)::integer
 from regexp_split_to_table(value,'') as parts(character);
$$;
revoke all on function private.utf16_length(text) from public,anon,authenticated;
create table public.seeds (
  id uuid primary key default gen_random_uuid(), source_notion_id text unique,
  text text not null check (private.utf16_length(text) between 3 and 240),
  author text not null default '' check (private.utf16_length(author) <= 80),
  tags text[] not null default '{}',
  publication_state text not null default 'published' check (publication_state in ('published','hidden')),
  revision integer not null default 1 check (revision > 0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.content_events (
  id uuid primary key default gen_random_uuid(),
  seed_id uuid references public.seeds(id), contribution_id uuid references public.contributions(id),
  actor_id uuid not null references auth.users(id), actor_label text not null,
  action text not null check (action in ('created','updated','hidden','restored')),
  revision integer not null check (revision > 0), reason text not null default '',
  created_at timestamptz not null default now(),
  check ((seed_id is null) <> (contribution_id is null))
);
create index content_events_seed on public.content_events(seed_id,created_at);
create index content_events_contribution on public.content_events(contribution_id,created_at);
create index content_events_actor on public.content_events(actor_id);
create index seeds_order on public.seeds(created_at desc,id);
create index applications_member on public.applications(member_id);
do $$ declare t text; begin
  foreach t in array array['seeds','content_events'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
    execute format('create policy steward_read on public.%I for select to authenticated using ((select private.is_active_steward()))',t);
  end loop;
end $$;

-- Only approved public fields are granted. Private applications/history stay closed.
grant select(id,source_notion_id,name,member_type,location,vision,website,avatar,focus_areas,contribution_areas,applied_at,publication_state) on public.members to anon;
grant select on public.affiliations,public.contribution_members to anon;
grant select(id,source_notion_id,title,publication_state,description,contribution_type,stage,capital_forms,tier,terms,license,tags,contributed_at) on public.contributions to anon;
grant select(id,source_notion_id,text,author,tags,publication_state) on public.seeds to anon;
create policy website_read on public.members for select to anon using (publication_state='published');
create policy website_read on public.contributions for select to anon using (publication_state='published');
create policy website_read on public.seeds for select to anon using (publication_state='published');
create policy website_read on public.affiliations for select to anon using (
  exists(select 1 from public.members m where m.id=member_id and m.publication_state='published')
  and exists(select 1 from public.members m where m.id=organization_id and m.publication_state='published'));
create policy website_read on public.contribution_members for select to anon using (
  exists(select 1 from public.members m where m.id=member_id and m.publication_state='published')
  and exists(select 1 from public.contributions c where c.id=contribution_id and c.publication_state='published'));
create view public.website_members with (security_invoker=true) as
select coalesce(m.source_notion_id,m.id::text) id,m.name,
  case m.member_type when 'organization' then 'Organization' else 'Individual' end type,
  'Active'::text status,m.location,m.focus_areas as "focusAreas",m.contribution_areas as "contributionAreas",
  m.vision,coalesce(m.website,'') website,coalesce(m.avatar,'') avatar,
  coalesce((select jsonb_agg(coalesce(o.source_notion_id,o.id::text) order by o.id)
    from public.affiliations a join public.members o on o.id=a.organization_id
    where a.member_id=m.id and o.publication_state='published'),'[]'::jsonb) as "affiliationIds",
  coalesce(m.applied_at::text,'') as "dateApplied"
from public.members m where m.publication_state='published';
create view public.website_contributions with (security_invoker=true) as
select coalesce(c.source_notion_id,c.id::text) id,c.title,coalesce(c.contribution_type,'') type,
  coalesce(c.stage,'') stage,'Active'::text status,c.description,c.capital_forms as "capitalForm",
  coalesce(c.tier,'') tier,coalesce(c.terms,'') terms,coalesce(c.license,'') license,c.tags,
  coalesce(c.contributed_at::text,'') as "dateContributed",
  coalesce((select jsonb_agg(jsonb_build_object('id',coalesce(m.source_notion_id,m.id::text),'name',m.name) order by m.id)
    from public.contribution_members cm join public.members m on m.id=cm.member_id
    where cm.contribution_id=c.id and m.publication_state='published'),'[]'::jsonb) contributors
from public.contributions c where c.publication_state='published';
create view public.website_seeds with (security_invoker=true) as
select coalesce(source_notion_id,id::text) id,text,author,tags from public.seeds where publication_state='published';
revoke all on public.website_members,public.website_contributions,public.website_seeds from public,anon,authenticated;
grant select on public.website_members,public.website_contributions,public.website_seeds to anon;

create function private.moderate_content(p_resource text,p_id uuid,p_revision integer,p_state text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old_state text; rev integer; begin
  if auth.uid() is null or not private.is_active_steward() then raise sqlstate 'PT403' using message='steward_required'; end if;
  if p_resource is null or p_state is null or p_resource not in ('seeds','contributions') or p_state not in ('published','hidden')
    or p_reason is null or char_length(trim(p_reason)) not between 1 and 1000 or p_revision is null then
    raise sqlstate 'PT400' using message='invalid_moderation'; end if;
  if p_resource='seeds' then
    select publication_state,revision into old_state,rev from public.seeds where id=p_id for update;
  else
    select publication_state,revision into old_state,rev from public.contributions where id=p_id for update;
  end if;
  if not found then raise sqlstate 'PT404' using message='content_not_found'; end if;
  if rev<>p_revision then raise sqlstate 'PT409' using message='revision_conflict'; end if;
  if old_state=p_state then return jsonb_build_object('id',p_id,'revision',rev,'publication_state',p_state); end if;
  if p_resource='seeds' then
    update public.seeds set publication_state=p_state,revision=rev+1,updated_at=now() where id=p_id;
  else
    update public.contributions set publication_state=p_state,revision=rev+1,updated_at=now() where id=p_id;
  end if;
  insert into public.content_events(seed_id,contribution_id,actor_id,actor_label,action,revision,reason)
    values(case when p_resource='seeds' then p_id end,case when p_resource='contributions' then p_id end,
      auth.uid(),(select email from auth.users where id=auth.uid()),case when p_state='hidden' then 'hidden' else 'restored' end,rev+1,trim(p_reason));
  return jsonb_build_object('id',p_id,'revision',rev+1,'publication_state',p_state);
end $$;
create function public.moderate_content(p_resource text,p_id uuid,p_revision integer,p_state text,p_reason text)
returns jsonb language sql security invoker set search_path='' as $$
  select private.moderate_content(p_resource,p_id,p_revision,p_state,p_reason);
$$;

create table private.content_requests(request_id uuid primary key,actor_id uuid not null references auth.users(id),command jsonb not null,result jsonb not null);
alter table private.content_requests enable row level security;
create index content_requests_actor on private.content_requests(actor_id);
revoke all on private.content_requests from public,anon,authenticated;
create function private.save_contribution(p_id uuid,p_revision integer,p_payload jsonb,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid; rev integer; mid uuid; prior private.content_requests; command jsonb; answer jsonb; begin
  if auth.uid() is null or not private.is_active_steward() then raise sqlstate 'PT403' using message='steward_required'; end if;
  if p_request_id is null then raise sqlstate 'PT400' using message='invalid_request_id'; end if;
  command:=jsonb_build_object('id',p_id,'revision',p_revision,'payload',p_payload);
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,1));
  select * into prior from private.content_requests where request_id=p_request_id;
  if found then
    if prior.actor_id<>auth.uid() or prior.command<>command then raise sqlstate 'PT409' using message='request_conflict'; end if;
    return prior.result;
  end if;
  if jsonb_typeof(p_payload)<>'object' or p_payload is null
    or char_length(trim(coalesce(p_payload->>'title',''))) not between 1 and 200
    or octet_length(p_payload::text)>30000
    or jsonb_typeof(p_payload->'contributor_ids') is distinct from 'array'
    or jsonb_array_length(p_payload->'contributor_ids')>50
    or jsonb_typeof(p_payload->'tags') is distinct from 'array'
    or jsonb_typeof(p_payload->'capital_forms') is distinct from 'array' then
    raise sqlstate 'PT400' using message='invalid_contribution'; end if;
  if p_id is null then
    insert into public.contributions(title,publication_state) values(trim(p_payload->>'title'),'published') returning id,revision into cid,rev;
  else
    select id,revision into cid,rev from public.contributions where id=p_id for update;
    if not found then raise sqlstate 'PT404' using message='content_not_found'; end if;
    if p_revision is null or rev<>p_revision then raise sqlstate 'PT409' using message='revision_conflict'; end if;
    rev:=rev+1;
  end if;
  update public.contributions set title=trim(p_payload->>'title'),description=coalesce(p_payload->>'description',''),
    contribution_type=nullif(p_payload->>'contribution_type',''),stage=nullif(p_payload->>'stage',''),
    capital_forms=array(select jsonb_array_elements_text(p_payload->'capital_forms')),
    tier=nullif(p_payload->>'tier',''),terms=coalesce(p_payload->>'terms',''),license=nullif(p_payload->>'license',''),
    tags=array(select jsonb_array_elements_text(p_payload->'tags')),revision=rev,updated_at=now() where id=cid;
  delete from public.contribution_members where contribution_id=cid;
  for mid in select distinct v::uuid from jsonb_array_elements_text(p_payload->'contributor_ids') t(v) loop
    if not exists(select 1 from public.members where id=mid) then raise sqlstate 'PT400' using message='invalid_contributor'; end if;
    insert into public.contribution_members values(cid,mid);
  end loop;
  insert into public.content_events(contribution_id,actor_id,actor_label,action,revision)
    values(cid,auth.uid(),(select email from auth.users where id=auth.uid()),case when p_id is null then 'created' else 'updated' end,rev);
  answer:=jsonb_build_object('id',cid,'revision',rev);
  insert into private.content_requests values(p_request_id,auth.uid(),command,answer);
  return answer;
end $$;
create function public.save_contribution(p_id uuid,p_revision integer,p_payload jsonb,p_request_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
  select private.save_contribution(p_id,p_revision,p_payload,p_request_id);
$$;
revoke all on function private.moderate_content(text,uuid,integer,text,text),public.moderate_content(text,uuid,integer,text,text),
  private.save_contribution(uuid,integer,jsonb,uuid),public.save_contribution(uuid,integer,jsonb,uuid) from public,anon,authenticated;
grant execute on function private.moderate_content(text,uuid,integer,text,text),public.moderate_content(text,uuid,integer,text,text),
  private.save_contribution(uuid,integer,jsonb,uuid),public.save_contribution(uuid,integer,jsonb,uuid) to authenticated;

-- This credential permits only bounded anonymous intake, never steward operations.
create table private.intake_settings (singleton boolean primary key default true check(singleton), secret_sha256 text not null);
create table private.intake_requests (request_id uuid primary key,kind text not null,payload jsonb not null,target_id uuid not null,created_at timestamptz not null default now());
create table private.intake_limits (kind text not null,actor_hash text not null,window_start timestamptz not null,total integer not null,primary key(kind,actor_hash,window_start));
create table private.notification_jobs (
  id uuid primary key default gen_random_uuid(),application_id uuid not null references public.applications(id),
  channel text not null check(channel in ('receipt','steward','telegram')),status text not null default 'pending',
  attempts integer not null default 0,lease_id uuid,updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),unique(application_id,channel)
);
create table private.import_records (
  source_id text primary key,collection text not null,checksum text not null,payload jsonb not null,
  target_id uuid,imported_at timestamptz not null default now()
);
do $$ declare t text; begin
  foreach t in array array['intake_settings','intake_requests','intake_limits','notification_jobs','import_records'] loop
    execute format('alter table private.%I enable row level security',t);
    execute format('revoke all on private.%I from public,anon,authenticated',t);
  end loop;
end $$;
create function private.submit_intake(p_secret text,p_kind text,p_request_id uuid,p_payload jsonb,p_actor_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare prior private.intake_requests; target uuid; quota integer; win timestamptz:=date_trunc('hour',now()); begin
  if p_secret is null or not exists(select 1 from private.intake_settings where secret_sha256=encode(sha256(convert_to(p_secret,'UTF8')),'hex')) then
    raise sqlstate 'PT403' using message='intake_credential_required'; end if;
  if p_kind not in ('seed','application') or p_kind is null or p_request_id is null or jsonb_typeof(p_payload) is distinct from 'object'
    or octet_length(p_payload::text)>32768 or coalesce(char_length(p_actor_hash),0)<>64 then
    raise sqlstate 'PT400' using message='invalid_request'; end if;
  -- Serialize a request identity across different instances before quota or insert.
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
  select * into prior from private.intake_requests where request_id=p_request_id;
  if found then
    if prior.kind<>p_kind or prior.payload<>p_payload then raise sqlstate 'PT409' using message='request_conflict'; end if;
    return jsonb_build_object('ok',true,'id',prior.target_id,'fresh',false);
  end if;
  insert into private.intake_limits values(p_kind,p_actor_hash,win,1)
    on conflict(kind,actor_hash,window_start) do update set total=private.intake_limits.total+1 returning total into quota;
  if quota>(case when p_kind='seed' then 6 else 3 end) then raise sqlstate 'PT429' using message='rate_limited'; end if;
  if p_kind='seed' then
    if jsonb_typeof(p_payload->'text') is distinct from 'string' or private.utf16_length(trim(p_payload->>'text')) not between 3 and 240
      or private.utf16_length(coalesce(p_payload->>'author',''))>80 then raise sqlstate 'PT400' using message='invalid_length'; end if;
    insert into public.seeds(text,author) values(trim(p_payload->>'text'),coalesce(p_payload->>'author','')) returning id into target;
  else
    if char_length(trim(coalesce(p_payload->>'full-name',''))) not between 1 and 200
      or coalesce(p_payload->>'email','')!~'^[^\s@]+@[^\s@]+\.[^\s@]+$'
      or coalesce(p_payload->>'applicant-type','individual') not in ('individual','organization') then
      raise sqlstate 'PT400' using message='invalid_application'; end if;
    insert into public.applications(request_id,display_name,applicant_type,email,original_answers)
      values(p_request_id,trim(p_payload->>'full-name'),coalesce(p_payload->>'applicant-type','individual'),p_payload->>'email',p_payload)
      returning id into target;
    insert into private.notification_jobs(application_id,channel) values(target,'receipt'),(target,'steward'),(target,'telegram');
  end if;
  insert into private.intake_requests values(p_request_id,p_kind,p_payload,target,now());
  delete from private.intake_limits where window_start<now()-interval '2 days';
  return jsonb_build_object('ok',true,'id',target,'fresh',true);
end $$;
create function public.submit_intake(p_secret text,p_kind text,p_request_id uuid,p_payload jsonb,p_actor_hash text)
returns jsonb language sql security invoker set search_path='' as $$
  select private.submit_intake(p_secret,p_kind,p_request_id,p_payload,p_actor_hash);
$$;
grant usage on schema private to anon;
revoke all on function private.submit_intake(text,text,uuid,jsonb,text),public.submit_intake(text,text,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function private.submit_intake(text,text,uuid,jsonb,text),public.submit_intake(text,text,uuid,jsonb,text) to anon;

-- Leases and provider identities survive serverless restarts. Telegram has no
-- receiver deduplication contract, so uncertain deliveries require manual review.
create function private.notification_work(p_secret text,p_application_id uuid,p_job_id uuid,p_lease uuid,p_status text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare jobs jsonb; begin
 if p_secret is null or not exists(select 1 from private.intake_settings where secret_sha256=encode(sha256(convert_to(p_secret,'UTF8')),'hex')) then
  raise sqlstate 'PT403' using message='intake_credential_required'; end if;
 if p_job_id is not null then
  if p_status not in ('sent','failed','skipped','needs_review') or p_status is null then raise sqlstate 'PT400' using message='invalid_status'; end if;
  update private.notification_jobs set status=p_status,updated_at=now() where id=p_job_id and lease_id=p_lease and status='sending';
  if not found then raise sqlstate 'PT409' using message='notification_lease_conflict'; end if;
  return '[]'::jsonb;
 end if;
 update private.notification_jobs set status='needs_review',updated_at=now()
  where status in ('pending','failed','sending') and (created_at<now()-interval '24 hours'
   or (channel='telegram' and status='sending' and updated_at<now()-interval '5 minutes'));
 with candidates as (
  select id from private.notification_jobs where (p_application_id is null or application_id=p_application_id)
   and created_at>now()-interval '24 hours' and attempts<3
   and (status='pending' or (channel<>'telegram' and (status='failed' or (status='sending' and updated_at<now()-interval '5 minutes'))))
  order by created_at,id for update skip locked limit 10
 ), claimed as (
  update private.notification_jobs j set status='sending',attempts=attempts+1,lease_id=gen_random_uuid(),updated_at=now()
   from candidates c where j.id=c.id returning j.*
 ) select coalesce(jsonb_agg(jsonb_build_object('id',j.id,'lease_id',j.lease_id,'application_id',j.application_id,
   'channel',j.channel,'name',a.display_name,'email',a.email,'member_type',a.applicant_type)),'[]'::jsonb)
   into jobs from claimed j join public.applications a on a.id=j.application_id;
 return jobs;
end $$;
create function public.notification_work(p_secret text,p_application_id uuid,p_job_id uuid,p_lease uuid,p_status text)
returns jsonb language sql security invoker set search_path='' as $$
 select private.notification_work(p_secret,p_application_id,p_job_id,p_lease,p_status);
$$;
revoke all on function private.notification_work(text,uuid,uuid,uuid,text),public.notification_work(text,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.notification_work(text,uuid,uuid,uuid,text),public.notification_work(text,uuid,uuid,uuid,text) to anon;
