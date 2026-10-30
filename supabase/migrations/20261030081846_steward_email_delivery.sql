-- Email acceptance diagnostics. No provider payloads or credentials are retained.
alter table private.notification_jobs
  add column provider_message_id uuid,
  add column last_attempt_at timestamptz,
  add column failure_code text check (failure_code in (
    'resend_not_configured','recipients_not_configured','resend_authentication_failed',
    'resend_rate_limited','resend_idempotency_conflict','resend_invalid_request',
    'resend_unavailable','resend_rejected','resend_invalid_response',
    'notification_timeout','notification_connection_failed',
    'notification_not_configured','notification_rejected')),
  add column retry_actor_id uuid references auth.users(id),
  add column retry_requested_at timestamptz,
  add constraint notification_status check (status in ('pending','sending','sent','failed','skipped','needs_review')),
  add constraint notification_attempts check (attempts between 0 and 3);
create index notification_retry_actor on private.notification_jobs(retry_actor_id);

-- One rule for the steward's eligibility display and the locked retry command.
-- Stay inside Resend's 24-hour idempotency window; never reset the original clock.
create function private.email_retry_block(j private.notification_jobs) returns text
language sql stable security invoker set search_path='' as $$
  select case
    when j.channel not in ('receipt','steward') then 'email_only'
    when j.status='sent' or j.provider_message_id is not null then 'already_sent'
    when j.created_at<=now()-interval '24 hours' then 'retry_window_expired'
    when j.attempts>=3 then 'retry_limit_reached'
    when j.status='sending' and j.updated_at>now()-interval '5 minutes' then 'notification_busy'
    when j.status not in ('pending','failed','skipped','sending') then 'manual_review_required'
    else null end;
$$;
revoke all on function private.email_retry_block(private.notification_jobs) from public,anon,authenticated;

-- Shared completion guard for the intake worker and a session-scoped retry.
create function private.finish_notification(p_job_id uuid,p_lease uuid,p_status text,p_provider_message_id uuid,p_failure_code text)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
  if p_status is null or p_status not in ('sent','failed','skipped','needs_review')
    or (p_provider_message_id is not null and p_status<>'sent')
    or (p_failure_code is not null and p_status='sent') then
    raise sqlstate 'PT400' using message='invalid_notification_result';
  end if;
  update private.notification_jobs set status=p_status,provider_message_id=p_provider_message_id,
    failure_code=p_failure_code,updated_at=now()
    where id=p_job_id and lease_id=p_lease and status='sending';
  if not found then raise sqlstate 'PT409' using message='notification_lease_conflict'; end if;
  return '[]'::jsonb;
end $$;
revoke all on function private.finish_notification(uuid,uuid,text,uuid,text) from public,anon,authenticated;

create function private.notification_result(p_secret text,p_job_id uuid,p_lease uuid,p_status text,p_provider_message_id uuid,p_failure_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if p_secret is null or not exists(select 1 from private.intake_settings
    where secret_sha256=encode(sha256(convert_to(p_secret,'UTF8')),'hex')) then
    raise sqlstate 'PT403' using message='intake_credential_required';
  end if;
  return private.finish_notification(p_job_id,p_lease,p_status,p_provider_message_id,p_failure_code);
end $$;
create function public.notification_result(p_secret text,p_job_id uuid,p_lease uuid,p_status text,p_provider_message_id uuid,p_failure_code text)
returns jsonb language sql security invoker set search_path='' as $$
  select private.notification_result(p_secret,p_job_id,p_lease,p_status,p_provider_message_id,p_failure_code);
$$;
revoke all on function private.notification_result(text,uuid,uuid,text,uuid,text),public.notification_result(text,uuid,uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function private.notification_result(text,uuid,uuid,text,uuid,text),public.notification_result(text,uuid,uuid,text,uuid,text) to anon;

-- Private tables stay closed. Only active stewards with a live Auth session can
-- read the allowlisted diagnostics; imported applications have an empty ledger.
create function private.application_notifications(p_application_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare items jsonb; begin
  if not private.is_active_steward() then raise sqlstate 'PT403' using message='steward_required'; end if;
  if not exists(select 1 from public.applications where id=p_application_id) then
    raise sqlstate 'PT404' using message='application_not_found'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',j.id,'channel',j.channel,'status',j.status,'attempts',j.attempts,
    'created_at',j.created_at,'updated_at',j.updated_at,'last_attempt_at',j.last_attempt_at,
    'provider_message_id',j.provider_message_id,'failure_code',j.failure_code,
    'retry_block',private.email_retry_block(j)) order by j.channel),'[]'::jsonb)
    into items from private.notification_jobs j
    where j.application_id=p_application_id and j.channel in ('receipt','steward');
  return items;
