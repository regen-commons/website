-- Disposable database only; synthetic identities, projects, index rows and listings, and all fixture rows roll back.
-- DL-155, step 5: matching reads published listings. Two people's published needs and offers find each other
-- through the workspace runtime's listing_shortlist; what is not current, not shown in the public list, paused,
-- or in the person's own repository never appears; a viewer may search and an outsider may not; the device's
-- snapshot carries other projects' listings; and the public initiative read and the rest of content_command are
-- unchanged.
begin;
create function pg_temp.assert_listing_match(ok boolean, message text) returns void
language plpgsql as $$ begin if ok is distinct from true then raise exception '%', message; end if; end $$;
-- The refusal a statement meets, as `sqlstate message`, or `accepted`.
create function pg_temp.refusal(p_statement text) returns text
language plpgsql as $$
begin
  execute p_statement;
  return 'accepted';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

-- Grants and owners. The new reads run only inside definer functions; nobody calls them directly.
select pg_temp.assert_listing_match(not r.rolsuper, p.oid::regprocedure::text || ' must be created under a non-superuser')
  from pg_proc p join pg_roles r on r.oid = p.proowner
  where p.oid in ('private.weave_current_support_listings(text)'::regprocedure,
    'private.weave_shown_projects()'::regprocedure, 'private.weave_listing_terms(jsonb)'::regprocedure,
    'private.weave_listing_query_terms(jsonb)'::regprocedure,
    'private.weave_listing_shortlist(uuid)'::regprocedure, 'private.weave_public_project_snapshot(text)'::regprocedure,
    'private.weave_public_support_listings(text)'::regprocedure,
    'weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)'::regprocedure);
select pg_temp.assert_listing_match(not has_function_privilege(r, f, 'execute'), r || ' must not run ' || f)
  from unnest(array['anon', 'authenticated', 'service_role', 'weave_workspace_runtime', 'weave_index_job']) r,
    unnest(array['private.weave_current_support_listings(text)', 'private.weave_shown_projects()',
      'private.weave_listing_terms(jsonb)', 'private.weave_listing_query_terms(jsonb)', 'private.weave_listing_shortlist(uuid)',
      'private.weave_public_project_snapshot(text)']) f;
select pg_temp.assert_listing_match(not exists(select from information_schema.routine_privileges
  where specific_schema = 'private' and routine_name in ('weave_current_support_listings', 'weave_shown_projects',
    'weave_listing_terms', 'weave_listing_query_terms', 'weave_listing_shortlist', 'weave_public_project_snapshot') and grantee = 'PUBLIC'),
  'PUBLIC must not run the listing reads');
select pg_temp.assert_listing_match(has_function_privilege('weave_index_job', 'private.weave_public_support_listings(text)', 'execute')
  and not has_function_privilege('weave_workspace_runtime', 'private.weave_public_support_listings(text)', 'execute'),
  'the public listings read must keep its grants');
select pg_temp.assert_listing_match(has_function_privilege('weave_workspace_runtime',
    'weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)', 'execute'),
  'content_command must keep its grants');
-- content_command is weave-team-content's, with one new line. The hash is of that command as Platform held it on
-- 27 November 2026, which this replay reproduces.
select pg_temp.assert_listing_match(md5(replace(pg_get_functiondef(
    'weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)'::regprocedure),
    E'      when ''listing_shortlist'' then result := private.weave_listing_shortlist(p_id);\n', ''))
  = '5923a0dc0a097363bee2b1cf9b67f6b7', 'content_command must be unchanged apart from listing_shortlist');
-- The new reads take public records only: no saved card, share, draft or matching state.
select pg_temp.assert_listing_match(pg_get_functiondef(f) !~ 'weave\.(needs|offers|initiatives)|matching_(audience|withdrawn|reviews|leads|requests)',
  f::text || ' must not read saved cards or shares')
  from unnest(array['private.weave_current_support_listings(text)'::regprocedure, 'private.weave_listing_shortlist(uuid)'::regprocedure,
    'private.weave_public_project_snapshot(text)'::regprocedure, 'private.weave_shown_projects()'::regprocedure]) f;

