-- Replace the website's public Notion feedback form with private Supabase intake.
create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  message text not null check(private.utf16_length(message) between 3 and 5000),
  categories text[] not null default '{}',
  page_path text not null,
  submitted_at timestamptz not null default now()
);
alter table public.feedback enable row level security;
revoke all on public.feedback from public,anon,authenticated;
grant select on public.feedback to authenticated;
create policy steward_read on public.feedback for select to authenticated
  using ((select private.is_active_steward()));

-- Retain the existing credential, quota, idempotency and notification behavior.
create or replace function private.submit_intake(p_secret text,p_kind text,p_request_id uuid,p_payload jsonb,p_actor_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare prior private.intake_requests; target uuid; quota integer; win timestamptz:=date_trunc('hour',now()); begin
  if p_secret is null or not exists(select 1 from private.intake_settings where secret_sha256=encode(sha256(convert_to(p_secret,'UTF8')),'hex')) then
    raise sqlstate 'PT403' using message='intake_credential_required'; end if;
  if p_kind not in ('seed','application','feedback') or p_kind is null or p_request_id is null or jsonb_typeof(p_payload) is distinct from 'object'
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
  elsif p_kind='feedback' then
    if jsonb_typeof(p_payload->'message') is distinct from 'string'
      or jsonb_typeof(p_payload->'categories') is distinct from 'array'
      or jsonb_typeof(p_payload->'page_path') is distinct from 'string' then
      raise sqlstate 'PT400' using message='invalid_feedback'; end if;
    if private.utf16_length(trim(p_payload->>'message')) not between 3 and 5000
      or jsonb_array_length(p_payload->'categories')>7
      or char_length(p_payload->>'page_path') not between 1 and 500
      or left(p_payload->>'page_path',1)<>'/' or left(p_payload->>'page_path',2)='//'
      or p_payload->>'page_path' ~ '\s' or position('?' in p_payload->>'page_path')>0
      or position('#' in p_payload->>'page_path')>0 or position(chr(92) in p_payload->>'page_path')>0
      or exists(select 1 from jsonb_array_elements(p_payload->'categories') item
        where jsonb_typeof(item) is distinct from 'string' or item#>>'{}' not in
          ('Bug','Idea','Technical suggestion','Feature request','Security consideration','Other','Fine Tuning')) then
      raise sqlstate 'PT400' using message='invalid_feedback'; end if;
    insert into public.feedback(request_id,message,categories,page_path)
      values(p_request_id,trim(p_payload->>'message'),array(select distinct jsonb_array_elements_text(p_payload->'categories')),p_payload->>'page_path')
      returning id into target;
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
