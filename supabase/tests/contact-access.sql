-- Synthetic contact records, Auth users and credentials roll back.
begin;
create function pg_temp.assert_true(ok boolean, message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end $$;
insert into auth.users(id,email) values
 ('a1000000-0000-4000-8000-000000000001','contact-steward@example.test'),
 ('a1000000-0000-4000-8000-000000000002','contact-visitor@example.test');
insert into auth.sessions(id,user_id,not_after) values
 ('a2000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001',now()+interval '1 hour'),
 ('a2000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002',now()+interval '1 hour');
insert into private.steward_roles(user_id,active) values('a1000000-0000-4000-8000-000000000001',true);
insert into private.intake_settings values(true,encode(sha256(convert_to('synthetic-contact-capability','UTF8')),'hex'));
set local role anon;
select public.submit_contact('synthetic-contact-capability','a3000000-0000-4000-8000-000000000001',
 '{"name":"Synthetic Visitor","email":"visitor@example.test","subject":"Hello","message":"Synthetic contact 🌳"}',repeat('c',64));
select public.submit_contact('synthetic-contact-capability','a3000000-0000-4000-8000-000000000001',
 '{"name":"Synthetic Visitor","email":"visitor@example.test","subject":"Hello","message":"Synthetic contact 🌳"}',repeat('c',64));
do $$ begin
 begin perform * from public.contact_messages; raise exception 'Anonymous contact read allowed'; exception when insufficient_privilege then null; end;
 begin perform public.submit_contact('synthetic-contact-capability','a3000000-0000-4000-8000-000000000001',
  '{"name":"Synthetic Visitor","email":"visitor@example.test","subject":"Hello","message":"Changed request"}',repeat('c',64));
  raise exception 'Contact identity reused'; exception when sqlstate 'PT409' then null; end;
 begin perform public.submit_contact('synthetic-contact-capability','a3000000-0000-4000-8000-000000000002',
  '{"name":"Synthetic Visitor","email":"invalid-email","subject":"Hello","message":"Invalid email"}',repeat('c',64));
  raise exception 'Invalid contact email accepted'; exception when sqlstate 'PT400' then null; end;
end $$;
reset role;
select pg_temp.assert_true((select count(*)=1 from public.contact_messages),'Contact retry duplicated');
select pg_temp.assert_true((select count(*)=0 from private.notification_jobs),'Contact created membership jobs');
select pg_temp.assert_true((select count(*)=1 from public.contact_messages where notification_state='pending'),'Contact queue missing');
set local role anon;
do $$ begin
 begin perform public.claim_contact_notifications('wrong',null); raise exception 'Untrusted worker claimed contact'; exception when sqlstate 'PT403' then null; end;
end $$;
reset role;
create temporary table claimed as select * from public.claim_contact_notifications('synthetic-contact-capability',null);
select pg_temp.assert_true((select count(*)=1 from claimed),'No notification claimed');
select pg_temp.assert_true((select count(*)=0 from public.claim_contact_notifications('synthetic-contact-capability',null)),'Concurrent notification claimed twice');
do $$ begin
 begin perform public.finish_contact_notification('synthetic-contact-capability',(select id from claimed),gen_random_uuid(),'sent');
 raise exception 'Wrong lease accepted'; exception when sqlstate 'PT409' then null; end;
end $$;
select public.finish_contact_notification('synthetic-contact-capability',id,notification_lease,'sent') from claimed;
select pg_temp.assert_true((select count(*)=0 from public.claim_contact_notifications('synthetic-contact-capability',null)),'Sent notification reclaimed');
update public.contact_messages set notification_state='sending',notification_updated_at=now()-interval '6 minutes';
select pg_temp.assert_true((select count(*)=0 from public.claim_contact_notifications('synthetic-contact-capability',null)),'Stale uncertain notification retried');
select pg_temp.assert_true((select notification_state='needs_review' from public.contact_messages),'Uncertain delivery not visible');
set local request.jwt.claims='{"sub":"a1000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"a2000000-0000-4000-8000-000000000002","user_metadata":{"steward":true}}';
set local role authenticated;
select pg_temp.assert_true((select count(id)=0 from public.contact_messages),'Non-steward contact read allowed');
reset role;
set local request.jwt.claims='{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"a2000000-0000-4000-8000-000000000001"}';
set local role authenticated;
select pg_temp.assert_true((select count(id)=1 from public.contact_messages),'Steward cannot read contact');
do $$ begin
 begin update public.contact_messages set message='Overwritten'; raise exception 'Steward overwrote correspondence'; exception when insufficient_privilege then null; end;
 begin perform notification_lease from public.contact_messages; raise exception 'Steward read worker lease'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update private.steward_roles set active=false where user_id='a1000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.assert_true((select count(id)=0 from public.contact_messages),'Revoked steward can read contact');
reset role;
update private.steward_roles set active=true where user_id='a1000000-0000-4000-8000-000000000001';
update auth.sessions set not_after=now()-interval '1 minute' where id='a2000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.assert_true((select count(id)=0 from public.contact_messages),'Expired session can read contact');
reset role;
update auth.sessions set not_after=now()+interval '1 hour' where id='a2000000-0000-4000-8000-000000000001';
delete from auth.sessions where id='a2000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.assert_true((select count(id)=0 from public.contact_messages),'Revoked session can read contact');
reset role;
rollback;
select 'PASS: private contact, idempotency, bounded worker, safe notification leases, active-steward reads';