end $$;
create function public.application_notifications(p_application_id uuid) returns jsonb
language sql security invoker set search_path='' as $$ select private.application_notifications(p_application_id); $$;

create function private.retry_notification(p_application_id uuid,p_job_id uuid,p_attempts integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare j private.notification_jobs; blocked text; a public.applications; begin
  if not private.is_active_steward() then raise sqlstate 'PT403' using message='steward_required'; end if;
  select * into j from private.notification_jobs where id=p_job_id and application_id=p_application_id
    and channel in ('receipt','steward') for update;
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
    'channel',j.channel,'name',a.display_name,'email',a.email,'member_type',a.applicant_type);
end $$;
create function public.retry_notification(p_application_id uuid,p_job_id uuid,p_attempts integer) returns jsonb
language sql security invoker set search_path='' as $$ select private.retry_notification(p_application_id,p_job_id,p_attempts); $$;

create function private.complete_notification_retry(p_job_id uuid,p_lease uuid,p_status text,p_provider_message_id uuid,p_failure_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if not private.is_active_steward() then raise sqlstate 'PT403' using message='steward_required'; end if;
  if not exists(select 1 from private.notification_jobs where id=p_job_id and retry_actor_id=auth.uid()
    and lease_id=p_lease and channel in ('receipt','steward')) then
    raise sqlstate 'PT409' using message='notification_lease_conflict'; end if;
  return private.finish_notification(p_job_id,p_lease,p_status,p_provider_message_id,p_failure_code);
end $$;
create function public.complete_notification_retry(p_job_id uuid,p_lease uuid,p_status text,p_provider_message_id uuid,p_failure_code text)
returns jsonb language sql security invoker set search_path='' as $$
  select private.complete_notification_retry(p_job_id,p_lease,p_status,p_provider_message_id,p_failure_code);
$$;
revoke all on function private.application_notifications(uuid),public.application_notifications(uuid),
  private.retry_notification(uuid,uuid,integer),public.retry_notification(uuid,uuid,integer),
  private.complete_notification_retry(uuid,uuid,text,uuid,text),public.complete_notification_retry(uuid,uuid,text,uuid,text)
  from public,anon,authenticated;
grant execute on function private.application_notifications(uuid),public.application_notifications(uuid),
  private.retry_notification(uuid,uuid,integer),public.retry_notification(uuid,uuid,integer),
  private.complete_notification_retry(uuid,uuid,text,uuid,text),public.complete_notification_retry(uuid,uuid,text,uuid,text)
  to authenticated;

-- Preserve the existing worker API during rollout; record new attempt times
-- without fabricating timestamps for older attempts.
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
  where status in ('pending','failed','sending') and (created_at<now()-interval '24 hours'
   or (channel='telegram' and status='sending' and updated_at<now()-interval '5 minutes'));
 with candidates as (
  select id from private.notification_jobs where (p_application_id is null or application_id=p_application_id)
   and created_at>now()-interval '24 hours' and attempts<3
   and (status='pending' or (channel<>'telegram' and (status='failed' or (status='sending' and updated_at<now()-interval '5 minutes'))))
  order by created_at,id for update skip locked limit 10
 ), claimed as (
  update private.notification_jobs j set status='sending',attempts=attempts+1,lease_id=gen_random_uuid(),updated_at=now(),last_attempt_at=now()
   from candidates c where j.id=c.id returning j.*
 ) select coalesce(jsonb_agg(jsonb_build_object('id',j.id,'lease_id',j.lease_id,'application_id',j.application_id,
   'channel',j.channel,'name',a.display_name,'email',a.email,'member_type',a.applicant_type)),'[]'::jsonb)
   into jobs from claimed j join public.applications a on a.id=j.application_id;
 return jobs;
end $$;
