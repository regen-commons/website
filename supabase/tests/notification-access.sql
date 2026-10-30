-- Disposable PostgreSQL only; no external requests. All synthetic data rolls back.
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
 begin if ok is distinct from true then raise exception '%',message; end if; end $$;
insert into auth.users(id,email) values
 ('91000000-0000-4000-8000-000000000001','steward@example.test'),
 ('91000000-0000-4000-8000-000000000002','visitor@example.test'),
 ('91000000-0000-4000-8000-000000000003','other-steward@example.test');
insert into auth.sessions(id,user_id,not_after) values
 ('92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001',now()+interval '1 hour'),
 ('92000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000002',now()+interval '1 hour'),
 ('92000000-0000-4000-8000-000000000003','91000000-0000-4000-8000-000000000003',now()+interval '1 hour');
insert into private.steward_roles(user_id,active) values
 ('91000000-0000-4000-8000-000000000001',true),('91000000-0000-4000-8000-000000000003',true);
insert into public.applications(id,display_name,applicant_type,email,original_answers)
 select ('a1000000-0000-4000-8000-00000000000'||n)::uuid,'Synthetic applicant '||n,'individual','person@example.test','{}' from generate_series(1,6) n;
insert into private.notification_jobs(id,application_id,channel,status,attempts,created_at,updated_at)
 select ('b1000000-0000-4000-8000-00000000000'||n)::uuid,('a1000000-0000-4000-8000-00000000000'||n)::uuid,'receipt',
 case when n in (5,6) then 'sending' else 'failed' end,case when n=3 then 3 else 1 end,
 now()-case when n=4 then interval '24 hours' else interval '1 hour' end,
 now()-case when n=6 then interval '6 minutes' else interval '1 minute' end
 from generate_series(1,6) n where n<>2;
insert into private.notification_jobs(application_id,channel,status,attempts,provider_message_id) values
 ('a1000000-0000-4000-8000-000000000001','steward','sent',1,'c1000000-0000-4000-8000-000000000001'),
 ('a1000000-0000-4000-8000-000000000001','telegram','needs_review',1,null);
insert into private.intake_settings values(true,encode(sha256(convert_to('synthetic-secret','UTF8')),'hex'));
select set_config('test.telegram_job',(select id::text from private.notification_jobs where channel='telegram'),true);
set local role anon;
do $$ begin
 begin perform public.application_notifications('a1000000-0000-4000-8000-000000000001'); raise exception 'anonymous read allowed'; exception when insufficient_privilege then null; end;
 begin perform public.retry_notification('a1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001',1); raise exception 'anonymous retry allowed'; exception when insufficient_privilege then null; end;
 begin perform * from private.notification_jobs; raise exception 'private ledger exposed'; exception when insufficient_privilege then null; end;
 begin perform public.notification_result('wrong','b1000000-0000-4000-8000-000000000001',null,'sent',null,null); raise exception 'bad worker credential accepted'; exception when sqlstate 'PT403' then null; end;
end $$;
reset role;
set local request.jwt.claims='{"sub":"91000000-0000-4000-8000-000000000002","session_id":"92000000-0000-4000-8000-000000000002","user_metadata":{"steward":true}}';
set local role authenticated;
do $$ begin
 begin perform public.application_notifications('a1000000-0000-4000-8000-000000000001'); raise exception 'visitor read allowed'; exception when sqlstate 'PT403' then null; end;
 begin perform public.retry_notification('a1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001',1); raise exception 'visitor retry allowed'; exception when sqlstate 'PT403' then null; end;
 begin perform public.complete_notification_retry('b1000000-0000-4000-8000-000000000001',null,'sent',null,null); raise exception 'visitor completion allowed'; exception when sqlstate 'PT403' then null; end;
end $$;
reset role;
set local request.jwt.claims='{"sub":"91000000-0000-4000-8000-000000000001","session_id":"92000000-0000-4000-8000-000000000001"}';
set local role authenticated;
select pg_temp.assert_true(public.application_notifications('a1000000-0000-4000-8000-000000000002')='[]'::jsonb,'imported application acquired delivery evidence');
select pg_temp.assert_true(jsonb_array_length(public.application_notifications('a1000000-0000-4000-8000-000000000001'))=2,'email projection includes Telegram or lost an email');
select pg_temp.assert_true(public.application_notifications('a1000000-0000-4000-8000-000000000001')::text!~'lease_id|email|person@|secret','private worker data leaked');
do $$ begin
 begin perform * from private.notification_jobs; raise exception 'steward has broad table access'; exception when insufficient_privilege then null; end;
 begin perform public.retry_notification('a1000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000001',1); raise exception 'cross-application retry allowed'; exception when sqlstate 'PT404' then null; end;
 begin perform public.retry_notification('a1000000-0000-4000-8000-000000000001',current_setting('test.telegram_job')::uuid,1); raise exception 'Telegram retry allowed'; exception when sqlstate 'PT404' then null; end;
