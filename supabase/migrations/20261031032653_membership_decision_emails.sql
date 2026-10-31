-- Decision mail is a private, immutable snapshot of an explicit review event.
-- No existing applications, review events, receipt jobs or profiles are backfilled.
alter table public.review_events add column applicant_message text;
alter table private.notification_jobs
  drop constraint notification_jobs_channel_check,
  drop constraint notification_jobs_application_id_channel_key,
  drop constraint notification_status,
  add column review_event_id uuid unique references public.review_events(id),
  add column decision_state text,
  add column recipient_name text,
  add column recipient_email text,
  add column applicant_message text,
  add column template_version integer,
  add constraint notification_channel check(channel in ('receipt','steward','telegram','decision')),
  add constraint notification_status check(status in ('pending','sending','sent','failed','skipped','needs_review','superseded')),
  add constraint decision_snapshot check (
    (channel='decision' and review_event_id is not null
      and decision_state is not null and decision_state in ('approved','declined','changes_requested')
      and recipient_name is not null and recipient_email is not null
      and applicant_message is not null and private.utf16_length(applicant_message)<=4000
      and (decision_state<>'changes_requested' or length(trim(applicant_message))>0)
      and template_version is not null and template_version=1)
    or (channel<>'decision' and review_event_id is null and decision_state is null
      and recipient_name is null and recipient_email is null and applicant_message is null and template_version is null)
  );
create unique index notification_intake_identity on private.notification_jobs(application_id,channel) where channel<>'decision';

-- Pending/superseded decisions are never retried after a newer review decision.
-- Profile linking can increment application revision without changing the decision.
create or replace function private.email_retry_block(j private.notification_jobs) returns text
language sql stable security invoker set search_path='' as $$
  select case
    when j.channel not in ('receipt','steward','decision') then 'email_only'
    when j.status='sent' or j.provider_message_id is not null then 'already_sent'
    when j.channel='decision' and (j.status='superseded' or not exists (
      select 1 from public.review_events e join public.applications a on a.id=e.application_id
      where e.id=j.review_event_id and e.to_state=a.review_state and not exists (
        select 1 from public.review_events later where later.application_id=a.id
          and later.event_type in ('approved','declined','changes_requested','reopened')
          and later.resulting_revision>e.resulting_revision
      ))) then 'decision_superseded'
    when j.created_at<=now()-interval '24 hours'+interval '1 minute' then 'retry_window_expired'
    when j.attempts>=3 then 'retry_limit_reached'
    when j.status='sending' and j.updated_at>now()-interval '5 minutes' then 'notification_busy'
    when j.status not in ('pending','failed','skipped','sending') then 'manual_review_required'
    else null end;
$$;

create or replace function private.membership_command(p_request_id uuid,p_command jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  prior private.membership_requests; a public.applications; m public.members;
  payload jsonb; answer jsonb; snapshot jsonb;
  action text:=p_command->>'action'; reason text:=trim(p_command->>'reason');
  target uuid; email_job uuid; review_event uuid; applicant_message text; rev integer; next_state text; event text; actor text;
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
    when action='review-application' then array['action','reason','id','revision','state','applicant_message']
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
      if next_state='pending' then
        if p_command ? 'applicant_message' then raise sqlstate 'PT400' using message='invalid_applicant_message'; end if;
      else
        if jsonb_typeof(p_command->'applicant_message') is distinct from 'string'
          or private.utf16_length(p_command->>'applicant_message')>4000 then
          raise sqlstate 'PT400' using message='invalid_applicant_message'; end if;
        applicant_message:=trim(p_command->>'applicant_message');
        if next_state='changes_requested' and char_length(applicant_message)=0 then
          raise sqlstate 'PT400' using message='invalid_applicant_message'; end if;
      end if;
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
    insert into public.review_events(application_id,actor_id,actor_label,event_type,reviewed_revision,note,from_state,to_state,resulting_revision,changes,applicant_message)
      values(a.id,auth.uid(),actor,event,rev,reason,a.review_state,next_state,rev+1,case when action='link-profile' then jsonb_build_object('before',a.member_id,'after',target) else null end,applicant_message) returning id into review_event;
    if action='review-application' then
      -- Claims lock the application before a job, so a later decision cannot
      -- race an unclaimed message. A send already in flight cannot be recalled.
      update private.notification_jobs set status='superseded',updated_at=now()
        where application_id=a.id and channel='decision'
        and (status in ('pending','failed','skipped') or (status='sending' and updated_at<=now()-interval '5 minutes'));
      if next_state<>'pending' then
        insert into private.notification_jobs(application_id,channel,review_event_id,
          decision_state,recipient_name,recipient_email,applicant_message,template_version)
        values(a.id,'decision',review_event,next_state,a.display_name,a.email,applicant_message,1)
        returning id into email_job;
      end if;
    end if;
    answer:=jsonb_build_object('id',a.id,'revision',rev+1);
    if email_job is not null then answer:=answer||jsonb_build_object('notification_id',email_job); end if;
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

create or replace function private.application_notifications(p_application_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare items jsonb; begin
  if not private.is_active_steward() then raise sqlstate 'PT403' using message='steward_required'; end if;
  if not exists(select 1 from public.applications where id=p_application_id) then raise sqlstate 'PT404' using message='application_not_found'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',j.id,'channel',j.channel,'status',j.status,'attempts',j.attempts,
    'created_at',j.created_at,'updated_at',j.updated_at,'last_attempt_at',j.last_attempt_at,
    'provider_message_id',j.provider_message_id,'failure_code',j.failure_code,
    'review_event_id',j.review_event_id,'decision_state',j.decision_state,
    'decision_revision',e.resulting_revision,'applicant_message',j.applicant_message,'recipient',j.recipient_email,
    'retry_block',private.email_retry_block(j)) order by j.created_at,j.id),'[]'::jsonb)
  into items from private.notification_jobs j left join public.review_events e on e.id=j.review_event_id
  where j.application_id=p_application_id and j.channel in ('receipt','steward','decision');
  return items;
