-- Apply through the shared Platform database's migration owner.
create role weave_speech_quota_owner nologin;
create role weave_speech_quota_writer nologin;
create role weave_speech_quota_runtime nologin nosuperuser nocreaterole nocreatedb noreplication nobypassrls;
grant weave_speech_quota_writer to weave_speech_quota_runtime;
grant weave_speech_quota_owner to current_user;
grant usage, create on schema weave to weave_speech_quota_owner;

-- Keep the privileged reservation function outside the Data API schemas.
create schema weave_speech_quota_private authorization weave_speech_quota_owner;
revoke all on schema weave_speech_quota_private from public, anon, authenticated, service_role;
grant usage on schema weave_speech_quota_private to weave_speech_quota_writer;

-- One row serializes reservations across deployments. Connection keys only cover the active
-- ten-minute window, with at most one key per admitted call.
create table weave.speech_quota (
  singleton boolean primary key default true check (singleton),
  day_start timestamptz not null default '-infinity',
  daily_calls integer not null default 0 check (daily_calls >= 0),
  caller_window timestamptz not null default '-infinity',
  callers jsonb not null default '{}'
);
insert into weave.speech_quota default values;
alter table weave.speech_quota enable row level security;
revoke all on weave.speech_quota from public, anon, authenticated, service_role;
alter table weave.speech_quota owner to weave_speech_quota_owner;

create function weave_speech_quota_private.reserve(caller_key text)
returns table (decision text, retry_at timestamptz)
language plpgsql security definer set search_path = '' set lock_timeout = '500ms'
as $$
declare
  quota weave.speech_quota%rowtype;
  checked_at timestamptz;
  today timestamptz;
  caller_bucket timestamptz;
  caller_calls integer;
begin
  if caller_key is null or caller_key !~ '^[a-f0-9]{64}$' then
    raise exception 'invalid speech quota key';
  end if;

  select * into strict quota from weave.speech_quota where singleton for update;
  checked_at := clock_timestamp();
  today := date_trunc('day', checked_at, 'UTC');
  caller_bucket := date_bin('10 minutes', checked_at, timestamptz '2000-01-01 00:00:00+00');

  if quota.day_start <> today then quota.daily_calls := 0; end if;
  if quota.caller_window <> caller_bucket then quota.callers := '{}'::jsonb; end if;
  caller_calls := coalesce((quota.callers ->> caller_key)::integer, 0);

  if quota.daily_calls >= 60 then
    return query select 'daily'::text, today + interval '24 hours';
  elsif caller_calls >= 6 then
    return query select 'caller'::text, caller_bucket + interval '10 minutes';
  else
    update weave.speech_quota
    set day_start = today,
        daily_calls = quota.daily_calls + 1,
        caller_window = caller_bucket,
        callers = quota.callers || jsonb_build_object(caller_key, caller_calls + 1)
    where singleton;
    return query select 'allowed'::text, null::timestamptz;
  end if;
end;
$$;

alter function weave_speech_quota_private.reserve(text) owner to weave_speech_quota_owner;
revoke create on schema weave from weave_speech_quota_owner;
revoke all on function weave_speech_quota_private.reserve(text) from public, anon, authenticated, service_role;
grant execute on function weave_speech_quota_private.reserve(text) to weave_speech_quota_writer;

-- Clear expired keys even when no more recordings arrive. The daily count stays in place.
do $migration$
begin
  -- The migration-owner CI uses a separate test database without a cron scheduler.
  if not exists (
    select from pg_settings where name = 'cron.database_name' and setting = current_database()
  ) then
    return;
  end if;
  create extension if not exists pg_cron;
  perform cron.schedule('weave-speech-quota-retention', '*/10 * * * *', $job$
    update weave.speech_quota set callers = '{}'::jsonb
    where singleton and callers <> '{}'::jsonb and caller_window + interval '10 minutes' <= clock_timestamp();
  $job$);
end
$migration$;
