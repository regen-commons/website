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

set local role anon;
do $$ begin
  begin perform * from public.applications; raise exception 'anon read private answers'; exception when insufficient_privilege then null; end;
  begin perform * from public.members; raise exception 'public projection activated unexpectedly'; exception when insufficient_privilege then null; end;
  begin perform public.steward_access(); raise exception 'anon called role RPC'; exception when insufficient_privilege then null; end;
end $$;
reset role;

set local request.jwt.claims = '{"sub":"91000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"92000000-0000-4000-8000-000000000002","user_metadata":{"steward":true,"role":"admin"}}';
set local role authenticated;
select pg_temp.assert_true(not public.steward_access(), 'authentication or editable metadata granted stewardship');
do $$ declare t text; visible integer; begin
  foreach t in array array['applications','members','affiliations','contributions','contribution_members','review_events'] loop
    execute format('select count(*) from public.%I', t) into visible;
    if visible <> 0 then raise exception 'non-steward read %', t; end if;
  end loop;
  begin update private.steward_roles set active=true; raise exception 'user granted their own role'; exception when insufficient_privilege then null; end;
end $$;
reset role;

set local request.jwt.claims = '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"92000000-0000-4000-8000-000000000001"}';
set local role authenticated;
select pg_temp.assert_true(public.steward_access(), 'active steward denied');
select pg_temp.assert_true((select original_answers->>'constraints' = 'private synthetic answer' from public.applications where id='94000000-0000-4000-8000-000000000001'), 'private answers inaccessible');
select pg_temp.assert_true((select count(*)=1 from public.affiliations where member_id='93000000-0000-4000-8000-000000000001'), 'affiliation lost');
select pg_temp.assert_true((select count(*)=1 from public.contribution_members where member_id='93000000-0000-4000-8000-000000000001'), 'contributor relation lost');
select pg_temp.assert_true((select count(*)=1 from public.review_events where application_id='94000000-0000-4000-8000-000000000001'), 'history inaccessible');
do $$ begin
  begin update public.members set publication_state='published'; raise exception 'steward published without authority'; exception when insufficient_privilege then null; end;
  begin update public.applications set review_state='accepted'; raise exception 'steward accepted without authority'; exception when insufficient_privilege then null; end;
  begin insert into private.steward_roles(user_id,active) values ('91000000-0000-4000-8000-000000000002',true); raise exception 'steward granted roles'; exception when insufficient_privilege then null; end;
end $$;
reset role;

update private.steward_roles set active=false where user_id='91000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.assert_true(not public.steward_access(), 'revoked role still has access');
select pg_temp.assert_true((select count(*)=0 from public.applications), 'revoked role bypassed RLS');
reset role;
update private.steward_roles set active=true where user_id='91000000-0000-4000-8000-000000000001';
set local request.jwt.claims = '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"92000000-0000-4000-8000-000000000003"}';
set local role authenticated;
select pg_temp.assert_true(not public.steward_access(), 'expired session still has access');
select pg_temp.assert_true((select count(*)=0 from public.applications), 'expired session bypassed RLS');
reset role;
set local request.jwt.claims = '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"92000000-0000-4000-8000-000000000001"}';
delete from auth.sessions where id='92000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.assert_true(not public.steward_access(), 'revoked session still has access');
select pg_temp.assert_true((select count(*)=0 from public.applications), 'revoked session bypassed RLS');
reset role;
rollback;
select 'PASS: anon, visitor, metadata spoofing, active steward, relationships, decision writes, role revocation, session expiry/revocation; all synthetic data rolled back' as result;