end $$;

create or replace function private.retry_notification(p_application_id uuid,p_job_id uuid,p_attempts integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare j private.notification_jobs; blocked text; a public.applications; begin
  if not private.is_active_steward() then raise sqlstate 'PT403' using message='steward_required'; end if;
  perform 1 from public.applications where id=p_application_id for update;
  select * into j from private.notification_jobs where id=p_job_id and application_id=p_application_id
    and channel in ('receipt','steward','decision') for update;
  if not found then raise sqlstate 'PT404' using message='notification_not_found'; end if;
  if p_attempts is null or p_attempts<>j.attempts then
    raise sqlstate 'PT409' using message='notification_changed'; end if;
  blocked:=private.email_retry_block(j);
  if blocked is not null then raise sqlstate 'PT409' using message=blocked; end if;
  update private.notification_jobs set status='sending',attempts=attempts+1,lease_id=gen_random_uuid(),
    updated_at=now(),last_attempt_at=now(),retry_actor_id=auth.uid(),retry_requested_at=now()
    where id=j.id returning * into j;
  select * into a from public.applications where id=j.application_id;
  return jsonb_build_object('id',j.id,'lease_id',j.lease_id,'application_id',j.application_id,
    'channel',j.channel,'name',coalesce(j.recipient_name,a.display_name),
    'email',coalesce(j.recipient_email,a.email),'member_type',a.applicant_type,
    'state',j.decision_state,'message',j.applicant_message,'version',j.template_version);
end $$;

-- Intake draining cannot dispatch decision mail; active stewards claim it explicitly.
create or replace function private.notification_work(p_secret text,p_application_id uuid,p_job_id uuid,p_lease uuid,p_status text)
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
  where (status in ('pending','failed') and created_at<now()-interval '24 hours')
   or (status='sending' and updated_at<now()-interval '5 minutes'
     and (created_at<now()-interval '24 hours' or channel='telegram'));
 with candidates as (
  select j.id from private.notification_jobs j where (p_application_id is null or j.application_id=p_application_id)
   and j.created_at>now()-interval '24 hours' and j.attempts<3
   and ((j.channel='telegram' and j.status='pending')
     or (j.channel in ('receipt','steward') and j.status in ('pending','failed','sending') and private.email_retry_block(j) is null))
  order by j.created_at,j.id for update skip locked limit 10
 ), claimed as (
  update private.notification_jobs j set status='sending',attempts=attempts+1,lease_id=gen_random_uuid(),updated_at=now(),last_attempt_at=now()
   from candidates c where j.id=c.id returning j.*
 ) select coalesce(jsonb_agg(jsonb_build_object('id',j.id,'lease_id',j.lease_id,'application_id',j.application_id,
   'channel',j.channel,'name',a.display_name,'email',a.email,'member_type',a.applicant_type)),'[]'::jsonb)
   into jobs from claimed j join public.applications a on a.id=j.application_id;
 return jobs;
end $$;

-- Replacements retain earlier grants. Private snapshots remain inaccessible directly.
revoke all on function private.email_retry_block(private.notification_jobs) from public,anon,authenticated;
comment on column public.review_events.applicant_message is 'Explicit applicant-facing text. Separate from the private review reason; never inferred from original answers.';
