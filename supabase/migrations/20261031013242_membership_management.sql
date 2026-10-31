-- Review, membership standing and profile visibility are independent commands.
-- Existing visibility and source evidence are preserved; no historic approval is inferred.
alter table public.members
  add column membership_status text not null default 'unconfirmed'
    check (membership_status in ('unconfirmed','active','paused','ended')),
  add column revision integer not null default 1 check (revision > 0),
  add column updated_at timestamptz not null default now();
alter table public.review_events
  add column actor_label text,
  add column changes jsonb,
  add column from_state text,
  add column to_state text,
  add column resulting_revision integer check (resulting_revision > 0);
create table public.member_events (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id),
  actor_id uuid not null references auth.users(id),
  actor_label text not null,
  event_type text not null check (event_type in ('profile_created','profile_updated','membership_changed','visibility_changed')),
  revision integer not null check (revision > 0),
  reason text not null,
  changes jsonb not null,
  created_at timestamptz not null default now()
);
create index member_events_member on public.member_events(member_id,created_at,id);
create index member_events_actor on public.member_events(actor_id);
alter table public.member_events enable row level security;
revoke all on public.member_events from public,anon,authenticated;
grant select on public.member_events to authenticated;
create policy steward_read on public.member_events for select to authenticated
  using ((select private.is_active_steward()));
create table private.membership_requests (
  request_id uuid primary key,
  actor_id uuid not null references auth.users(id),
  command jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now()
);
create index membership_requests_actor on private.membership_requests(actor_id);
alter table private.membership_requests enable row level security;
revoke all on private.membership_requests from public,anon,authenticated;

