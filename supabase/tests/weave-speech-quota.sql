-- Run against disposable Postgres. All counter mutations roll back.
begin;

do $test$
begin
  if has_function_privilege('anon', 'weave_speech_quota_private.reserve(text)', 'execute')
     or has_function_privilege('authenticated', 'weave_speech_quota_private.reserve(text)', 'execute')
     or has_function_privilege('service_role', 'weave_speech_quota_private.reserve(text)', 'execute') then
    raise exception 'Data API roles must not be able to reserve speech quota';
  end if;
  if not has_function_privilege('weave_speech_quota_runtime', 'weave_speech_quota_private.reserve(text)', 'execute')
     or has_table_privilege('weave_speech_quota_runtime', 'weave.speech_quota', 'select,insert,update,delete')
     or (select rolcanlogin from pg_roles where rolname = 'weave_speech_quota_runtime') then
    raise exception 'The runtime role must have only the reservation grant and start with login disabled';
  end if;
end
$test$;

set local role weave_speech_quota_runtime;
set local time zone 'Pacific/Auckland';

do $test$
declare
  result record;
begin
  for n in 1..6 loop
    select * into strict result from weave_speech_quota_private.reserve(repeat('a', 64));
    if result.decision <> 'allowed' or result.retry_at is not null then
      raise exception 'Expected connection reservation % to succeed', n;
    end if;
  end loop;
  select * into strict result from weave_speech_quota_private.reserve(repeat('a', 64));
  if result.decision <> 'caller' or result.retry_at <= clock_timestamp()
     or result.retry_at > clock_timestamp() + interval '10 minutes' then
    raise exception 'Expected the next connection window';
  end if;

  for n in 1..54 loop
    select * into strict result from weave_speech_quota_private.reserve(lpad(to_hex(n), 64, '0'));
    if result.decision <> 'allowed' then
      raise exception 'Expected shared reservation % to succeed', n;
    end if;
  end loop;
  select * into strict result from weave_speech_quota_private.reserve(repeat('b', 64));
  if result.decision <> 'daily'
     or result.retry_at <> date_trunc('day', clock_timestamp(), 'UTC') + interval '24 hours' then
    raise exception 'Expected the shared quota to reset at UTC midnight';
  end if;
end
$test$;

reset role;
update weave.speech_quota
set day_start = day_start - interval '24 hours', caller_window = caller_window - interval '10 minutes'
where singleton;

set local role weave_speech_quota_runtime;
do $test$
begin
  if (select decision from weave_speech_quota_private.reserve(repeat('a', 64))) <> 'allowed' then
    raise exception 'A new UTC day must reopen both quotas';
  end if;
end
$test$;

rollback;