end $$;
select set_config('test.notification_lease',(public.retry_notification('a1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001',1)->>'lease_id'),true);
reset role;
set local role anon;
select pg_temp.assert_true(jsonb_array_length(public.notification_work('synthetic-secret','a1000000-0000-4000-8000-000000000001',null,null,null))=0,'background worker reclaimed the live steward lease');
reset role;
set local role authenticated;
do $$ begin
 begin perform public.retry_notification('a1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001',1); raise exception 'duplicate stale command accepted'; exception when sqlstate 'PT409' then null; end;
 begin perform public.retry_notification('a1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001',2); raise exception 'in-flight retry accepted'; exception when sqlstate 'PT409' then null; end;
 begin perform public.complete_notification_retry('b1000000-0000-4000-8000-000000000001',gen_random_uuid(),'sent',null,null); raise exception 'incorrect lease completed'; exception when sqlstate 'PT409' then null; end;
 begin perform public.retry_notification('a1000000-0000-4000-8000-000000000003','b1000000-0000-4000-8000-000000000003',3); raise exception 'attempt limit bypassed'; exception when sqlstate 'PT409' then null; end;
 begin perform public.retry_notification('a1000000-0000-4000-8000-000000000004','b1000000-0000-4000-8000-000000000004',1); raise exception '24 hour boundary bypassed'; exception when sqlstate 'PT409' then null; end;
 begin perform public.retry_notification('a1000000-0000-4000-8000-000000000005','b1000000-0000-4000-8000-000000000005',1); raise exception 'active lease bypassed'; exception when sqlstate 'PT409' then null; end;
end $$;
reset role;
set local request.jwt.claims='{"sub":"91000000-0000-4000-8000-000000000003","session_id":"92000000-0000-4000-8000-000000000003"}';
set local role authenticated;
do $$ begin
 begin perform public.complete_notification_retry('b1000000-0000-4000-8000-000000000001',current_setting('test.notification_lease')::uuid,'sent',null,null); raise exception 'other steward completed the lease'; exception when sqlstate 'PT409' then null; end;
end $$;
reset role;
set local request.jwt.claims='{"sub":"91000000-0000-4000-8000-000000000001","session_id":"92000000-0000-4000-8000-000000000001"}';
set local role authenticated;
select public.complete_notification_retry('b1000000-0000-4000-8000-000000000001',current_setting('test.notification_lease')::uuid,'sent','c1000000-0000-4000-8000-000000000002',null);
do $$ begin
 begin perform public.retry_notification('a1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001',2); raise exception 'accepted email resent'; exception when sqlstate 'PT409' then null; end;
end $$;
select set_config('test.notification_lease',(public.retry_notification('a1000000-0000-4000-8000-000000000006','b1000000-0000-4000-8000-000000000006',1)->>'lease_id'),true);
reset role;
select pg_temp.assert_true((select attempts=2 and retry_actor_id='91000000-0000-4000-8000-000000000001' and retry_requested_at is not null
 from private.notification_jobs where id='b1000000-0000-4000-8000-000000000001'),'attempts or retry attribution missing');
select pg_temp.assert_true((select provider_message_id='c1000000-0000-4000-8000-000000000002' and failure_code is null
 from private.notification_jobs where id='b1000000-0000-4000-8000-000000000001'),'Resend ID not retained');
set local role anon;
select public.notification_result('synthetic-secret','b1000000-0000-4000-8000-000000000006',current_setting('test.notification_lease')::uuid,'failed',null,'notification_timeout');
reset role;
select pg_temp.assert_true((select failure_code='notification_timeout' from private.notification_jobs where id='b1000000-0000-4000-8000-000000000006'),'safe failure reason missing');
update private.steward_roles set active=false where user_id='91000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin
 begin perform public.application_notifications('a1000000-0000-4000-8000-000000000001'); raise exception 'revoked role read allowed'; exception when sqlstate 'PT403' then null; end;
 begin perform public.retry_notification('a1000000-0000-4000-8000-000000000006','b1000000-0000-4000-8000-000000000006',2); raise exception 'revoked role retry allowed'; exception when sqlstate 'PT403' then null; end;
end $$;
reset role;
update private.steward_roles set active=true where user_id='91000000-0000-4000-8000-000000000001';
update auth.sessions set not_after=now()-interval '1 second' where id='92000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin
 begin perform public.application_notifications('a1000000-0000-4000-8000-000000000001'); raise exception 'expired session read allowed'; exception when sqlstate 'PT403' then null; end;
 begin perform public.retry_notification('a1000000-0000-4000-8000-000000000006','b1000000-0000-4000-8000-000000000006',2); raise exception 'expired session retry allowed'; exception when sqlstate 'PT403' then null; end;
end $$;
reset role;
delete from auth.sessions where id='92000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin
 begin perform public.complete_notification_retry('b1000000-0000-4000-8000-000000000006',current_setting('test.notification_lease')::uuid,'sent',null,null); raise exception 'revoked session completion allowed'; exception when sqlstate 'PT403' then null; end;
end $$;
reset role;
rollback;
select 'PASS: private email projection, active steward/session checks, safe result persistence, attempt/window limits, lease fencing, stale clicks, cross-application denial, acceptance deduplication; synthetic data rolled back' as result;