create function private.membership_command(p_request_id uuid,p_command jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  prior private.membership_requests; a public.applications; m public.members;
  payload jsonb; answer jsonb; snapshot jsonb;
  action text:=p_command->>'action'; reason text:=trim(p_command->>'reason');
  target uuid; rev integer; next_state text; event text; actor text;
  key text; max_length integer; allowed text[]; orgs uuid[]; org uuid;
begin
  if not private.is_active_steward() then raise sqlstate 'PT403' using message='steward_required'; end if;
  if p_request_id is null or jsonb_typeof(p_command) is distinct from 'object'
    or octet_length(p_command::text)>32768
    or jsonb_typeof(p_command->'action') is distinct from 'string'
    or jsonb_typeof(p_command->'reason') is distinct from 'string'
    or reason is null or char_length(reason)<1 or private.utf16_length(p_command->>'reason')>1000
    or action is null or action not in ('review-application','save-profile','link-profile','set-membership-status','set-profile-visibility')
  then raise sqlstate 'PT400' using message='invalid_membership_command'; end if;
  allowed:=case when action='save-profile' then array['action','reason','id','revision','application_id','application_revision','payload']
    when action='link-profile' then array['action','reason','id','revision','member_id']
    else array['action','reason','id','revision','state'] end;
  if exists(select 1 from jsonb_object_keys(p_command) k where not k=any(allowed)) then
    raise sqlstate 'PT400' using message='invalid_membership_command'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,2));
  select * into prior from private.membership_requests where request_id=p_request_id;
  if found then
    if prior.actor_id<>auth.uid() or prior.command<>p_command then raise sqlstate 'PT409' using message='request_conflict'; end if;
    return prior.result;
  end if;
  actor:=(select email from auth.users where id=auth.uid());
  if action<>'save-profile' or p_command ? 'id' then
    target:=(p_command->>'id')::uuid;
    rev:=(p_command->>'revision')::integer;
    if target is null or jsonb_typeof(p_command->'revision') is distinct from 'number' or rev is null or rev<1 or rev>=2147483647 then
      raise sqlstate 'PT400' using message='invalid_membership_command'; end if;
  end if;
  if action in ('review-application','link-profile') then
    select * into a from public.applications where id=target for update;
    if not found then raise sqlstate 'PT404' using message='application_not_found'; end if;
    if a.revision<>rev then raise sqlstate 'PT409' using message='revision_conflict'; end if;
    if action='review-application' then
      next_state:=p_command->>'state';
      if jsonb_typeof(p_command->'state') is distinct from 'string' or next_state is null or not (
        (a.review_state in ('pending','legacy_active') and next_state in ('approved','declined','changes_requested'))
        or (a.review_state='changes_requested' and next_state in ('approved','declined','pending'))
        or (a.review_state in ('approved','declined','legacy_active') and next_state='pending')
      ) then raise sqlstate 'PT409' using message='invalid_review_transition'; end if;
      update public.applications set review_state=next_state,revision=rev+1 where id=a.id;
      event:=case when next_state='pending' then 'reopened' else next_state end;
    else
      if not (p_command ? 'member_id') then raise sqlstate 'PT400' using message='invalid_membership_command'; end if;
      target:=(p_command->>'member_id')::uuid;
      if target is not null then
        select * into m from public.members where id=target;
        if not found or m.member_type<>a.applicant_type then raise sqlstate 'PT400' using message='profile_type_mismatch'; end if;
      end if;
      update public.applications set member_id=target,revision=rev+1 where id=a.id;
      next_state:=a.review_state; event:='profile_linked';
    end if;
    insert into public.review_events(application_id,actor_id,actor_label,event_type,reviewed_revision,note,from_state,to_state,resulting_revision,changes)
      values(a.id,auth.uid(),actor,event,rev,reason,a.review_state,next_state,rev+1,case when action='link-profile' then jsonb_build_object('before',a.member_id,'after',target) else null end);
    answer:=jsonb_build_object('id',a.id,'revision',rev+1);
  elsif action='save-profile' then
    payload:=p_command->'payload';
    if jsonb_typeof(payload) is distinct from 'object' then raise sqlstate 'PT400' using message='invalid_profile'; end if;
    if exists(select 1 from jsonb_object_keys(payload) k where k not in
      ('name','member_type','location','summary','vision','website','avatar','focus_areas','contribution_areas','organization_ids'))
    then raise sqlstate 'PT400' using message='invalid_profile'; end if;
    for key,max_length in select * from (values ('name',200),('member_type',20),('location',300),('summary',2000),('vision',5000),('website',2048),('avatar',2048)) v loop
      if jsonb_typeof(payload->key) is distinct from 'string' or private.utf16_length(payload->>key)>max_length then
        raise sqlstate 'PT400' using message='invalid_profile'; end if;
    end loop;
    if char_length(trim(payload->>'name'))<1 or payload->>'member_type' not in ('individual','organization')
      or ((payload->>'website')<>'' and (payload->>'website')!~* '^https?://[^[:space:]]+$')
      or ((payload->>'avatar')<>'' and (payload->>'avatar')!~* '^https?://[^[:space:]]+$')
    then raise sqlstate 'PT400' using message='invalid_profile'; end if;
    foreach key in array array['focus_areas','contribution_areas','organization_ids'] loop
      if jsonb_typeof(payload->key) is distinct from 'array' then raise sqlstate 'PT400' using message='invalid_profile'; end if;
      if jsonb_array_length(payload->key)>20 then raise sqlstate 'PT400' using message='invalid_profile'; end if;
      if exists(select 1 from jsonb_array_elements(payload->key) v where jsonb_typeof(v)<>'string' or char_length(trim(v#>>'{}'))<1
        or (key<>'organization_ids' and private.utf16_length(v#>>'{}')>80))
      then raise sqlstate 'PT400' using message='invalid_profile'; end if;
    end loop;
    orgs:=array(select distinct v::uuid from jsonb_array_elements_text(payload->'organization_ids') t(v) order by 1);
    if (payload->>'member_type'='organization' and cardinality(orgs)>0)
      or exists(select 1 from unnest(orgs) o where not exists(select 1 from public.members x where x.id=o and x.member_type='organization'))
    then raise sqlstate 'PT400' using message='invalid_affiliation'; end if;
    if p_command ? 'application_id' then
      if p_command ? 'id' then raise sqlstate 'PT400' using message='invalid_membership_command'; end if;
      select * into a from public.applications where id=(p_command->>'application_id')::uuid for update;
      if not found then raise sqlstate 'PT404' using message='application_not_found'; end if;
      if jsonb_typeof(p_command->'application_revision') is distinct from 'number' then raise sqlstate 'PT400' using message='invalid_membership_command'; end if;
      if a.revision<>(p_command->>'application_revision')::integer or a.member_id is not null then
        raise sqlstate 'PT409' using message='revision_conflict'; end if;
      if a.applicant_type<>payload->>'member_type' then raise sqlstate 'PT400' using message='profile_type_mismatch'; end if;
    elsif p_command ? 'application_revision' then raise sqlstate 'PT400' using message='invalid_membership_command';
    end if;
    if p_command ? 'id' then
      select * into m from public.members where id=target for update;
      if not found then raise sqlstate 'PT404' using message='member_not_found'; end if;
      if m.revision<>rev then raise sqlstate 'PT409' using message='revision_conflict'; end if;
      if m.member_type<>payload->>'member_type' then raise sqlstate 'PT400' using message='profile_type_immutable'; end if;
      snapshot:=jsonb_build_object('profile',to_jsonb(m),'organization_ids',(select coalesce(jsonb_agg(organization_id order by organization_id),'[]'::jsonb) from public.affiliations where member_id=m.id));
      event:='profile_updated'; rev:=rev+1;
    else
      if p_command ? 'revision' then raise sqlstate 'PT400' using message='invalid_membership_command'; end if;
      insert into public.members(name,member_type) values(trim(payload->>'name'),payload->>'member_type') returning * into m;
      snapshot:='null'::jsonb; event:='profile_created'; rev:=1;
    end if;
    update public.members set name=trim(payload->>'name'),location=payload->>'location',summary=payload->>'summary',
      vision=payload->>'vision',website=nullif(payload->>'website',''),avatar=nullif(payload->>'avatar',''),
      focus_areas=array(select jsonb_array_elements_text(payload->'focus_areas')),
      contribution_areas=array(select jsonb_array_elements_text(payload->'contribution_areas')),
      revision=rev,updated_at=now() where id=m.id returning * into m;
    delete from public.affiliations where member_id=m.id;
    foreach org in array orgs loop insert into public.affiliations values(m.id,org); end loop;
    insert into public.member_events(member_id,actor_id,actor_label,event_type,revision,reason,changes)
      values(m.id,auth.uid(),actor,event,rev,reason,jsonb_build_object('before',snapshot,'after',jsonb_build_object('profile',to_jsonb(m),'organization_ids',to_jsonb(orgs))));
    if a.id is not null then
      update public.applications set member_id=m.id,revision=revision+1 where id=a.id;
      insert into public.review_events(application_id,actor_id,actor_label,event_type,reviewed_revision,note,from_state,to_state,resulting_revision,changes)
        values(a.id,auth.uid(),actor,'profile_linked',a.revision,reason,a.review_state,a.review_state,a.revision+1,jsonb_build_object('before',a.member_id,'after',m.id));
    end if;
    answer:=jsonb_build_object('id',m.id,'revision',rev);
  else
    select * into m from public.members where id=target for update;
    if not found then raise sqlstate 'PT404' using message='member_not_found'; end if;
    if m.revision<>rev then raise sqlstate 'PT409' using message='revision_conflict'; end if;
    next_state:=p_command->>'state';
    if jsonb_typeof(p_command->'state') is distinct from 'string' or next_state is null then raise sqlstate 'PT400' using message='invalid_membership_command'; end if;
    if action='set-membership-status' then
      if next_state not in ('unconfirmed','active','paused','ended') then raise sqlstate 'PT400' using message='invalid_membership_command'; end if;
      snapshot:=to_jsonb(m.membership_status); event:='membership_changed';
      update public.members set membership_status=next_state,revision=rev+1,updated_at=now() where id=m.id;
    else
      if next_state not in ('draft','published','hidden') then raise sqlstate 'PT400' using message='invalid_membership_command'; end if;
      snapshot:=to_jsonb(m.publication_state); event:='visibility_changed';
      update public.members set publication_state=next_state,revision=rev+1,updated_at=now() where id=m.id;
    end if;
    insert into public.member_events(member_id,actor_id,actor_label,event_type,revision,reason,changes)
      values(m.id,auth.uid(),actor,event,rev+1,reason,jsonb_build_object('before',snapshot,'after',next_state));
    answer:=jsonb_build_object('id',m.id,'revision',rev+1);
  end if;
  insert into private.membership_requests(request_id,actor_id,command,result) values(p_request_id,auth.uid(),p_command,answer);
  return answer;
exception when invalid_text_representation or numeric_value_out_of_range then
  raise sqlstate 'PT400' using message='invalid_membership_command';
end $$;
create function public.membership_command(p_request_id uuid,p_command jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select private.membership_command(p_request_id,p_command); $$;
revoke all on function private.membership_command(uuid,jsonb),public.membership_command(uuid,jsonb) from public,anon,authenticated;
grant execute on function private.membership_command(uuid,jsonb),public.membership_command(uuid,jsonb) to authenticated;
-- No public grants on standing, revision, history or private request records.
-- Website projections and visibility rules are unchanged.
