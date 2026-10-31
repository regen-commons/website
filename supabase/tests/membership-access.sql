-- Disposable database only. Synthetic records and all mutations roll back.
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void
language plpgsql as $$ begin if ok is distinct from true then raise exception '%',message; end if; end $$;
create function pg_temp.expect_error(statement text,expected text) returns void
language plpgsql as $$ begin
  begin execute statement;
  exception when others then if sqlstate=expected then return; end if; raise; end;
  raise exception 'Expected SQLSTATE %',expected;
end $$;
insert into auth.users(id,email,raw_user_meta_data) values
 ('a1000000-0000-4000-8000-000000000001','membership-steward@example.test','{}'),
 ('a1000000-0000-4000-8000-000000000002','membership-visitor@example.test','{"steward":true}');
insert into auth.sessions(id,user_id,not_after) values
 ('a2000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001',now()+interval '1 hour'),
 ('a2000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002',now()+interval '1 hour');
insert into private.steward_roles(user_id,active) values('a1000000-0000-4000-8000-000000000001',true);
insert into public.members(id,name,member_type,publication_state) values
 ('a3000000-0000-4000-8000-000000000001','Original synthetic person','individual','published'),
 ('a3000000-0000-4000-8000-000000000002','Synthetic organization','organization','published');
insert into public.applications(id,display_name,applicant_type,email,original_answers,member_id) values
 ('a4000000-0000-4000-8000-000000000001','Synthetic applicant','individual','person@example.test','{"constraints":"private original evidence"}','a3000000-0000-4000-8000-000000000001'),
 ('a4000000-0000-4000-8000-000000000002','Synthetic org applicant','organization','org@example.test','{"org-description":"Private organization answer"}',null);
-- Boundaries: no direct writes, no public standing/history, no self-granted authority.
set local role anon;
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{}')$q$,'42501');
select pg_temp.expect_error($q$select membership_status from public.members$q$,'42501');
select pg_temp.expect_error($q$select * from public.member_events$q$,'42501');
reset role;
set local request.jwt.claims='{"sub":"a1000000-0000-4000-8000-000000000002","session_id":"a2000000-0000-4000-8000-000000000002","role":"authenticated","user_metadata":{"steward":true}}';
set local role authenticated;
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{}')$q$,'PT403');
select pg_temp.assert_true((select count(*)=0 from public.member_events),'visitor read member history');
reset role;
set local request.jwt.claims='{"sub":"a1000000-0000-4000-8000-000000000001","session_id":"a2000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select pg_temp.expect_error($q$update public.members set membership_status='active'$q$,'42501');
select pg_temp.expect_error($q$update public.applications set review_state='approved'$q$,'42501');
select pg_temp.expect_error($q$update public.member_events set reason='rewritten'$q$,'42501');
select pg_temp.expect_error($q$select * from private.membership_requests$q$,'42501');

-- Approval neither activates nor publishes; replay is exactly once.
select public.membership_command('a5000000-0000-4000-8000-000000000001',
 '{"action":"review-application","id":"a4000000-0000-4000-8000-000000000001","revision":1,"state":"approved","reason":"Reviewed this exact revision"}');
select public.membership_command('a5000000-0000-4000-8000-000000000001',
 '{"action":"review-application","id":"a4000000-0000-4000-8000-000000000001","revision":1,"state":"approved","reason":"Reviewed this exact revision"}');
