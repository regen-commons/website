-- Contact messages are private correspondence, separate from membership and feedback.
create table public.contact_messages (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  name text not null check(private.utf16_length(name) between 1 and 200),
  email text not null check(private.utf16_length(email) between 3 and 254),
  subject text not null check(private.utf16_length(subject) between 1 and 200),
  message text not null check(private.utf16_length(message) between 3 and 5000),
  submitted_at timestamptz not null default now(),
  notification_state text not null default 'pending' check(notification_state in ('pending','sending','sent','needs_review')),
  notification_lease uuid,
  notification_updated_at timestamptz not null default now()
);
create index contact_messages_order on public.contact_messages(submitted_at desc,id);
create index contact_messages_pending on public.contact_messages(submitted_at,id) where notification_state='pending';
alter table public.contact_messages enable row level security;
revoke all on public.contact_messages from public,anon,authenticated;
grant select(id,name,email,subject,message,submitted_at,notification_state) on public.contact_messages to authenticated;
create policy steward_read on public.contact_messages for select to authenticated
  using ((select private.is_active_steward()));

-- The existing server-held intake capability is bounded to insert/notification work.
create function private.submit_contact(p_secret text,p_request_id uuid,p_payload jsonb,p_actor_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare prior private.intake_requests; target uuid; quota integer; win timestamptz:=date_trunc('hour',now()); begin
  if p_secret is null or not exists(select 1 from private.intake_settings where secret_sha256=encode(sha256(convert_to(p_secret,'UTF8')),'hex')) then
    raise sqlstate 'PT403' using message='intake_credential_required'; end if;
  if p_request_id is null or jsonb_typeof(p_payload) is distinct from 'object'
    or octet_length(p_payload::text)>32768 or coalesce(char_length(p_actor_hash),0)<>64 then
    raise sqlstate 'PT400' using message='invalid_request'; end if;
  if jsonb_typeof(p_payload->'name') is distinct from 'string'
    or jsonb_typeof(p_payload->'email') is distinct from 'string'
    or jsonb_typeof(p_payload->'subject') is distinct from 'string'
    or jsonb_typeof(p_payload->'message') is distinct from 'string' then
    raise sqlstate 'PT400' using message='invalid_contact'; end if;
  if private.utf16_length(trim(p_payload->>'name')) not between 1 and 200
    or private.utf16_length(trim(p_payload->>'email'))>254
    or trim(p_payload->>'email') !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$'
    or private.utf16_length(trim(p_payload->>'subject')) not between 1 and 200
    or private.utf16_length(trim(p_payload->>'message')) not between 3 and 5000 then
    raise sqlstate 'PT400' using message='invalid_contact'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
  select * into prior from private.intake_requests where request_id=p_request_id;
  if found then
    if prior.kind<>'contact' or prior.payload<>p_payload then raise sqlstate 'PT409' using message='request_conflict'; end if;
    return jsonb_build_object('ok',true,'id',prior.target_id,'fresh',false);
  end if;
  insert into private.intake_limits values('contact',p_actor_hash,win,1)
    on conflict(kind,actor_hash,window_start) do update set total=private.intake_limits.total+1 returning total into quota;
  if quota>3 then raise sqlstate 'PT429' using message='rate_limited'; end if;
  insert into public.contact_messages(request_id,name,email,subject,message)
    values(p_request_id,trim(p_payload->>'name'),lower(trim(p_payload->>'email')),trim(p_payload->>'subject'),trim(p_payload->>'message'))
    returning id into target;
  insert into private.intake_requests values(p_request_id,'contact',p_payload,target,now());
  delete from private.intake_limits where window_start<now()-interval '2 days';
  return jsonb_build_object('ok',true,'id',target,'fresh',true);
end $$;
create function public.submit_contact(p_secret text,p_request_id uuid,p_payload jsonb,p_actor_hash text)
returns jsonb language sql security invoker set search_path='' as $$
 select private.submit_contact(p_secret,p_request_id,p_payload,p_actor_hash);
$$;
revoke all on function private.submit_contact(text,uuid,jsonb,text),public.submit_contact(text,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function private.submit_contact(text,uuid,jsonb,text),public.submit_contact(text,uuid,jsonb,text) to anon;

-- A lease prevents concurrent sends. Uncertain delivery never silently retries.
create function private.claim_contact_notifications(p_secret text,p_message_id uuid)
returns table(id uuid,notification_lease uuid) language plpgsql security definer set search_path='' as $$
begin
  if p_secret is null or not exists(select 1 from private.intake_settings where secret_sha256=encode(sha256(convert_to(p_secret,'UTF8')),'hex')) then
    raise sqlstate 'PT403' using message='intake_credential_required'; end if;
  update public.contact_messages m set notification_state='needs_review',notification_updated_at=now()
    where m.notification_state='sending' and m.notification_updated_at<now()-interval '5 minutes';
  return query with picked as (
    select m.id from public.contact_messages m where m.notification_state='pending'
      and (p_message_id is null or m.id=p_message_id)
      order by m.submitted_at,m.id limit 5 for update skip locked
  ) update public.contact_messages m set notification_state='sending',notification_lease=gen_random_uuid(),notification_updated_at=now()
    from picked where m.id=picked.id returning m.id,m.notification_lease;
end $$;
create function public.claim_contact_notifications(p_secret text,p_message_id uuid default null)
returns table(id uuid,notification_lease uuid) language sql security invoker set search_path='' as $$
 select * from private.claim_contact_notifications(p_secret,p_message_id);
$$;
create function private.finish_contact_notification(p_secret text,p_message_id uuid,p_lease uuid,p_status text)
returns void language plpgsql security definer set search_path='' as $$
begin
  if p_secret is null or not exists(select 1 from private.intake_settings where secret_sha256=encode(sha256(convert_to(p_secret,'UTF8')),'hex')) then
    raise sqlstate 'PT403' using message='intake_credential_required'; end if;
  if p_status is null or p_status not in ('sent','needs_review') then raise sqlstate 'PT400' using message='invalid_notification_status'; end if;
  update public.contact_messages set notification_state=p_status,notification_updated_at=now()
    where id=p_message_id and notification_lease=p_lease and notification_state='sending';
  if not found then raise sqlstate 'PT409' using message='notification_lease_conflict'; end if;
end $$;
create function public.finish_contact_notification(p_secret text,p_message_id uuid,p_lease uuid,p_status text)
returns void language sql security invoker set search_path='' as $$
 select private.finish_contact_notification(p_secret,p_message_id,p_lease,p_status);
$$;
revoke all on function private.claim_contact_notifications(text,uuid),public.claim_contact_notifications(text,uuid),
 private.finish_contact_notification(text,uuid,uuid,text),public.finish_contact_notification(text,uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.claim_contact_notifications(text,uuid),public.claim_contact_notifications(text,uuid),
 private.finish_contact_notification(text,uuid,uuid,text),public.finish_contact_notification(text,uuid,uuid,text) to anon;
