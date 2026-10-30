-- Run as the database owner against a disposable or empty pilot database.
-- All synthetic records, users, and sessions roll back, including on assertion failure.
begin;
create function pg_temp.assert_true(ok boolean, message text) returns void
language plpgsql as $$ begin if ok is distinct from true then raise exception '%', message; end if; end $$;

insert into auth.users (id, email) values
  ('91000000-0000-4000-8000-000000000001', 'db-steward@example.test'),
  ('91000000-0000-4000-8000-000000000002', 'db-visitor@example.test');
insert into auth.sessions (id, user_id, not_after) values
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', now() + interval '1 hour'),
  ('92000000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000002', now() + interval '1 hour'),
  ('92000000-0000-4000-8000-000000000003', '91000000-0000-4000-8000-000000000001', now() - interval '1 hour');
insert into private.steward_roles(user_id, active) values ('91000000-0000-4000-8000-000000000001', true);
insert into public.members(id, name, member_type, publication_state) values
  ('93000000-0000-4000-8000-000000000001', 'Synthetic draft person', 'individual', 'draft'),
  ('93000000-0000-4000-8000-000000000002', 'Synthetic published organization', 'organization', 'published');
insert into public.applications(id, display_name, applicant_type, email, original_answers, member_id) values
  ('94000000-0000-4000-8000-000000000001', 'Synthetic applicant', 'individual', 'applicant@example.test', '{"constraints":"private synthetic answer"}', '93000000-0000-4000-8000-000000000001');
insert into public.affiliations values ('93000000-0000-4000-8000-000000000001', '93000000-0000-4000-8000-000000000002');
insert into public.contributions(id, title) values ('95000000-0000-4000-8000-000000000001', 'Synthetic guide');
insert into public.contribution_members values ('95000000-0000-4000-8000-000000000001', '93000000-0000-4000-8000-000000000001');
insert into public.review_events(application_id, actor_id, event_type, reviewed_revision, note) values
  ('94000000-0000-4000-8000-000000000001', null, 'synthetic_capture', 1, 'No approval implied');


select pg_temp.assert_true(private.utf16_length('😀😀')=4,'Unicode length differs from browser');
insert into public.seeds(id,text) values('96000000-0000-4000-8000-000000000001','Synthetic public seed');
insert into public.seeds(text,publication_state) values('Synthetic hidden seed','hidden');
update public.contributions set publication_state='published';
insert into private.intake_settings values(true,encode(sha256(convert_to('synthetic-intake-secret','UTF8')),'hex'));
set local role anon;
select pg_temp.assert_true((select count(*)=1 from public.website_members),'public member projection or RLS failed');
select pg_temp.assert_true((select contributors='[]'::jsonb from public.website_contributions),'private contributor name leaked');
select pg_temp.assert_true((select count(*)=1 from public.website_seeds),'hidden seed leaked');
do $$ begin
 begin perform * from public.applications; raise exception 'private applications leaked'; exception when insufficient_privilege then null; end;
 begin update public.seeds set publication_state='hidden'; raise exception 'anonymous moderation allowed'; exception when insufficient_privilege then null; end;
 begin perform public.moderate_content('seeds','96000000-0000-4000-8000-000000000001',1,'hidden','bad actor'); raise exception 'anonymous moderation RPC allowed'; exception when insufficient_privilege then null; end;
 begin perform public.submit_intake('wrong','seed','97000000-0000-4000-8000-000000000001','{"text":"A synthetic seed"}',repeat('a',64)); raise exception 'missing credential accepted'; exception when sqlstate 'PT403' then null; end;
end $$;
select public.submit_intake('synthetic-intake-secret','seed','97000000-0000-4000-8000-000000000001','{"text":"A synthetic saved seed","author":"Demo"}',repeat('a',64));
select public.submit_intake('synthetic-intake-secret','seed','97000000-0000-4000-8000-000000000001','{"text":"A synthetic saved seed","author":"Demo"}',repeat('a',64));
select pg_temp.assert_true((select count(*)=1 from public.website_seeds where text='A synthetic saved seed'),'duplicate seed on retry');
do $$ begin
 begin perform public.submit_intake('synthetic-intake-secret','seed','97000000-0000-4000-8000-000000000001','{"text":"Different payload"}',repeat('a',64)); raise exception 'request identity reused'; exception when sqlstate 'PT409' then null; end;
