-- Disposable database only; synthetic identities, cards and workspaces, and all fixture rows roll back.
-- DL-155, step 4: nothing new is saved privately or shared for matching. A personal save, a review, a
-- share and a renewal are refused by name, through a session's own token and through the workspace
-- runtime alike. The private saves already here still load, list and delete (D49), a share made before
-- can still be withdrawn, and a team workspace still saves (until step 6).
begin;
create function pg_temp.assert_retired(ok boolean, message text) returns void
language plpgsql as $$ begin if ok is distinct from true then raise exception '%', message; end if; end $$;
-- The refusal a statement meets, as `sqlstate message`, or `accepted`. A refused statement changes nothing.
create function pg_temp.refusal(p_statement text) returns text
language plpgsql as $$
begin
  execute p_statement;
  return 'accepted';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

-- Each function this migration replaces is still owned by the migration role and keeps its grants. A
-- signed-in session still reaches the personal save, so it hears the refusal by name; nothing but the
-- workspace runtime reaches matching.
select pg_temp.assert_retired(not r.rolsuper, p.oid::regprocedure::text || ' must be created under a non-superuser')
  from pg_proc p join pg_roles r on r.oid = p.proowner
  where p.oid in ('private.weave_save_initiative(uuid,integer,uuid,jsonb)'::regprocedure,
    'private.weave_matching_preview(uuid,integer,jsonb,timestamptz)'::regprocedure,
    'private.weave_matching_change(uuid,text,uuid,uuid,jsonb)'::regprocedure);
select pg_temp.assert_retired(has_function_privilege('authenticated', f, 'execute'), 'a signed-in session must still reach ' || f)
  from unnest(array['weave.save_initiative(uuid,integer,uuid,jsonb)', 'private.weave_save_initiative(uuid,integer,uuid,jsonb)',
    'weave.load_initiative(uuid)', 'weave.list_initiatives(integer)', 'weave.delete_initiative(uuid,integer,uuid)']) f;
select pg_temp.assert_retired(not has_function_privilege('anon', 'weave.save_initiative(uuid,integer,uuid,jsonb)', 'execute'),
  'an anonymous caller must not reach the save');
select pg_temp.assert_retired(not has_function_privilege(r, f, 'execute'), r || ' must not run ' || f)
  from unnest(array['public', 'anon', 'authenticated', 'service_role']) r,
    unnest(array['weave.matching_preview(uuid,integer,jsonb,timestamptz)', 'weave.matching_change(uuid,text,uuid,uuid,jsonb)',
      'private.weave_matching_preview(uuid,integer,jsonb,timestamptz)', 'private.weave_matching_change(uuid,text,uuid,uuid,jsonb)']) f;
select pg_temp.assert_retired(has_function_privilege('weave_workspace_runtime',
    'weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)', 'execute'), 'the workspace runtime must still run team commands');

-- Dana saved privately before step 4 and is an admin of a group's workspace; Eli is someone else.
insert into auth.users(id, email_confirmed_at) values
  ('f1000000-0000-4000-8000-000000000001', now()), ('f1000000-0000-4000-8000-000000000002', now());
insert into auth.sessions(id, user_id) values
  ('f2000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001'),
  ('f2000000-0000-4000-8000-000000000002', 'f1000000-0000-4000-8000-000000000002');
insert into auth.identities(user_id, provider, provider_id) values
  ('f1000000-0000-4000-8000-000000000001', 'custom:certified', 'https://certified.one|did:plc:dddddddddddddddddddddddd'),
  ('f1000000-0000-4000-8000-000000000002', 'custom:certified', 'https://certified.one|did:plc:eeeeeeeeeeeeeeeeeeeeeeee');
insert into weave_workspace.project_links(id, project_uri, repository_did, group_did, cid, linked_by) values
  ('f3000000-0000-4000-8000-000000000001', 'at://did:plc:gggggggggggggggggggggggg/org.hypercerts.collection/3mretiredsaves',
   'did:plc:gggggggggggggggggggggggg', 'did:plc:gggggggggggggggggggggggg', 'bafyfixture', 'f1000000-0000-4000-8000-000000000001');
insert into weave_workspace.access_grants(workspace_id, user_id, member_did, access_role) values
  ('f3000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001', 'did:plc:dddddddddddddddddddddddd', 'admin');

