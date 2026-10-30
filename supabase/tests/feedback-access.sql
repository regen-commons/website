-- Synthetic feedback records, Auth users and credentials roll back.
begin;
create function pg_temp.assert_true(ok boolean, message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end $$;
insert into auth.users(id,email) values
 ('a1000000-0000-4000-8000-000000000001','feedback-steward@example.test'),
 ('a1000000-0000-4000-8000-000000000002','feedback-visitor@example.test');
insert into auth.sessions(id,user_id,not_after) values
 ('a2000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001',now()+interval '1 hour'),
 ('a2000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002',now()+interval '1 hour');
insert into private.steward_roles(user_id,active) values('a1000000-0000-4000-8000-000000000001',true);
insert into private.intake_settings values(true,encode(sha256(convert_to('synthetic-feedback-capability','UTF8')),'hex'));
set local role anon;
select public.submit_intake('synthetic-feedback-capability','feedback','a3000000-0000-4000-8000-000000000001',
 '{"message":"Synthetic feedback 🌳","categories":["Bug","Idea"],"page_path":"/map"}',repeat('c',64));
select public.submit_intake('synthetic-feedback-capability','feedback','a3000000-0000-4000-8000-000000000001',
 '{"message":"Synthetic feedback 🌳","categories":["Bug","Idea"],"page_path":"/map"}',repeat('c',64));
do $$ begin
 begin perform * from public.feedback; raise exception 'Anonymous feedback read allowed'; exception when insufficient_privilege then null; end;
 begin perform public.submit_intake('synthetic-feedback-capability','feedback','a3000000-0000-4000-8000-000000000001',
  '{"message":"Changed request","categories":[],"page_path":"/"}',repeat('c',64));
  raise exception 'Feedback identity reused'; exception when sqlstate 'PT409' then null; end;
 begin perform public.submit_intake('synthetic-feedback-capability','feedback','a3000000-0000-4000-8000-000000000002',
  '{"message":"Invalid category","categories":["unsupported"],"page_path":"/"}',repeat('c',64));
  raise exception 'Invalid feedback category accepted'; exception when sqlstate 'PT400' then null; end;
end $$;
reset role;
select pg_temp.assert_true((select count(*)=1 from public.feedback),'Feedback retry duplicated');
select pg_temp.assert_true((select count(*)=0 from private.notification_jobs),'Feedback sent notifications');
set local request.jwt.claims='{"sub":"a1000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"a2000000-0000-4000-8000-000000000002","user_metadata":{"steward":true}}';
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.feedback),'Non-steward feedback read allowed');
reset role;
set local request.jwt.claims='{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"a2000000-0000-4000-8000-000000000001"}';
set local role authenticated;
select pg_temp.assert_true((select count(*)=1 from public.feedback),'Steward cannot read feedback');
reset role;
update private.steward_roles set active=false where user_id='a1000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.feedback),'Revoked steward can read feedback');
reset role;
rollback;
select 'PASS: private feedback, source context, idempotency, allowed categories, no notifications, active-steward reads';