end $$;
select public.submit_intake('synthetic-intake-secret','application','97000000-0000-4000-8000-000000000002','{"full-name":"New synthetic applicant","email":"new@example.test"}',repeat('b',64));
reset role;
select pg_temp.assert_true((select count(*)=1 from public.applications where email='new@example.test'),'request not saved privately');
select pg_temp.assert_true((select count(*)=3 from private.notification_jobs),'notification job not atomic with request');
set local request.jwt.claims='{"sub":"91000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"92000000-0000-4000-8000-000000000002","user_metadata":{"steward":true}}';
set local role authenticated;
do $$ begin
 begin perform public.moderate_content('seeds','96000000-0000-4000-8000-000000000001',1,'hidden','visitor'); raise exception 'visitor moderated'; exception when sqlstate 'PT403' then null; end;
end $$;
reset role;
set local request.jwt.claims='{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"92000000-0000-4000-8000-000000000001"}';
set local role authenticated;
select public.moderate_content('seeds','96000000-0000-4000-8000-000000000001',1,'hidden','Synthetic moderation reason');
select pg_temp.assert_true((select count(*)=1 from public.content_events where seed_id='96000000-0000-4000-8000-000000000001' and actor_id=auth.uid() and revision=2),'moderation history missing');
do $$ begin
 begin perform public.moderate_content('seeds','96000000-0000-4000-8000-000000000001',1,'published','stale'); raise exception 'stale revision accepted'; exception when sqlstate 'PT409' then null; end;
end $$;
reset role;
set local role anon;
select pg_temp.assert_true((select count(*)=0 from public.website_seeds where id='96000000-0000-4000-8000-000000000001'),'hidden seed still public');
reset role;
set local role authenticated;
select public.moderate_content('seeds','96000000-0000-4000-8000-000000000001',2,'published','Restore after review');
select public.save_contribution(null,null,'{"title":"Synthetic new contribution","tags":[],"capital_forms":[],"contributor_ids":["93000000-0000-4000-8000-000000000002"]}','98000000-0000-4000-8000-000000000001');
select public.save_contribution(null,null,'{"title":"Synthetic new contribution","tags":[],"capital_forms":[],"contributor_ids":["93000000-0000-4000-8000-000000000002"]}','98000000-0000-4000-8000-000000000001');
select pg_temp.assert_true((select count(*)=1 from public.contributions where title='Synthetic new contribution' and publication_state='published'),'new contribution duplicated or not immediate');
select public.moderate_content('contributions','95000000-0000-4000-8000-000000000001',1,'hidden','Hide synthetic guide');
select public.save_contribution('95000000-0000-4000-8000-000000000001',2,'{"title":"Edited hidden guide","tags":[],"capital_forms":[],"contributor_ids":[]}','98000000-0000-4000-8000-000000000002');
select pg_temp.assert_true((select publication_state='hidden' from public.contributions where id='95000000-0000-4000-8000-000000000001'),'edit republished hidden content');
do $$ begin
 begin perform public.save_contribution('95000000-0000-4000-8000-000000000001',3,'{"title":"Must roll back","tags":[],"capital_forms":[],"contributor_ids":["99999999-0000-4000-8000-000000000001"]}','98000000-0000-4000-8000-000000000003'); raise exception 'unknown contributor accepted'; exception when sqlstate 'PT400' then null; end;
end $$;
select pg_temp.assert_true((select title='Edited hidden guide' and revision=3 from public.contributions where id='95000000-0000-4000-8000-000000000001'),'failed edit was not atomic');
reset role;
set local role anon;
select pg_temp.assert_true(jsonb_array_length(public.notification_work('synthetic-intake-secret',null,null,null,null))=3,'notification jobs not leased');
select pg_temp.assert_true(jsonb_array_length(public.notification_work('synthetic-intake-secret',null,null,null,null))=0,'notification jobs leased twice');
reset role;
update private.notification_jobs set updated_at=now()-interval '6 minutes' where channel='telegram';
set local role anon;
select public.notification_work('synthetic-intake-secret',null,null,null,null);
reset role;
select pg_temp.assert_true((select status='needs_review' from private.notification_jobs where channel='telegram'),'uncertain Telegram send retried');
update private.steward_roles set active=false;
set local role authenticated;
do $$ begin
 begin perform public.moderate_content('seeds','96000000-0000-4000-8000-000000000001',3,'hidden','revoked'); raise exception 'revoked steward moderated'; exception when sqlstate 'PT403' then null; end;
end $$;
reset role;
update private.steward_roles set active=true;
delete from auth.sessions where id='92000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin
 begin perform public.moderate_content('seeds','96000000-0000-4000-8000-000000000001',3,'hidden','revoked session'); raise exception 'revoked session moderated'; exception when sqlstate 'PT403' then null; end;
end $$;
reset role;
rollback;
select 'PASS: public projections, private data isolation, credential gate, immediate save, idempotency, moderation/history, revision conflicts, atomic edits, role/session revocation; synthetic data rolled back' as result;