create function pg_temp.claims(p_user uuid, p_session uuid) returns text language sql as $$
  select set_config('request.jwt.claims', jsonb_build_object('sub', p_user, 'session_id', p_session, 'role', 'authenticated',
    'exp', 4102444800)::text, true) $$;
-- A checked card with one open need, as a private save held it.
create function pg_temp.card(p_entry uuid, p_title text) returns jsonb language sql immutable as $$
  select jsonb_build_object('version', 1,
    'initiative', jsonb_build_object('name', 'Fictional seed swap', 'description', 'Private card summary', 'locations', '[]'::jsonb,
      'isGlobal', false, 'links', '[]'::jsonb, 'stage', null, 'lenses', '[]'::jsonb, 'themes', '[]'::jsonb,
      'beneficiaries', '[]'::jsonb, 'languages', '[]'::jsonb),
    'needs', jsonb_build_array(jsonb_build_object('id', p_entry, 'value', jsonb_build_object('title', p_title,
      'description', 'Fictional details', 'capitalForms', jsonb_build_array('social'), 'amount', null, 'timeframe', null,
      'urgency', null, 'placeScope', 'here', 'exchangeTerms', jsonb_build_array('open'), 'purpose', null,
      'capacity', null, 'audience', null, 'status', 'open'))),
    'offers', '[]'::jsonb,
    'funding', jsonb_build_object('form', jsonb_build_object('workCountries', '', 'benefitCountries', '', 'applicantBaseCountry', '',
      'registrationCountry', '', 'applicantType', 'unknown', 'fundingInstruments', '[]'::jsonb, 'goalMin', '', 'goalMax', '',
      'currency', '', 'usWorkStates', '', 'usBenefitStates', ''), 'programAnswers', '{}'::jsonb)) $$;
-- A private save made before step 4, through the save logic a team workspace still uses. Only the test
-- owner can run that logic; this is the setup, not a path any client has.
create function pg_temp.saved_before(p_id uuid, p_revision integer, p_request uuid, p_document jsonb) returns jsonb
language sql security definer as $$ select private.weave_save_document(p_id, p_revision, p_request, p_document, false) $$;
-- A card's need as a matching command names it, read as the test owner.
create function pg_temp.need_ref(p_card uuid) returns jsonb language sql stable security definer as $$
  select jsonb_build_array(jsonb_build_object('kind', 'need', 'entryId', e.id, 'revision', e.matching_revision,
    'shareVersion', e.matching_share_version))
  from private.weave_matching_entries e where e.initiative_id = p_card and e.kind = 'need' $$;
-- A need shared as Weave shared it before step 4.
create function pg_temp.shared_before(p_card uuid) returns void language sql security definer as $$
  update weave.needs set matching_audience = 'weave_users', matching_withdrawn = false,
    matching_reviewed_revision = matching_revision,
    matching_reviewed_summary_revision = (select matching_summary_revision from weave.initiatives where id = p_card),
    matching_confirmed_at = now(), matching_expires_at = now() + interval '30 days',
    matching_share_version = nextval('private.weave_matching_version')
  where initiative_id = p_card $$;
create function pg_temp.withdrawn(p_card uuid) returns boolean language sql stable security definer as $$
  select bool_and(matching_withdrawn) from weave.needs where initiative_id = p_card $$;
-- Dana's command to the group workspace, as the Weave server sends it through the workspace runtime.
create function pg_temp.team(p_action text, p_data jsonb) returns jsonb language sql as $$
  select weave_workspace.content_command('f1000000-0000-4000-8000-000000000001', 'f2000000-0000-4000-8000-000000000001',
    'did:plc:dddddddddddddddddddddddd', 'f3000000-0000-4000-8000-000000000001', 'owner', 'bafyfixture', p_action, p_data) $$;

-- 1. Nothing is saved privately: not a new card, not an update to a save made before, not a replay of
-- its earlier request. Each is refused by name and writes nothing.
select pg_temp.claims('f1000000-0000-4000-8000-000000000001', 'f2000000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.assert_retired(pg_temp.saved_before('f4000000-0000-4000-8000-000000000001', 0, 'f8000000-0000-4000-8000-000000000001',
    pg_temp.card('f5000000-0000-4000-8000-000000000001', 'Seed swap'))->>'revision' = '1', 'a save made before step 4 is set up');
select pg_temp.assert_retired(pg_temp.refusal(format('select weave.save_initiative(%L, 0, %L, %L)', c.id, c.request, c.document))
    = 'PT410 private_saves_retired', 'a personal save must be refused: ' || c.label)
