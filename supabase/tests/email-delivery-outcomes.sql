-- Disposable PostgreSQL only; fixture sends and timestamps are synthetic.
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
insert into auth.users(id,email) values ('e1000000-0000-4000-8000-000000000001','steward@example.test');
insert into auth.sessions(id,user_id,not_after) values ('e2000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001',now()+interval '1 hour');
insert into private.steward_roles values ('e1000000-0000-4000-8000-000000000001',true,now());
insert into private.intake_settings values(true,encode(sha256(convert_to('synthetic-secret','UTF8')),'hex'));
insert into public.applications(id,display_name,applicant_type,email,original_answers) values
 ('e3000000-0000-4000-8000-000000000001','Synthetic delivery applicant','individual','applicant@example.test','{}');
set local request.jwt.claims='{"sub":"e1000000-0000-4000-8000-000000000001","session_id":"e2000000-0000-4000-8000-000000000001"}';
set local role authenticated;
select set_config('test.decision',public.membership_command(gen_random_uuid(),
  '{"action":"review-application","id":"e3000000-0000-4000-8000-000000000001","revision":1,"state":"approved","reason":"Synthetic review","applicant_message":""}')::text,true);
select pg_temp.expect_error($q$select public.record_email_delivery('synthetic-secret',gen_random_uuid(),'delivered',now())$q$,'42501');
select pg_temp.expect_error($q$select * from private.email_delivery_outcomes$q$,'42501');
reset role;
set local role anon;
select pg_temp.expect_error($q$select public.record_email_delivery('wrong',gen_random_uuid(),'delivered',now())$q$,'PT403');
select pg_temp.expect_error($q$select * from private.email_delivery_outcomes$q$,'42501');
select pg_temp.expect_error($q$select public.application_notifications('e3000000-0000-4000-8000-000000000001')$q$,'42501');
-- Webhooks can beat the send completion and can arrive duplicated or out of order.
select public.record_email_delivery('synthetic-secret','e4000000-0000-4000-8000-000000000001','delivered','2026-10-30 10:00Z');
select public.record_email_delivery('synthetic-secret','e4000000-0000-4000-8000-000000000002','bounced','2026-10-30 10:05Z');
select public.record_email_delivery('synthetic-secret','e4000000-0000-4000-8000-000000000002','bounced','2026-10-30 10:05Z');
select public.record_email_delivery('synthetic-secret','e4000000-0000-4000-8000-000000000002','delivered','2026-10-30 10:05Z');
select public.record_email_delivery('synthetic-secret','e4000000-0000-4000-8000-000000000002','delivered','2026-10-30 10:01Z');
select public.record_email_delivery('synthetic-secret','e4000000-0000-4000-8000-000000000003','bounced','2026-10-30 10:05Z');
reset role;
insert into private.notification_jobs(application_id,channel,status,attempts,provider_message_id) values
 ('e3000000-0000-4000-8000-000000000001','receipt','sent',1,'e4000000-0000-4000-8000-000000000001'),
 ('e3000000-0000-4000-8000-000000000001','steward','sent',1,'e4000000-0000-4000-8000-000000000003');
update private.notification_jobs set status='sent',attempts=1,provider_message_id='e4000000-0000-4000-8000-000000000002'
where id=(current_setting('test.decision')::jsonb->>'notification_id')::uuid;
set local role authenticated;
with rows as (
  select jsonb_array_elements(public.application_notifications('e3000000-0000-4000-8000-000000000001')) as job
)
select pg_temp.assert_true(
  count(*)=3 and
  count(*) filter (where job->>'channel'='receipt' and job->>'delivery_outcome'='delivered')=1 and
  count(*) filter (where job->>'channel'='decision' and job->>'delivery_outcome'='bounced'
    and (job->>'delivery_occurred_at')::timestamptz='2026-10-30 10:05Z'
    and job->>'status'='sent' and job->>'retry_block'='already_sent')=1 and
  count(*) filter (where job->>'channel'='steward' and job->>'delivery_outcome' is null)=1,
  'delivery correlation, order, scope, or retry rules changed'
) from rows;
reset role;
select pg_temp.assert_true((select count(*)=3 from private.email_delivery_outcomes),'duplicate rows stored');
update private.steward_roles set active=false;
set local role authenticated;
select pg_temp.expect_error($q$select public.application_notifications('e3000000-0000-4000-8000-000000000001')$q$,'PT403');
reset role;
select pg_temp.assert_true((select review_state='approved' and member_id is null from public.applications),'webhook changed membership or review state');
rollback;