select pg_temp.assert_true((select review_state='approved' and revision=2 and original_answers->>'constraints'='private original evidence' from public.applications where id='a4000000-0000-4000-8000-000000000001'),'approval corrupted evidence');
select pg_temp.assert_true((select membership_status='unconfirmed' and publication_state='published' and revision=1 from public.members where id='a3000000-0000-4000-8000-000000000001'),'approval changed membership or visibility');
select pg_temp.assert_true((select count(*)=1 from public.review_events where application_id='a4000000-0000-4000-8000-000000000001'),'replay recorded two decisions');
select pg_temp.assert_true((select reviewed_revision=1 and resulting_revision=2 and actor_label='membership-steward@example.test' from public.review_events where application_id='a4000000-0000-4000-8000-000000000001'),'decision lacks exact revision or actor');
select pg_temp.expect_error($q$select public.membership_command('a5000000-0000-4000-8000-000000000001','{"action":"review-application","id":"a4000000-0000-4000-8000-000000000001","revision":1,"state":"declined","reason":"Different"}')$q$,'PT409');
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{"action":"review-application","id":"a4000000-0000-4000-8000-000000000001","revision":1,"state":"approved","reason":"Stale"}')$q$,'PT409');
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{"action":"review-application","id":"a4000000-0000-4000-8000-000000000001","revision":2,"state":"declined","reason":"Must reopen"}')$q$,'PT409');
select public.membership_command(gen_random_uuid(),'{"action":"review-application","id":"a4000000-0000-4000-8000-000000000001","revision":2,"state":"pending","reason":"Reopen deliberately"}');
select public.membership_command(gen_random_uuid(),'{"action":"review-application","id":"a4000000-0000-4000-8000-000000000001","revision":3,"state":"changes_requested","reason":"Need clarification"}');
select public.membership_command(gen_random_uuid(),'{"action":"review-application","id":"a4000000-0000-4000-8000-000000000001","revision":4,"state":"declined","reason":"Record separate decision"}');

-- Independent member commands and conflicting profile edits.
select public.membership_command(gen_random_uuid(),'{"action":"set-membership-status","id":"a3000000-0000-4000-8000-000000000001","revision":1,"state":"active","reason":"Explicitly confirmed standing"}');
select public.membership_command(gen_random_uuid(),'{"action":"set-profile-visibility","id":"a3000000-0000-4000-8000-000000000001","revision":2,"state":"hidden","reason":"Visibility only"}');
select public.membership_command(gen_random_uuid(),'{"action":"set-membership-status","id":"a3000000-0000-4000-8000-000000000001","revision":3,"state":"paused","reason":"Standing only"}');
select pg_temp.assert_true((select membership_status='paused' and publication_state='hidden' and revision=4 from public.members where id='a3000000-0000-4000-8000-000000000001'),'standing and visibility coupled');
select pg_temp.assert_true((select review_state='declined' from public.applications where id='a4000000-0000-4000-8000-000000000001'),'member command changed application');
select public.membership_command(gen_random_uuid(),'{"action":"save-profile","id":"a3000000-0000-4000-8000-000000000001","revision":4,"reason":"Curated fields","payload":{"name":"Updated synthetic person","member_type":"individual","location":"Demo region","summary":"Curated summary","vision":"Public vision","website":"https://example.test","avatar":"","focus_areas":["Care"],"contribution_areas":[],"organization_ids":["a3000000-0000-4000-8000-000000000002"]}}');
select pg_temp.assert_true((select membership_status='paused' and publication_state='hidden' and name='Updated synthetic person' and revision=5 from public.members where id='a3000000-0000-4000-8000-000000000001'),'profile edit changed other states');
select pg_temp.assert_true((select count(*)=1 from public.affiliations where member_id='a3000000-0000-4000-8000-000000000001'),'affiliation missing');
select pg_temp.assert_true((select changes->'before'->'profile'->>'name'='Original synthetic person' and changes->'after'->'profile'->>'name'='Updated synthetic person' from public.member_events where member_id='a3000000-0000-4000-8000-000000000001' and event_type='profile_updated'),'missing before/after evidence');
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{"action":"set-profile-visibility","id":"a3000000-0000-4000-8000-000000000001","revision":4,"state":"published","reason":"Stale"}')$q$,'PT409');
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{"action":"set-membership-status","id":"a3000000-0000-4000-8000-000000000001","revision":5,"state":"active","reason":"  "}')$q$,'PT400');
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{"action":"set-membership-status","id":"a3000000-0000-4000-8000-000000000001","revision":5,"state":"active","reason":"No role grant","grant_role":true}')$q$,'PT400');
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{"action":"link-profile","id":"a4000000-0000-4000-8000-000000000001","revision":5,"member_id":"a3000000-0000-4000-8000-000000000002","reason":"Type mismatch"}')$q$,'PT400');