from (values
  ('f4000000-0000-4000-8000-000000000002'::uuid, 'f8000000-0000-4000-8000-000000000002'::uuid,
    pg_temp.card('f5000000-0000-4000-8000-000000000002', 'A new card'), 'a new card'),
  ('f4000000-0000-4000-8000-000000000001'::uuid, 'f8000000-0000-4000-8000-000000000001'::uuid,
    pg_temp.card('f5000000-0000-4000-8000-000000000001', 'Seed swap'), 'a replay of the earlier request')) c(id, request, document, label);
select pg_temp.assert_retired(pg_temp.refusal(format('select weave.save_initiative(%L, 1, %L, %L)', 'f4000000-0000-4000-8000-000000000001',
    'f8000000-0000-4000-8000-000000000003', pg_temp.card('f5000000-0000-4000-8000-000000000001', 'Seed swap, changed')))
  = 'PT410 private_saves_retired', 'a save made before must not be updated');

-- 2. The save made before still loads and lists as it was (D49).
select pg_temp.assert_retired(weave.load_initiative('f4000000-0000-4000-8000-000000000001')->'document'
    = pg_temp.card('f5000000-0000-4000-8000-000000000001', 'Seed swap'), 'the save made before must load as it was');
select pg_temp.assert_retired((weave.load_initiative('f4000000-0000-4000-8000-000000000001')->>'revision')::int = 1,
  'the save made before must keep its revision');
select pg_temp.assert_retired(jsonb_array_length(weave.list_initiatives()) = 1, 'the account must list only the save made before');
reset role;
select pg_temp.assert_retired((select count(*) from weave.initiatives where owner_id = 'f1000000-0000-4000-8000-000000000001') = 1
  and (select count(*) from private.weave_save_requests where actor_id = 'f1000000-0000-4000-8000-000000000001') = 1,
  'the refused saves must write nothing');

-- 3. A share made before can be withdrawn by its owner; nothing is reviewed, shared or renewed. The
-- private functions run only as their owner or through the workspace runtime, so the test owner calls
-- them here with the session's claims.
select pg_temp.shared_before('f4000000-0000-4000-8000-000000000001');
select pg_temp.assert_retired(pg_temp.refusal(format('select private.weave_matching_preview(%L, 1, %L, null)',
    'f4000000-0000-4000-8000-000000000001', pg_temp.need_ref('f4000000-0000-4000-8000-000000000001')))
  = 'PT410 matching_shares_retired', 'no review may be made');
select pg_temp.assert_retired(pg_temp.refusal(format('select private.weave_matching_change(%L, %L, %L, %L, null)',
    'f4000000-0000-4000-8000-000000000001', a, gen_random_uuid(), gen_random_uuid())) = 'PT410 matching_shares_retired',
  'a ' || a || ' must be refused')
from unnest(array['share', 'renew']) a;
select pg_temp.assert_retired(pg_temp.refusal(format('select private.weave_matching_change(%L, %L, %L, %L, %L)',
    'f4000000-0000-4000-8000-000000000001', c.action, gen_random_uuid(), c.review, c.entries)) = 'PT400 invalid_data',
  'a malformed command must still be invalid data: ' || c.label)
from (values ('share', null::uuid, null::jsonb, 'a share with no review'),
  ('publish', gen_random_uuid(), null::jsonb, 'an unknown action'),
  ('withdraw', null::uuid, null::jsonb, 'a withdrawal naming nothing')) c(action, review, entries, label);
select pg_temp.assert_retired((select count(*) from private.weave_matching_reviews
    where initiative_id = 'f4000000-0000-4000-8000-000000000001') = 0, 'no review may be kept');
select pg_temp.claims('f1000000-0000-4000-8000-000000000002', 'f2000000-0000-4000-8000-000000000002');
select pg_temp.assert_retired(pg_temp.refusal(format('select private.weave_matching_change(%L, %L, %L, null, %L)',
    'f4000000-0000-4000-8000-000000000001', 'withdraw', gen_random_uuid(), pg_temp.need_ref('f4000000-0000-4000-8000-000000000001')))
  = 'PT404 not_found', 'someone else must not withdraw the share');
