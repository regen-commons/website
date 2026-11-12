-- Disposable database only; synthetic identities and all fixture rows roll back.
begin;
create function pg_temp.assert_context(ok boolean,message text) returns void
language plpgsql as $$ begin if ok is distinct from true then raise exception '%',message; end if; end $$;
select pg_temp.assert_context(not (select r.rolsuper from pg_proc p join pg_roles r on r.oid=p.proowner
  where p.oid='weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)'::regprocedure),
  'migration replay must create the team command under a non-superuser');

insert into auth.users(id) values('c1000000-0000-4000-8000-000000000001');
insert into auth.sessions(id,user_id) values('c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001');
insert into auth.identities(user_id,provider,provider_id) values
  ('c1000000-0000-4000-8000-000000000001','custom:certified','https://certified.one|did:plc:aaaaaaaaaaaaaaaaaaaaaaaa');
insert into weave_workspace.project_links(id,project_uri,repository_did,group_did,cid,linked_by) values
  ('c3000000-0000-4000-8000-000000000001',
   'at://did:plc:cccccccccccccccccccccccc/org.hypercerts.collection/context-fixture',
   'did:plc:cccccccccccccccccccccccc','did:plc:cccccccccccccccccccccccc','bafyfixture','c1000000-0000-4000-8000-000000000001');
insert into weave_workspace.access_grants(workspace_id,user_id,member_did,access_role) values
  ('c3000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','did:plc:aaaaaaaaaaaaaaaaaaaaaaaa','admin');

set local request.jwt.claims='{"proof":"caller-context"}';
set local request.jwt.claim.sub='caller-sub-context';
set local role weave_workspace_runtime;
select pg_temp.assert_context((weave_workspace.content_command(
  'c1000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001',
  'did:plc:aaaaaaaaaaaaaaaaaaaaaaaa','c3000000-0000-4000-8000-000000000001',
  'owner',null,'team_load','{}'))->>'accessRole'='admin','team read failed');
select pg_temp.assert_context(current_setting('request.jwt.claims',true)='{"proof":"caller-context"}'
  and current_setting('request.jwt.claim.sub',true)='caller-sub-context','successful command leaked actor context');

do $$ begin
  begin
    perform weave_workspace.content_command(
      'c1000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001',
      'did:plc:aaaaaaaaaaaaaaaaaaaaaaaa','c3000000-0000-4000-8000-000000000001',
      'owner',null,'team_save','{}');
    raise exception 'invalid save unexpectedly succeeded';
  exception when sqlstate 'PT400' then null; end;
end $$;
select pg_temp.assert_context(current_setting('request.jwt.claims',true)='{"proof":"caller-context"}'
  and current_setting('request.jwt.claim.sub',true)='caller-sub-context','rejected command leaked actor context');

select set_config('request.jwt.claims','',true),set_config('request.jwt.claim.sub','',true);
select weave_workspace.content_command(
  'c1000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001',
  'did:plc:aaaaaaaaaaaaaaaaaaaaaaaa','c3000000-0000-4000-8000-000000000001',
  'owner',null,'team_load','{}');
select pg_temp.assert_context(nullif(current_setting('request.jwt.claims',true),'') is null
  and nullif(current_setting('request.jwt.claim.sub',true),'') is null,'empty context gained actor authority');
reset role;
rollback;