-- Ana and Ben each publish from a personal project; Cleo is someone else. Ana's second project lives in her own
-- repository. A group project lists Ana as a viewer. One project is not in the public list, one has dropped out of
-- it, and one link is paused.
insert into auth.users(id, email_confirmed_at) values
  ('a1000000-0000-4000-8000-000000000001', now()), ('a1000000-0000-4000-8000-000000000002', now()),
  ('a1000000-0000-4000-8000-000000000003', now());
insert into auth.sessions(id, user_id) values
  ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001'),
  ('a2000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000002'),
  ('a2000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000003');
insert into auth.identities(user_id, provider, provider_id) values
  ('a1000000-0000-4000-8000-000000000001', 'custom:certified', 'https://certified.one|did:plc:anaaaaaaaaaaaaaaaaaaaaaa'),
  ('a1000000-0000-4000-8000-000000000002', 'custom:certified', 'https://certified.one|did:plc:benbbbbbbbbbbbbbbbbbbbbb'),
  ('a1000000-0000-4000-8000-000000000003', 'custom:certified', 'https://certified.one|did:plc:cleocccccccccccccccccccc');

create function pg_temp.project(p_n integer) returns text language sql immutable as $$
  select case p_n
    when 1 then 'at://did:plc:anaaaaaaaaaaaaaaaaaaaaaa/org.hypercerts.collection/3mlistingana1'
    when 2 then 'at://did:plc:anaaaaaaaaaaaaaaaaaaaaaa/org.hypercerts.collection/3mlistingana2'
    when 3 then 'at://did:plc:benbbbbbbbbbbbbbbbbbbbbb/org.hypercerts.collection/3mlistingben1'
    when 4 then 'at://did:plc:grpgggggggggggggggggggggg/org.hypercerts.collection/3mlistinggrp1'
    when 5 then 'at://did:plc:hidhhhhhhhhhhhhhhhhhhhhh/org.hypercerts.collection/3mlistinghid1'
    when 6 then 'at://did:plc:oldoooooooooooooooooooooo/org.hypercerts.collection/3mlistingold1'
    when 7 then 'at://did:plc:pauppppppppppppppppppppp/org.hypercerts.collection/3mlistingpau1'
    when 8 then 'at://did:plc:faiffffffffffffffffffffff/org.hypercerts.collection/3mlistingfai1'
    when 9 then 'at://did:plc:stassssssssssssssssssssss/org.hypercerts.collection/3mlistingsta1'
    when 10 then 'at://did:plc:cidcccccccccccccccccccccc/org.hypercerts.collection/3mlistingcid1'
  end $$;