-- Explicit profile creation/linking remains draft and unconfirmed, without copying answers.
do $$
declare
 command jsonb:='{"action":"save-profile","id":"a3000000-0000-4000-8000-000000000001","revision":5,"reason":"Direct RPC validation","payload":{"name":"Updated synthetic person","member_type":"individual","location":"","summary":"","vision":"","website":"","avatar":"","focus_areas":[],"contribution_areas":[],"organization_ids":[]}}';
 patch jsonb;
begin
 for patch in select value from jsonb_array_elements(jsonb_build_array(
   '{"member_type":"organization"}'::jsonb,
   '{"avatar":"data:text/html,unsafe"}'::jsonb,
   '{"focus_areas":[null]}'::jsonb,
   jsonb_build_object('vision',repeat('🌱',2501))
 )) loop
   begin
     perform public.membership_command(gen_random_uuid(),jsonb_set(command,'{payload}',command->'payload'||patch));
     raise exception 'Invalid direct RPC profile accepted';
   exception when sqlstate 'PT400' then null; end;
 end loop;
end $$;
select public.membership_command('a5000000-0000-4000-8000-000000000002','{"action":"save-profile","application_id":"a4000000-0000-4000-8000-000000000002","application_revision":1,"reason":"Explicit curated draft","payload":{"name":"New curated organization","member_type":"organization","location":"","summary":"","vision":"","website":"","avatar":"","focus_areas":[],"contribution_areas":[],"organization_ids":[]}}');
select public.membership_command('a5000000-0000-4000-8000-000000000002','{"action":"save-profile","application_id":"a4000000-0000-4000-8000-000000000002","application_revision":1,"reason":"Explicit curated draft","payload":{"name":"New curated organization","member_type":"organization","location":"","summary":"","vision":"","website":"","avatar":"","focus_areas":[],"contribution_areas":[],"organization_ids":[]}}');
select pg_temp.assert_true((select count(*)=1 from public.members where name='New curated organization'),'duplicate profile created');
select pg_temp.assert_true((select a.review_state='pending' and a.revision=2 and m.publication_state='draft' and m.membership_status='unconfirmed' and m.vision='' from public.applications a join public.members m on m.id=a.member_id where a.id='a4000000-0000-4000-8000-000000000002'),'draft creation implied approval or copied answers');
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{"action":"save-profile","reason":"Cannot mass assign","payload":{"name":"Bad profile","member_type":"individual","location":"","summary":"","vision":"","website":"","avatar":"","focus_areas":[],"contribution_areas":[],"organization_ids":[],"publication_state":"published"}}')$q$,'PT400');
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{"action":"save-profile","reason":"Unsafe URL","payload":{"name":"Bad profile","member_type":"individual","location":"","summary":"","vision":"","website":"javascript:alert(1)","avatar":"","focus_areas":[],"contribution_areas":[],"organization_ids":[]}}')$q$,'PT400');
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{"action":"save-profile","reason":"Bad affiliation","payload":{"name":"Bad profile","member_type":"individual","location":"","summary":"","vision":"","website":"","avatar":"","focus_areas":[],"contribution_areas":[],"organization_ids":["a3000000-0000-4000-8000-000000000001"]}}')$q$,'PT400');
reset role;
select pg_temp.assert_true((select count(*)=0 from private.notification_jobs),'membership commands queued messages');
select pg_temp.assert_true((select count(*)=1 from private.steward_roles),'membership commands granted access');
set local role anon;
select pg_temp.assert_true((select count(*)=0 from public.website_members where name in ('Updated synthetic person','New curated organization')),'hidden or draft profile leaked');
reset role;
-- Revocation also blocks replay of previously successful commands.
update private.steward_roles set active=false where user_id='a1000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.expect_error($q$select public.membership_command('a5000000-0000-4000-8000-000000000001','{}')$q$,'PT403');
reset role;
update private.steward_roles set active=true where user_id='a1000000-0000-4000-8000-000000000001';
update auth.sessions set not_after=now()-interval '1 minute' where id='a2000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{}')$q$,'PT403');
reset role;
delete from auth.sessions where id='a2000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.expect_error($q$select public.membership_command(gen_random_uuid(),'{}')$q$,'PT403');
reset role;
rollback;
select 'PASS: independent states, private evidence, audit, replay, stale revisions, creation/linking, boundaries and revocation' as result;
