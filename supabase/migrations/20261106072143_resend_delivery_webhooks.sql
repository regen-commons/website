-- A message can receive a webhook before the outbox saves its Resend ID.
-- Keep one latest outcome per ID, with no raw payload or recipient data.
create table private.email_delivery_outcomes (
  provider_message_id uuid primary key,
  outcome text not null check (outcome in ('delivered','bounced')),
  occurred_at timestamptz not null check (isfinite(occurred_at))
);
alter table private.email_delivery_outcomes enable row level security;
revoke all on private.email_delivery_outcomes from public,anon,authenticated;

create function private.record_email_delivery(
  p_secret text,p_provider_message_id uuid,p_outcome text,p_occurred_at timestamptz
) returns void language plpgsql security definer set search_path='' as $$
begin
  if p_secret is null or not exists(select 1 from private.intake_settings
    where secret_sha256=encode(sha256(convert_to(p_secret,'UTF8')),'hex')) then
    raise sqlstate 'PT403' using message='intake_credential_required';
  end if;
  insert into private.email_delivery_outcomes as current_outcome
    (provider_message_id,outcome,occurred_at)
    values(p_provider_message_id,p_outcome,p_occurred_at)
  on conflict (provider_message_id) do update
    set outcome=excluded.outcome,occurred_at=excluded.occurred_at
    where excluded.occurred_at>current_outcome.occurred_at
      or (excluded.occurred_at=current_outcome.occurred_at
        and excluded.outcome='bounced' and current_outcome.outcome='delivered');
end $$;

create function public.record_email_delivery(
  p_secret text,p_provider_message_id uuid,p_outcome text,p_occurred_at timestamptz
) returns void language sql security invoker set search_path='' as $$
  select private.record_email_delivery(p_secret,p_provider_message_id,p_outcome,p_occurred_at);
$$;
revoke all on function private.record_email_delivery(text,uuid,text,timestamptz),
  public.record_email_delivery(text,uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function private.record_email_delivery(text,uuid,text,timestamptz),
  public.record_email_delivery(text,uuid,text,timestamptz) to anon;

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
    'delivery_outcome',d.outcome,'delivery_occurred_at',d.occurred_at,
    'retry_block',private.email_retry_block(j)) order by j.created_at,j.id),'[]'::jsonb)
  into items from private.notification_jobs j left join public.review_events e on e.id=j.review_event_id
  left join private.email_delivery_outcomes d
    on j.channel in ('receipt','decision') and d.provider_message_id=j.provider_message_id
  where j.application_id=p_application_id and j.channel in ('receipt','steward','decision');
  return items;
end $$;