create function pg_temp.link(p_n integer) returns uuid language sql immutable as $$
  select ('a3000000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid $$;
insert into weave_workspace.project_links(id, project_uri, repository_did, group_did, cid, linked_by)
select pg_temp.link(n), pg_temp.project(n), split_part(pg_temp.project(n), '/', 3),
  case when n >= 4 then split_part(pg_temp.project(n), '/', 3) end, 'bafyfixture',
  'a1000000-0000-4000-8000-000000000001'
from generate_series(1, 10) n;
update weave_workspace.project_links set matching_paused = true where id = pg_temp.link(7);
insert into weave_workspace.access_grants(workspace_id, user_id, member_did, access_role) values
  (pg_temp.link(4), 'a1000000-0000-4000-8000-000000000001', 'did:plc:anaaaaaaaaaaaaaaaaaaaaaa', 'viewer');

-- The public list shows projects 1 to 4 and 7. Project 5 was never indexed, project 6's listing permission
-- lapsed, project 8's last read failed, project 9 was last read eight days ago, and project 10's only passage
-- is from an older version of its record.
insert into private.weave_project_index_source(project_uri, status, permission_until, cid, checked_at, fetched_at)
select pg_temp.project(n), case when n = 8 then 'failed' else 'indexed' end,
  now() + case when n = 6 then interval '-1 day' else interval '2 days' end,
  'bafyindex' || n, now(), now() - case when n = 9 then interval '8 days' else interval '0' end
from unnest(array[1, 2, 3, 4, 6, 7, 8, 9, 10]) n;
insert into private.weave_project_index_evidence(id, project_uri, evidence, lexical_text)
select 'evidence-' || n, pg_temp.project(n),
  jsonb_build_object('id', 'evidence-' || n, 'projectUri', pg_temp.project(n),
    'cid', case when n = 10 then 'bafyolder' else 'bafyindex' || n end,
    'projectName', 'Fictional project ' || n, 'passage', 'A fictional seed library and compost commons ' || n),
  'Fictional project ' || n || ' seed library compost commons'
from unnest(array[1, 2, 3, 4, 6, 7, 8, 9, 10]) n;

-- Listings, as support_command leaves them once read back. Each row is one case.
with cases(n, link, kind, title, status, cid, record) as (values
  -- Ana's project: a need and an offer, both current.
  (1, 1, 'need', 'Volunteers for our seed library', 'published', 'b' || repeat('a', 58), '{}'::jsonb),
  (2, 1, 'offer', 'Compost training for neighbours', 'published', 'b' || repeat('b', 58), '{}'),
  -- Ana's second project, in her own repository: never matched to her.
  (3, 2, 'offer', 'Seed library volunteers on weekends', 'published', 'b' || repeat('c', 58), '{}'),
  -- Ben's project: the two that should find Ana, then the ones that must not appear.
  (4, 3, 'offer', 'Weekend volunteers for a seed library', 'published', 'b' || repeat('d', 58), '{}'),
  (5, 3, 'need', 'Compost training for a school garden', 'published', 'b' || repeat('e', 58), '{}'),
  (6, 3, 'offer', 'Seed library shelving, still pending', 'publish_pending', null, '{}'),
  (7, 3, 'offer', 'Seed library sorting, withdrawn', 'withdrawn', 'b' || repeat('g', 58), '{}'),
  (8, 3, 'offer', 'Seed library labels, withdrawing', 'withdrawal_pending', 'b' || repeat('h', 58), '{}'),
  (9, 3, 'offer', 'Seed library catalogue, in conflict', 'conflict', 'b' || repeat('i', 58), '{}'),
  (10, 3, 'offer', 'Seed library volunteers, expired', 'published', 'b' || repeat('j', 58), '{"expiresAt":"2000-01-01T00:00:00.000Z"}'),
  (11, 3, 'offer', 'Seed library volunteers, bad expiry', 'published', 'b' || repeat('k', 58), '{"expiresAt":"tomorrow"}'),
  (12, 3, 'offer', 'Seed library volunteers, met', 'published', 'b' || repeat('l', 58), '{"status":"met"}'),
  (13, 3, 'offer', 'Seed library volunteers, wrong project', 'published', 'b' || repeat('m', 58),
     '{"projectUri":"at://did:plc:benbbbbbbbbbbbbbbbbbbbbb/org.hypercerts.collection/3mlistingben9"}'),
  -- Ben's offer that shares no word of three letters or more with Ana's need.
  (14, 3, 'offer', 'Bike repair', 'published', 'b' || repeat('n', 58), '{"description":"Fix a flat"}'),
  -- The group's offer, the hidden project's, the lapsed project's and the paused project's.
  (15, 4, 'offer', 'Seed library volunteers from the group', 'published', 'b' || repeat('o', 58), '{}'),
  (16, 5, 'offer', 'Seed library volunteers, unlisted project', 'published', 'b' || repeat('p', 58), '{}'),
  (17, 6, 'offer', 'Seed library volunteers, lapsed project', 'published', 'b' || repeat('q', 58), '{}'),
  (18, 7, 'offer', 'Seed library volunteers, paused project', 'published', 'b' || repeat('r', 58), '{}'),
  -- Offers from projects the public list does not show: a failed read, a stale read, an older record's passage.
  (19, 8, 'offer', 'Seed library volunteers, failed read', 'published', 'b' || repeat('s', 58), '{}'),
  (20, 9, 'offer', 'Seed library volunteers, stale read', 'published', 'b' || repeat('t', 58), '{}'),
  (21, 10, 'offer', 'Seed library volunteers, older passage', 'published', 'b' || repeat('u', 58), '{}'),
  -- Ben's damaged records: an expiry of the right shape that is no real time, other digits, another type. None
  -- may appear, and none may fail a read.
  (22, 3, 'offer', 'Seed library volunteers, impossible expiry', 'published', 'b' || repeat('v', 58), '{"expiresAt":"2026-02-30T00:00:00Z"}'),
  (23, 3, 'offer', 'Seed library volunteers, year zero', 'published', 'b' || repeat('w', 58), '{"expiresAt":"0000-01-01T00:00:00Z"}'),
  (24, 3, 'offer', 'Seed library volunteers, other digits', 'published', 'b' || repeat('x', 58), '{"expiresAt":"٢٠٩٩-٠١-٠١T00:00:00Z"}'),
  (25, 3, 'offer', 'Seed library volunteers, another type', 'published', 'b' || repeat('y', 58), '{"$type":"app.example.other"}'),
  -- Ben's offer in words too common to show a fit: current, but it searches for nothing and nothing finds it.
  (26, 3, 'offer', 'For the people', 'published', 'b' || repeat('z', 58), '{}')
)
insert into weave_workspace.support_listings(workspace_id, kind, entry_id, rkey, operation_id, actor_id,
  entry_revision, record_value, status, cid, source, updated_at)
select pg_temp.link(link), kind, ('a4000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  '3mlst' || chr(96 + n) || 'aaaaaaa', ('a5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'a1000000-0000-4000-8000-000000000001', 0,
  jsonb_build_object('$type', 'com.regencommons.weave.supportListing', 'projectUri', pg_temp.project(link),
    'kind', kind, 'title', title, 'capitalForms', jsonb_build_array('social'),
    'status', 'open', 'createdAt', '2026-11-01T00:00:00.000Z') || record,
  status, cid, 'draft', now() - make_interval(mins => n)
from cases;

-- A person's listing search, as the Weave server sends it through the workspace runtime.
create function pg_temp.search(p_user integer, p_link integer, p_did text default null) returns jsonb language sql as $$
  select weave_workspace.content_command(('a1000000-0000-4000-8000-' || lpad(p_user::text, 12, '0'))::uuid,
    ('a2000000-0000-4000-8000-' || lpad(p_user::text, 12, '0'))::uuid,
    coalesce(p_did, case p_user when 1 then 'did:plc:anaaaaaaaaaaaaaaaaaaaaaa' when 2 then 'did:plc:benbbbbbbbbbbbbbbbbbbbbb'
      else 'did:plc:cleocccccccccccccccccccc' end),
    pg_temp.link(p_link), 'member', 'bafyfixture', 'listing_shortlist', '{}'::jsonb) $$;
-- The candidate titles a search finds for one of its listings, by title.
create function pg_temp.found(p_result jsonb, p_title text) returns text[] language sql immutable as $$
  select coalesce(array_agg(c->'record'->>'title' order by o), '{}')
  from jsonb_array_elements(p_result->'groups') g
  cross join lateral jsonb_array_elements(g->'candidates') with ordinality as x(c, o)
  where g->'listing'->'record'->>'title' = p_title $$;

set local role weave_workspace_runtime;
create temporary table ana_found on commit drop as select pg_temp.search(1, 1) as result;
create temporary table ben_found on commit drop as select pg_temp.search(2, 3) as result;
reset role;

-- 1. Two people's published entries find each other, and nothing else does.
select pg_temp.assert_listing_match((select array_agg(t order by t) from unnest(pg_temp.found(result, 'Volunteers for our seed library')) t)
  = array['Seed library volunteers from the group', 'Weekend volunteers for a seed library'],
  'Ana''s need must find Ben''s current offer and the group''s, and not her own repository''s or any that is not current or shown')
  from ana_found;
select pg_temp.assert_listing_match(pg_temp.found(result, 'Compost training for neighbours') = array['Compost training for a school garden'],
  'Ana''s offer must find Ben''s need') from ana_found;
select pg_temp.assert_listing_match(pg_temp.found(result, 'Weekend volunteers for a seed library') = array['Volunteers for our seed library'],
  'Ben''s offer must find Ana''s need') from ben_found;
select pg_temp.assert_listing_match(pg_temp.found(result, 'Bike repair') = '{}', 'a listing that shares no term must find nothing')
  from ben_found;
select pg_temp.assert_listing_match(pg_temp.found(result, 'Compost training for a school garden') = array['Compost training for neighbours'],
  'Ben''s need must find Ana''s offer') from ben_found;
-- Only Ben's current listings are his queries.
select pg_temp.assert_listing_match((select array_agg(g->'listing'->'record'->>'title' order by g->'listing'->'record'->>'title')
    from jsonb_array_elements(result->'groups') g)
  = array['Bike repair', 'Compost training for a school garden', 'For the people', 'Weekend volunteers for a seed library'],
  'only current listings may be queries') from ben_found;
select pg_temp.assert_listing_match(pg_temp.found(result, 'For the people') = '{}' and (select g->'publicEvidence' = '[]'::jsonb
    from jsonb_array_elements(result->'groups') g where g->'listing'->'record'->>'title' = 'For the people'),
  'a listing of only common words must search for nothing') from ben_found;
-- A result carries the public record, its address, version and project, and nothing private.
select pg_temp.assert_listing_match((select bool_and((select array_agg(k order by k) from jsonb_object_keys(c) k)
    = array['cid', 'kind', 'projectName', 'projectUri', 'record', 'uri'])
  from jsonb_array_elements(result->'groups') g, jsonb_array_elements(g->'candidates') c), 'a candidate must hold only public fields')
  from ana_found;
select pg_temp.assert_listing_match((select c->>'uri' = 'at://did:plc:benbbbbbbbbbbbbbbbbbbbbb/com.regencommons.weave.supportListing/3mlstdaaaaaaa'
    and c->>'cid' = 'b' || repeat('d', 58) and c->>'projectName' = 'Fictional project 3' and c->>'projectUri' = pg_temp.project(3)
  from jsonb_array_elements(result->'groups') g, jsonb_array_elements(g->'candidates') c
  where c->'record'->>'title' = 'Weekend volunteers for a seed library'), 'a candidate must carry its address, version and project name')
  from ana_found;
select pg_temp.assert_listing_match((select g->'listing'->>'entryId' = 'a4000000-0000-4000-8000-000000000001'
    and g->'listing'->>'uri' = 'at://did:plc:anaaaaaaaaaaaaaaaaaaaaaa/com.regencommons.weave.supportListing/3mlstaaaaaaaa'
  from jsonb_array_elements(result->'groups') g where g->'listing'->'record'->>'title' = 'Volunteers for our seed library'),
  'a query must name the workspace''s own entry and its public address') from ana_found;
-- Public project evidence comes back with each query, as the share search returned it.
select pg_temp.assert_listing_match((select bool_and(jsonb_array_length(g->'publicEvidence') > 0) from jsonb_array_elements(result->'groups') g),
  'each query must return the public evidence its words find') from ana_found;
select pg_temp.assert_listing_match(result ? 'externalCoverage', 'the result must carry coverage') from ana_found;

-- 2. A viewer of a group project may search: the group's published offer finds Ana's need, which lives in another
-- repository. Ana's second project's offer is a query with nothing to find: her own need is in the same repository.
set local role weave_workspace_runtime;
select pg_temp.assert_listing_match(pg_temp.found(pg_temp.search(1, 4), 'Seed library volunteers from the group')
  = array['Volunteers for our seed library'], 'a viewer must be able to search the group''s listings');
select pg_temp.assert_listing_match(jsonb_array_length(pg_temp.search(1, 2)->'groups') = 1
  and pg_temp.found(pg_temp.search(1, 2), 'Seed library volunteers on weekends') = '{}',
  'a listing must never find another listing in its own repository');
-- 3. An outsider, a forged DID and a missing link are refused.
select pg_temp.assert_listing_match(pg_temp.refusal('select pg_temp.search(3, 1)') = 'PT404 not_found',
  'someone else must not search Ana''s personal project');
select pg_temp.assert_listing_match(pg_temp.refusal('select pg_temp.search(3, 4)') = 'PT404 not_found',
  'someone with no grant must not search a group project');
select pg_temp.assert_listing_match(pg_temp.refusal($q$select pg_temp.search(3, 1, 'did:plc:anaaaaaaaaaaaaaaaaaaaaaa')$q$) = 'PT401 sign_in_required',
  'a DID that is not the session''s must be refused');
select pg_temp.assert_listing_match(pg_temp.refusal($q$select weave_workspace.content_command('a1000000-0000-4000-8000-000000000001',
    'a2000000-0000-4000-8000-000000000001', 'did:plc:anaaaaaaaaaaaaaaaaaaaaaa', 'a3000000-0000-4000-8000-000000000099', 'member',
    'bafyfixture', 'listing_shortlist', '{}'::jsonb)$q$) = 'PT404 not_found', 'a missing workspace must be refused');
-- 4. The other actions still answer as before: an unknown one is invalid, and a viewer still cannot edit.
select pg_temp.assert_listing_match(pg_temp.refusal($q$select weave_workspace.content_command('a1000000-0000-4000-8000-000000000001',
    'a2000000-0000-4000-8000-000000000001', 'did:plc:anaaaaaaaaaaaaaaaaaaaaaa', 'a3000000-0000-4000-8000-000000000001', 'member',
    'bafyfixture', 'listing_search', '{}'::jsonb)$q$) = 'PT400 invalid_data', 'an unknown action must stay invalid');
select pg_temp.assert_listing_match(pg_temp.refusal($q$select weave_workspace.content_command('a1000000-0000-4000-8000-000000000001',
    'a2000000-0000-4000-8000-000000000001', 'did:plc:anaaaaaaaaaaaaaaaaaaaaaa', 'a3000000-0000-4000-8000-000000000004', 'member',
    'bafyfixture', 'matching_set_lead', '{}'::jsonb)$q$) = 'PT403 workspace_edit_required', 'a viewer must still not edit');

-- 5. The device's snapshot carries other shown projects' current listings, and none from Ana's own repository.
create temporary table ana_snapshot on commit drop as
  select weave_workspace.content_command('a1000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001',
    'did:plc:anaaaaaaaaaaaaaaaaaaaaaa', pg_temp.link(1), 'member', 'bafyfixture', 'public_evidence', '{}'::jsonb) as result;
reset role;
select pg_temp.assert_listing_match((select array_agg(l->'record'->>'title' order by l->'record'->>'title') from jsonb_array_elements(result->'listings') l)
  = array['Bike repair', 'Compost training for a school garden', 'For the people', 'Seed library volunteers from the group',
    'Weekend volunteers for a seed library'],
  'the snapshot must hold only other shown projects'' current listings') from ana_snapshot;
select pg_temp.assert_listing_match((select bool_and((select array_agg(k order by k) from jsonb_object_keys(l) k)
    = array['cid', 'kind', 'projectName', 'projectUri', 'record', 'uri']) from jsonb_array_elements(result->'listings') l)
  and result->'listingsTruncated' = 'false'::jsonb and result->>'workspaceId' = pg_temp.link(1)::text
  and jsonb_array_length(result->'evidence') > 0, 'the snapshot must keep its evidence and hold only public listing fields')
  from ana_snapshot;

-- 6. The public initiative read returns what it returned before, for Ben's project and for the paused one.
set local role weave_index_job;
select pg_temp.assert_listing_match((select array_agg(kind || ' ' || rkey) from private.weave_public_support_listings(pg_temp.project(3)))
  = array['need 3mlsteaaaaaaa', 'offer 3mlstdaaaaaaa', 'offer 3mlstnaaaaaaa', 'offer 3mlstzaaaaaaa'],
  'the public read must show exactly Ben''s current listings, in its order');
select pg_temp.assert_listing_match(not exists(select from private.weave_public_support_listings(pg_temp.project(7))),
  'a paused project link must still show no listings');
reset role;

-- 7. Limits. A search takes the workspace's ten most recently created listings as queries, the snapshot holds at
-- most ten listings from any one project, and a suspended grant can no longer search.
insert into weave_workspace.support_listings(workspace_id, kind, entry_id, rkey, operation_id, actor_id,
  entry_revision, record_value, status, cid, source)
select pg_temp.link(link), 'need', ('a6000000-0000-4000-8000-' || lpad((link * 100 + i)::text, 12, '0'))::uuid,
  '3m' || case link when 1 then 'cap' else 'pot' end || chr(96 + i) || 'aaaaaaa',
  ('a7000000-0000-4000-8000-' || lpad((link * 100 + i)::text, 12, '0'))::uuid, 'a1000000-0000-4000-8000-000000000001', 0,
  jsonb_build_object('$type', 'com.regencommons.weave.supportListing', 'projectUri', pg_temp.project(link), 'kind', 'need',
    'title', case link when 1 then 'Later need ' else 'Pottery class ' end || i, 'capitalForms', jsonb_build_array('social'),
    'status', 'open', 'createdAt', '2026-11-' || lpad((i + 1)::text, 2, '0') || 'T00:00:00.000Z'),
  'published', 'b' || repeat(chr(96 + i), 58), 'draft'
from unnest(array[1, 4]) link, generate_series(1, 11) i;
set local role weave_workspace_runtime;
create temporary table capped on commit drop as select pg_temp.search(1, 1) as search,
  weave_workspace.content_command('a1000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001',
    'did:plc:anaaaaaaaaaaaaaaaaaaaaaa', pg_temp.link(1), 'member', 'bafyfixture', 'public_evidence', '{}'::jsonb) as snapshot;
reset role;
select pg_temp.assert_listing_match((select array_agg(g->'listing'->'record'->>'title' order by g->'listing'->'record'->>'title')
    from jsonb_array_elements(search->'groups') g)
  = (select array_agg('Later need ' || i order by 'Later need ' || i) from generate_series(2, 11) i),
  'a search must take only the ten most recently created listings') from capped;
select pg_temp.assert_listing_match((select count(*) from jsonb_array_elements(snapshot->'listings') l
    where l->>'projectUri' = pg_temp.project(4)) = 10
  and not exists(select from jsonb_array_elements(snapshot->'listings') l
    where l->'record'->>'title' in ('Pottery class 1', 'Seed library volunteers from the group')),
  'the snapshot must hold at most the ten most recent listings of one project') from capped;
update weave_workspace.access_grants set suspended_at = now(), suspension_reason = 'revoked' where workspace_id = pg_temp.link(4);
set local role weave_workspace_runtime;
select pg_temp.assert_listing_match(pg_temp.refusal('select pg_temp.search(1, 4)') = 'PT404 not_found',
  'a suspended grant must not search');
reset role;

rollback;