select pg_temp.claims('f1000000-0000-4000-8000-000000000001', 'f2000000-0000-4000-8000-000000000001');
select pg_temp.assert_retired(not pg_temp.withdrawn('f4000000-0000-4000-8000-000000000001'), 'the share made before is still on');
create temp table earlier(entries jsonb not null);
insert into earlier select pg_temp.need_ref('f4000000-0000-4000-8000-000000000001');
select private.weave_matching_change('f4000000-0000-4000-8000-000000000001', 'withdraw', 'f9000000-0000-4000-8000-000000000001', null,
  (select entries from earlier));
select pg_temp.assert_retired(pg_temp.withdrawn('f4000000-0000-4000-8000-000000000001'), 'the owner must still withdraw a share made before');
create temp table after_withdrawal(entries jsonb not null);
insert into after_withdrawal select pg_temp.need_ref('f4000000-0000-4000-8000-000000000001');
select private.weave_matching_change('f4000000-0000-4000-8000-000000000001', 'withdraw', 'f9000000-0000-4000-8000-000000000001', null,
  (select entries from earlier));
select pg_temp.assert_retired(pg_temp.need_ref('f4000000-0000-4000-8000-000000000001') = (select entries from after_withdrawal),
  'a replayed withdrawal must change nothing again');
select pg_temp.assert_retired(pg_temp.refusal(format('select private.weave_matching_change(%L, %L, %L, null, %L)',
    'f4000000-0000-4000-8000-000000000001', 'withdraw', gen_random_uuid(), (select entries from earlier)))
  = 'PT409 matching_conflict', 'a withdrawal of a version that moved on must conflict');

-- 4. The save made before can still be deleted by its owner (D49).
set local role authenticated;
select pg_temp.assert_retired((weave.delete_initiative('f4000000-0000-4000-8000-000000000001', 1, 'f8000000-0000-4000-8000-000000000009')
  ->>'deleted')::boolean, 'the owner must still delete a save made before');
select pg_temp.assert_retired(jsonb_array_length(weave.list_initiatives()) = 0, 'a deleted save must leave the list');
reset role;

-- 5. A team workspace still saves through the workspace runtime (until step 6), and its matching refuses
-- the same way: no review, share or renewal, while a share made before can be withdrawn.
select set_config('request.jwt.claims', '', true);
set local role weave_workspace_runtime;
select pg_temp.assert_retired(pg_temp.team('team_save', jsonb_build_object('expectedRevision', 0,
    'requestId', 'f8000000-0000-4000-8000-000000000010', 'document', pg_temp.card('f5000000-0000-4000-8000-000000000010', 'Tool library')))
    ->>'revision' = '1', 'a team workspace must still save');
select pg_temp.assert_retired((pg_temp.team('team_load', '{}')->'saved'->'document')
    = pg_temp.card('f5000000-0000-4000-8000-000000000010', 'Tool library'), 'the team save must load as saved');
select pg_temp.assert_retired(pg_temp.refusal(format('select pg_temp.team(%L, %L)', 'matching_preview', jsonb_build_object('p_revision', 1,
    'p_entries', pg_temp.need_ref('f3000000-0000-4000-8000-000000000001'), 'p_expires_at', null))) = 'PT410 matching_shares_retired',
  'a team review must be refused');
select pg_temp.assert_retired(pg_temp.refusal(format('select pg_temp.team(%L, %L)', 'matching_change', jsonb_build_object('p_action', a,
    'p_request_id', gen_random_uuid(), 'p_review_id', gen_random_uuid(), 'p_entries', null))) = 'PT410 matching_shares_retired',
  'a team ' || a || ' must be refused')
from unnest(array['share', 'renew']) a;
reset role;
select pg_temp.shared_before('f3000000-0000-4000-8000-000000000001');
set local role weave_workspace_runtime;
select pg_temp.assert_retired(jsonb_typeof(pg_temp.team('matching_state', '{}')) = 'object', 'a team workspace must still read its matching state');
select pg_temp.team('matching_change', jsonb_build_object('p_action', 'withdraw', 'p_request_id', 'f9000000-0000-4000-8000-000000000010',
  'p_review_id', null, 'p_entries', pg_temp.need_ref('f3000000-0000-4000-8000-000000000001')));
reset role;
select pg_temp.assert_retired(pg_temp.withdrawn('f3000000-0000-4000-8000-000000000001'), 'a team must still withdraw a share made before');
select pg_temp.assert_retired(nullif(current_setting('request.jwt.claims', true), '') is null,
  'team commands must not leave an actor in the session');

rollback;
