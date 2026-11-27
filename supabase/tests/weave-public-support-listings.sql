-- Disposable database only; synthetic projects and listings, and all fixture rows roll back.
-- private.weave_public_support_listings shows only confirmed, open, unexpired listings for exactly
-- one project, from a link that is not paused, and only weave_index_job may run it.
begin;
create function pg_temp.assert_listings(ok boolean, message text) returns void
language plpgsql as $$ begin if ok is distinct from true then raise exception '%', message; end if; end $$;

select pg_temp.assert_listings(not (select r.rolsuper from pg_proc p join pg_roles r on r.oid = p.proowner
  where p.oid = 'private.weave_public_support_listings(text)'::regprocedure),
  'migration replay must create the public listings read under a non-superuser');
select pg_temp.assert_listings(has_function_privilege('weave_index_job',
  'private.weave_public_support_listings(text)', 'execute'), 'the index job must be able to read listings');
select pg_temp.assert_listings(not has_function_privilege(r, 'private.weave_public_support_listings(text)', 'execute'),
  r || ' must not be able to read listings')
  from unnest(array['anon', 'authenticated', 'service_role', 'weave_workspace_runtime']) r;
select pg_temp.assert_listings(not exists(select from information_schema.routine_privileges
  where specific_schema = 'private' and routine_name = 'weave_public_support_listings' and grantee = 'PUBLIC'),
  'PUBLIC must not be able to read listings');

insert into auth.users(id) values('d1000000-0000-4000-8000-000000000001');
insert into weave_workspace.project_links(id, project_uri, repository_did, group_did, cid, linked_by) values
  ('d3000000-0000-4000-8000-000000000001',
   'at://did:plc:dddddddddddddddddddddddd/org.hypercerts.collection/listing-fixture',
   'did:plc:dddddddddddddddddddddddd', 'did:plc:dddddddddddddddddddddddd', 'bafyfixture',
   'd1000000-0000-4000-8000-000000000001'),
  ('d3000000-0000-4000-8000-000000000002',
   'at://did:plc:eeeeeeeeeeeeeeeeeeeeeeee/org.hypercerts.collection/paused-fixture',
   'did:plc:eeeeeeeeeeeeeeeeeeeeeeee', 'did:plc:eeeeeeeeeeeeeeeeeeeeeeee', 'bafyfixture',
   'd1000000-0000-4000-8000-000000000001');
update weave_workspace.project_links set matching_paused = true where id = 'd3000000-0000-4000-8000-000000000002';

-- Each row is one case. Only the first two are current.
with cases(n, kind, rkey, status, cid, record) as (values
  (1, 'need', '3aaaaaaaaaaaa', 'published', 'b' || repeat('a', 58), '{}'::jsonb),
  (2, 'offer', '3aaaaaaaaaaab', 'published', 'b' || repeat('b', 58), '{"expiresAt":"2999-01-01T00:00:00.000Z"}'),
  (3, 'need', '3aaaaaaaaaaac', 'published', 'b' || repeat('c', 58), '{"expiresAt":"2000-01-01T00:00:00.000Z"}'),
  (4, 'need', '3aaaaaaaaaaad', 'publish_pending', null, '{}'),
  (5, 'need', '3aaaaaaaaaaae', 'withdrawn', 'b' || repeat('e', 58), '{}'),
  (6, 'need', '3aaaaaaaaaaaf', 'withdrawal_pending', 'b' || repeat('f', 58), '{}'),
  (7, 'need', '3aaaaaaaaaaag', 'published', 'b' || repeat('g', 58), '{"status":"met"}'),
  (8, 'need', '3aaaaaaaaaaah', 'published', 'b' || repeat('h', 58),
     '{"projectUri":"at://did:plc:dddddddddddddddddddddddd/org.hypercerts.collection/other-fixture"}'),
  (9, 'need', '3aaaaaaaaaaai', 'published', null, '{}'),
  (10, 'need', '3aaaaaaaaaaaj', 'published', 'b' || repeat('j', 58), '{"kind":"offer"}'),
  (11, 'need', '3aaaaaaaaaaak', 'published', 'b' || repeat('k', 58), '{"expiresAt":"tomorrow"}'),
  (12, 'need', '3aaaaaaaaaaal', 'conflict', 'b' || repeat('l', 58), '{}')
)
insert into weave_workspace.support_listings(workspace_id, kind, entry_id, rkey, operation_id, actor_id,
  entry_revision, record_value, status, cid)
select 'd3000000-0000-4000-8000-000000000001', kind,
  ('d4000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, rkey,
  ('d5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'd1000000-0000-4000-8000-000000000001', 1,
  jsonb_build_object('$type', 'com.regencommons.weave.supportListing',
    'projectUri', 'at://did:plc:dddddddddddddddddddddddd/org.hypercerts.collection/listing-fixture',
    'kind', kind, 'title', 'Fixture ' || n, 'capitalForms', jsonb_build_array('social'), 'status', 'open',
    'createdAt', '2026-11-01T00:00:00.000Z') || record,
  status, cid
from cases;
insert into weave_workspace.support_listings(workspace_id, kind, entry_id, rkey, operation_id, actor_id,
  entry_revision, record_value, status, cid) values
  ('d3000000-0000-4000-8000-000000000002', 'need', 'd4000000-0000-4000-8000-000000000099', '3aaaaaaaaaaam',
   'd5000000-0000-4000-8000-000000000099', 'd1000000-0000-4000-8000-000000000001', 1,
   jsonb_build_object('$type', 'com.regencommons.weave.supportListing',
     'projectUri', 'at://did:plc:eeeeeeeeeeeeeeeeeeeeeeee/org.hypercerts.collection/paused-fixture',
     'kind', 'need', 'title', 'Paused', 'capitalForms', jsonb_build_array('social'), 'status', 'open',
     'createdAt', '2026-11-01T00:00:00.000Z'),
   'published', 'b' || repeat('m', 58));

set local role weave_index_job;
select pg_temp.assert_listings((select array_agg(rkey order by rkey) from private.weave_public_support_listings(
  'at://did:plc:dddddddddddddddddddddddd/org.hypercerts.collection/listing-fixture'))
  = array['3aaaaaaaaaaaa', '3aaaaaaaaaaab'],
  'only confirmed, open, unexpired listings for exactly this project may be shown');
select pg_temp.assert_listings((select uri = 'at://did:plc:dddddddddddddddddddddddd/com.regencommons.weave.supportListing/3aaaaaaaaaaaa'
    and cid = 'b' || repeat('a', 58) and kind = 'need' and record->>'title' = 'Fixture 1'
  from private.weave_public_support_listings(
    'at://did:plc:dddddddddddddddddddddddd/org.hypercerts.collection/listing-fixture') where rkey = '3aaaaaaaaaaaa'),
  'a listing must carry its public address, version and record');
select pg_temp.assert_listings(not exists(select from private.weave_public_support_listings(
  'at://did:plc:eeeeeeeeeeeeeeeeeeeeeeee/org.hypercerts.collection/paused-fixture')),
  'a paused project link must show no listings');
select pg_temp.assert_listings(not exists(select from private.weave_public_support_listings(
  'at://did:plc:dddddddddddddddddddddddd/org.hypercerts.collection/other-fixture')),
  'a project with no link must show no listings');
reset role;

set local role weave_workspace_runtime;
do $$ begin
  begin
    perform private.weave_public_support_listings(
      'at://did:plc:dddddddddddddddddddddddd/org.hypercerts.collection/listing-fixture');
    raise exception 'the workspace runtime read public listings';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

rollback;
