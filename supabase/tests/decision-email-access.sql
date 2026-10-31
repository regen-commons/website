-- Disposable PostgreSQL only; no external requests or real recipients.
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end $$;
create function pg_temp.expect_error(command text,expected text) returns void language plpgsql as $$
begin
  begin execute command; exception when others then
    if sqlstate=expected then return; end if; raise;
  end;
  raise exception 'Expected error % for %',expected,command;
end $$;
insert into auth.users(id,email) values ('d1000000-0000-4000-8000-000000000001','steward@example.test');
insert into auth.sessions(id,user_id,not_after) values ('d2000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001',now()+interval '1 hour');
insert into private.steward_roles values ('d1000000-0000-4000-8000-000000000001',true,now());
insert into private.intake_settings values(true,encode(sha256(convert_to('synthetic-secret','UTF8')),'hex'));
insert into public.applications(id,display_name,applicant_type,email,original_answers) values
 ('d3000000-0000-4000-8000-000000000001','Synthetic decision applicant','individual','applicant@example.test','{"constraints":"PRIVATE-ONLY"}');
select pg_temp.assert_true(not exists(select 1 from private.notification_jobs),'historical application was emailed automatically');
set local request.jwt.claims='{"sub":"d1000000-0000-4000-8000-000000000001","session_id":"d2000000-0000-4000-8000-000000000001"}';
set local role authenticated;
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{"action":"review-application","id":"d3000000-0000-4000-8000-000000000001","revision":1,"state":"approved","reason":"Old client"}')$q$,'PT400');
select set_config('test.approval',(public.membership_command('d4000000-0000-4000-8000-000000000001','{"action":"review-application","id":"d3000000-0000-4000-8000-000000000001","revision":1,"state":"approved","reason":"PRIVATE-ONLY","applicant_message":"Thank you for applying."}'))::text,true);
select pg_temp.assert_true(public.membership_command('d4000000-0000-4000-8000-000000000001','{"action":"review-application","id":"d3000000-0000-4000-8000-000000000001","revision":1,"state":"approved","reason":"PRIVATE-ONLY","applicant_message":"Thank you for applying."}')=current_setting('test.approval')::jsonb,'replay changed email identity');
select pg_temp.expect_error($q$select public.membership_command('d4000000-0000-4000-8000-000000000001','{"action":"review-application","id":"d3000000-0000-4000-8000-000000000001","revision":1,"state":"approved","reason":"PRIVATE-ONLY","applicant_message":"Changed email"}')$q$,'PT409');
select pg_temp.assert_true(public.application_notifications('d3000000-0000-4000-8000-000000000001')::text!~'PRIVATE-ONLY|lease_id','private rationale or worker fields leaked');
select pg_temp.assert_true(public.application_notifications('d3000000-0000-4000-8000-000000000001')->0->>'recipient'='applicant@example.test','actual recipient absent from steward diagnostics');
select pg_temp.assert_true(jsonb_array_length(public.application_notifications('d3000000-0000-4000-8000-000000000001'))=1,'duplicate decision queued');
reset role;
select pg_temp.assert_true((select count(*)=1 from private.notification_jobs),'approval replay duplicated email');
select pg_temp.assert_true((select review_state='approved' and member_id is null and original_answers->>'constraints'='PRIVATE-ONLY' from public.applications where id='d3000000-0000-4000-8000-000000000001'),'email changed membership or evidence');
select pg_temp.assert_true((select to_jsonb(j)::text!~'PRIVATE-ONLY' from private.notification_jobs j),'private reason copied into email snapshot');
set local role anon;
select pg_temp.assert_true(public.notification_work('synthetic-secret','d3000000-0000-4000-8000-000000000001',null,null,null)='[]'::jsonb,'anonymous intake worker claimed decision mail');
select pg_temp.expect_error($q$select public.application_notifications('d3000000-0000-4000-8000-000000000001')$q$,'42501');
reset role;
set local role authenticated;
select set_config('test.claim',(public.retry_notification('d3000000-0000-4000-8000-000000000001',(current_setting('test.approval')::jsonb->>'notification_id')::uuid,0))::text,true);
select pg_temp.assert_true(current_setting('test.claim')::jsonb->>'state'='approved','decision outcome lost in dispatch');
select pg_temp.assert_true(current_setting('test.claim')::jsonb->>'message'='Thank you for applying.','public message lost in dispatch');
select public.membership_command(gen_random_uuid(),'{"action":"review-application","id":"d3000000-0000-4000-8000-000000000001","revision":2,"state":"pending","reason":"Reopen deliberately"}');
select pg_temp.expect_error($q$select public.retry_notification('d3000000-0000-4000-8000-000000000001',(current_setting('test.approval')::jsonb->>'notification_id')::uuid,1)$q$,'PT409');
-- A provider send already claimed before reopening still has a recordable outcome.
reset role;
set local role anon;
select public.notification_result('synthetic-secret',(current_setting('test.approval')::jsonb->>'notification_id')::uuid,(current_setting('test.claim')::jsonb->>'lease_id')::uuid,'sent','d5000000-0000-4000-8000-000000000001',null);
reset role;
set local role authenticated;
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{"action":"review-application","id":"d3000000-0000-4000-8000-000000000001","revision":3,"state":"changes_requested","reason":"Private review","applicant_message":"  "}')$q$,'PT400');
select set_config('test.changes',(public.membership_command(gen_random_uuid(),'{"action":"review-application","id":"d3000000-0000-4000-8000-000000000001","revision":3,"state":"changes_requested","reason":"PRIVATE-ONLY","applicant_message":"Please clarify your contribution."}'))::text,true);
select set_config('test.decline',(public.membership_command(gen_random_uuid(),'{"action":"review-application","id":"d3000000-0000-4000-8000-000000000001","revision":4,"state":"declined","reason":"PRIVATE-ONLY","applicant_message":""}'))::text,true);
select pg_temp.expect_error($q$select public.retry_notification('d3000000-0000-4000-8000-000000000001',(current_setting('test.changes')::jsonb->>'notification_id')::uuid,0)$q$,'PT409');
reset role;
select pg_temp.assert_true((select status='superseded' and attempts=0 from private.notification_jobs where id=(current_setting('test.changes')::jsonb->>'notification_id')::uuid),'obsolete pending email not superseded');
select pg_temp.assert_true((select count(*)=3 from private.notification_jobs),'reopening or invalid decision queued an email');
insert into public.members(id,name,member_type) values ('d6000000-0000-4000-8000-000000000001','Synthetic draft','individual');
set local role authenticated;
select public.membership_command(gen_random_uuid(),'{"action":"link-profile","id":"d3000000-0000-4000-8000-000000000001","revision":5,"member_id":"d6000000-0000-4000-8000-000000000001","reason":"Curate a separate draft"}');
reset role;
select pg_temp.assert_true((select private.email_retry_block(j) is null from private.notification_jobs j where id=(current_setting('test.decline')::jsonb->>'notification_id')::uuid),'profile linking incorrectly superseded a decision email');
update public.applications set display_name='Changed later',email='changed@example.test' where id='d3000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('test.decline_claim',(public.retry_notification('d3000000-0000-4000-8000-000000000001',(current_setting('test.decline')::jsonb->>'notification_id')::uuid,0))::text,true);
select pg_temp.assert_true(current_setting('test.decline_claim')::jsonb->>'name'='Synthetic decision applicant' and current_setting('test.decline_claim')::jsonb->>'email'='applicant@example.test','retry changed the immutable recipient snapshot');
select pg_temp.assert_true(current_setting('test.decline_claim')::jsonb->>'version'='1','template identity lost');
select pg_temp.expect_error($q$select * from private.notification_jobs$q$,'42501');
reset role;
select pg_temp.assert_true(not has_function_privilege('anon','public.membership_command(uuid,jsonb)','execute'),'anonymous decision authority added');
select pg_temp.assert_true((select relrowsecurity from pg_class where oid='private.notification_jobs'::regclass),'private outbox lost RLS');
rollback;
select 'PASS: atomic decision/outbox, no backfill, public/private message separation, explicit delivery intent, immutable snapshot, replay, supersession, active-session claims and denied anonymous access' as result;
