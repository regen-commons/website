-- Disposable database only; synthetic identities, projects and listings, and all fixture rows roll back.
-- DL-155, step 3: a need or offer is published from the device draft with no private save first. A
-- personal project link needs no saved card and is held by the verified Certified DID that owns the
-- project's repository. Deleting a saved card no longer erases Weave's record of its published listings,
-- no new card may take a link's ID, and publishing from a saved card still works, also after DL-155 step 4.
-- Security definer commands are called as the test owner unless a step is about the runtime's grants.
begin;
create function pg_temp.assert_draft(ok boolean, message text) returns void
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

-- Every function this migration replaces is still owned by the migration role and keeps its grants.
select pg_temp.assert_draft(not r.rolsuper, p.oid::regprocedure::text || ' must be created under a non-superuser')
  from pg_proc p join pg_roles r on r.oid = p.proowner
  where p.oid in ('weave_workspace.command(uuid,uuid,text,text,jsonb)'::regprocedure,
    'weave_workspace.support_command(uuid,uuid,text,uuid,text,text,text,jsonb)'::regprocedure,
    'weave_workspace.link_result(weave_workspace.project_links,uuid,text,text)'::regprocedure,
    'weave_workspace.support_entry_changed()'::regprocedure, 'weave_workspace.support_lenses_changed()'::regprocedure,
    'weave_workspace.initiative_link_guard()'::regprocedure);
select pg_temp.assert_draft(has_function_privilege('weave_workspace_runtime', f, 'execute'), 'the workspace runtime must run ' || f)
  from unnest(array['weave_workspace.command(uuid,uuid,text,text,jsonb)',
    'weave_workspace.support_command(uuid,uuid,text,uuid,text,text,text,jsonb)']) f;
select pg_temp.assert_draft(not has_function_privilege(r, f, 'execute'), r || ' must not run ' || f)
  from unnest(array['public', 'anon', 'authenticated', 'service_role']) r,
    unnest(array['weave_workspace.command(uuid,uuid,text,text,jsonb)',
      'weave_workspace.support_command(uuid,uuid,text,uuid,text,text,text,jsonb)']) f;
select pg_temp.assert_draft(not has_function_privilege(r, 'weave_workspace.initiative_link_guard()', 'execute'),
  r || ' must not run the link guard outside its trigger')
  from unnest(array['public', 'anon', 'authenticated', 'service_role', 'weave_workspace_runtime']) r;
select pg_temp.assert_draft((select array_agg(conname::text order by conname) from pg_constraint
    where conrelid = 'weave_workspace.project_links'::regclass and contype = 'c')
  = array['project_links_check', 'project_links_owner_check'], 'project_links must keep its project check and replace its owner check');
select pg_temp.assert_draft((select confdeltype from pg_constraint where conname = 'project_links_solo_initiative_id_fkey'
    and conrelid = 'weave_workspace.project_links'::regclass) = 'n', 'deleting a saved card must leave its project link, without the card');
select pg_temp.assert_draft((select count(*) from pg_trigger where tgrelid = 'weave.initiatives'::regclass
    and tgname = 'initiative_link_guard' and tgenabled = 'O') = 1, 'new saved cards must pass the link guard');

-- Alice holds did:plc:pppp… on two browsers; a second account also holds it, as after unlinking and relinking
-- the identity; Bob is someone else.
insert into auth.users(id, email_confirmed_at) values
  ('e1000000-0000-4000-8000-000000000001', now()), ('e1000000-0000-4000-8000-000000000002', now()),
  ('e1000000-0000-4000-8000-000000000003', now());
insert into auth.sessions(id, user_id) values
  ('e2000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001'),
  ('e2000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000001'),
  ('e2000000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000002'),
  ('e2000000-0000-4000-8000-000000000004', 'e1000000-0000-4000-8000-000000000003');
insert into auth.identities(user_id, provider, provider_id) values
  ('e1000000-0000-4000-8000-000000000001', 'custom:certified', 'https://certified.one|did:plc:pppppppppppppppppppppppp'),
  ('e1000000-0000-4000-8000-000000000002', 'custom:certified', 'https://certified.one|did:plc:qqqqqqqqqqqqqqqqqqqqqqqq'),
  ('e1000000-0000-4000-8000-000000000003', 'custom:certified', 'https://certified.one|did:plc:pppppppppppppppppppppppp');
create temp table actors(name text primary key, user_id uuid not null, session_id uuid not null, did text not null);
insert into actors values
  ('alice', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'did:plc:pppppppppppppppppppppppp'),
  ('alice elsewhere', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000002', 'did:plc:pppppppppppppppppppppppp'),
  ('bob', 'e1000000-0000-4000-8000-000000000002', 'e2000000-0000-4000-8000-000000000003', 'did:plc:qqqqqqqqqqqqqqqqqqqqqqqq'),
  ('alice''s other account', 'e1000000-0000-4000-8000-000000000003', 'e2000000-0000-4000-8000-000000000004', 'did:plc:pppppppppppppppppppppppp');
-- Values the commands answer with, by name, for later steps.
create temp table seen(name text primary key, value jsonb not null);
create function pg_temp.seen(p_name text) returns jsonb language sql stable as $$ select value from pg_temp.seen where name = p_name $$;
create function pg_temp.keep(p_name text, p_value jsonb) returns jsonb language sql as $$
  insert into pg_temp.seen values (p_name, p_value) returning value $$;
create function pg_temp.project(p_who text, p_action text, p_data jsonb) returns jsonb language sql as $$
  select weave_workspace.command(a.user_id, a.session_id, a.did, p_action, p_data) from pg_temp.actors a where a.name = p_who $$;
create function pg_temp.support(p_who text, p_workspace uuid, p_action text, p_data jsonb, p_role text default null) returns jsonb language sql as $$
  select weave_workspace.support_command(a.user_id, a.session_id, a.did, p_workspace, p_role, 'bafyfixture', p_action, p_data)
  from pg_temp.actors a where a.name = p_who $$;
create function pg_temp.workspaces(p_who text) returns jsonb language sql as $$
  select weave_workspace.discovery(a.user_id, a.session_id, a.did, 'list_workspaces', '{}')->'entries' from pg_temp.actors a where a.name = p_who $$;
-- Alice's own projects, as a verified Certified read names them.
create function pg_temp.own(p_rkey text) returns jsonb language sql immutable as $$
  select jsonb_build_object('projectUri', 'at://did:plc:pppppppppppppppppppppppp/org.hypercerts.collection/' || p_rkey,
    'repositoryDid', 'did:plc:pppppppppppppppppppppppp', 'cid', 'bafyfixture') $$;
create function pg_temp.draft_review(p_kind text, p_entry uuid, p_fields jsonb) returns jsonb language sql immutable as $$
  select jsonb_build_object('kind', p_kind, 'entryId', p_entry, 'expiresAt', null, 'entry', p_fields) $$;
-- A checked private save with one open need, as a private save held it.
create function pg_temp.card(p_entry uuid, p_title text, p_lenses jsonb) returns jsonb language sql immutable as $$
  select jsonb_build_object('version', 1,
    'initiative', jsonb_build_object('name', 'Fictional project', 'description', 'Private workspace summary', 'locations', '[]'::jsonb,
      'isGlobal', false, 'links', '[]'::jsonb, 'stage', null, 'lenses', p_lenses, 'themes', '[]'::jsonb,
      'beneficiaries', '[]'::jsonb, 'languages', '[]'::jsonb),
    'needs', jsonb_build_array(jsonb_build_object('id', p_entry, 'value', jsonb_build_object('title', p_title,
      'description', 'Public details', 'capitalForms', jsonb_build_array('social'), 'amount', null, 'timeframe', null,
      'urgency', null, 'placeScope', 'here', 'exchangeTerms', jsonb_build_array('open'), 'purpose', 'Private purpose',
      'capacity', null, 'audience', null, 'status', 'open'))),
    'offers', '[]'::jsonb,
    'funding', jsonb_build_object('form', jsonb_build_object('workCountries', '', 'benefitCountries', '', 'applicantBaseCountry', '',
      'registrationCountry', '', 'applicantType', 'unknown', 'fundingInstruments', '[]'::jsonb, 'goalMin', '', 'goalMax', '',
      'currency', '', 'usWorkStates', '', 'usBenefitStates', ''), 'programAnswers', '{}'::jsonb)) $$;
create function pg_temp.entry_revision(p_card uuid, p_entry uuid) returns bigint language sql stable as $$
  select matching_revision from private.weave_matching_entries where initiative_id = p_card and kind = 'need' and id = p_entry $$;
create function pg_temp.listing(p_workspace uuid, p_entry uuid) returns weave_workspace.support_listings language sql stable as $$
  select * from weave_workspace.support_listings where workspace_id = p_workspace and entry_id = p_entry $$;
-- A private save made before DL-155 step 4, which refuses new ones, through the save logic a team workspace
-- still uses. Only the test owner can run that logic; it is setup, not a path any client has.
create function pg_temp.saved_before(p_id uuid, p_revision integer, p_request uuid, p_document jsonb) returns jsonb
language sql security definer as $$ select private.weave_save_document(p_id, p_revision, p_request, p_document, false) $$;

-- 1. A draft links its person's own project with no saved card, through the workspace runtime.
set local role weave_workspace_runtime;
select pg_temp.assert_draft((weave_workspace.command('e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001',
    'did:plc:pppppppppppppppppppppppp', 'link', '{"projectUri":"at://did:plc:pppppppppppppppppppppppp/org.hypercerts.collection/3mdraftproject",
    "repositoryDid":"did:plc:pppppppppppppppppppppppp","cid":"bafyfixture"}'))->>'status' = 'linked',
  'the workspace runtime must link a person''s own project with no saved card');
reset role;
select pg_temp.keep('draft', to_jsonb(l)) from weave_workspace.project_links l
  where l.project_uri = 'at://did:plc:pppppppppppppppppppppppp/org.hypercerts.collection/3mdraftproject';
select pg_temp.assert_draft(pg_temp.seen('draft')->>'solo_initiative_id' is null and pg_temp.seen('draft')->>'group_did' is null
  and pg_temp.seen('draft')->>'linked_by' = 'e1000000-0000-4000-8000-000000000001'
  and pg_temp.seen('draft')->>'repository_did' = 'did:plc:pppppppppppppppppppppppp', 'a card-less link names its project and no saved card');
select pg_temp.assert_draft(pg_temp.project('alice', 'link', pg_temp.own('3mdraftproject')) = jsonb_build_object('status', 'linked',
    'workspaceId', pg_temp.seen('draft')->>'id', 'accessRole', 'admin',
    'projectUri', 'at://did:plc:pppppppppppppppppppppppp/org.hypercerts.collection/3mdraftproject', 'cid', 'bafyfixture'),
  'linking again must answer the same link');
select pg_temp.assert_draft((select count(*) from weave_workspace.project_links
    where project_uri = 'at://did:plc:pppppppppppppppppppppppp/org.hypercerts.collection/3mdraftproject') = 1, 'a project has one link');
select pg_temp.assert_draft(pg_temp.project('alice elsewhere', 'lookup', pg_temp.own('3mdraftproject'))
    = pg_temp.project('alice', 'link', pg_temp.own('3mdraftproject')), 'the same Certified identity holds the link from another browser');
select pg_temp.assert_draft(weave_workspace.link_result(l, 'e1000000-0000-4000-8000-000000000002', 'did:plc:qqqqqqqqqqqqqqqqqqqqqqqq', null)
    = '{"status":"access_required"}'::jsonb, 'only the DID that owns the repository holds a personal link')
  from weave_workspace.project_links l where l.id = (pg_temp.seen('draft')->>'id')::uuid;
select pg_temp.assert_draft(pg_temp.refusal(format('select pg_temp.project(%L, %L, %L)', 'bob', c.action, pg_temp.own('3mdraftproject')))
    = 'PT403 project_verification_required', 'someone else must not ' || c.action || ' another person''s project as their own')
  from (values ('lookup'), ('link')) c(action);
select pg_temp.assert_draft(pg_temp.refusal(format('select weave_workspace.command(%L, %L, %L, %L, %L)',
    'e1000000-0000-4000-8000-000000000002', 'e2000000-0000-4000-8000-000000000003', 'did:plc:pppppppppppppppppppppppp',
    'link', pg_temp.own('3mdraftproject'))) = 'PT401 sign_in_required', 'a session must not claim another person''s DID');
select pg_temp.assert_draft(pg_temp.refusal(format('select pg_temp.support(%L, %L, %L, %L)', 'bob', pg_temp.seen('draft')->>'id',
    'support_state', '{}')) = 'PT404 not_found', 'someone else must not read the project''s listings');
select pg_temp.assert_draft(pg_temp.refusal(format('select weave_workspace.support_command(%L, %L, %L, %L, null, %L, %L, %L)',
    'e1000000-0000-4000-8000-000000000002', 'e2000000-0000-4000-8000-000000000003', 'did:plc:pppppppppppppppppppppppp',
    pg_temp.seen('draft')->>'id', 'bafyfixture', 'support_state', '{}')) = 'PT401 sign_in_required',
  'a session must not claim the owner''s DID to reach the listings');
select pg_temp.assert_draft(not coalesce(pg_temp.workspaces('alice') @> jsonb_build_array(jsonb_build_object('workspaceId', pg_temp.seen('draft')->>'id')), false),
  'a card-less link is reached by its project, never listed as a saved workspace');

-- 2. A need is reviewed from the draft, published once, claimed once, confirmed and shown publicly.
select pg_temp.keep('review', pg_temp.support('alice', (pg_temp.seen('draft')->>'id')::uuid, 'support_review',
  pg_temp.draft_review('need', 'e6000000-0000-4000-8000-000000000001', jsonb_build_object('title', 'Seed packets for the valley',
    'description', 'Fictional public details.', 'capitalForms', jsonb_build_array('material', 'living'), 'lenses', jsonb_build_array('place_based')))));
select pg_temp.assert_draft(pg_temp.seen('review') - array['reviewId', 'reviewExpiresAt', 'record'] = jsonb_build_object('audience', 'public-atproto',
    'destination', 'did:plc:pppppppppppppppppppppppp', 'expectedRevision', 0, 'expectedEntryRevision', 0),
  'a draft review names the repository and no saved revision');
select pg_temp.assert_draft((pg_temp.seen('review')->'record') - array['createdAt', 'updatedAt'] = jsonb_build_object(
    '$type', 'com.regencommons.weave.supportListing', 'projectUri', 'at://did:plc:pppppppppppppppppppppppp/org.hypercerts.collection/3mdraftproject',
    'kind', 'need', 'title', 'Seed packets for the valley', 'description', 'Fictional public details.',
    'capitalForms', jsonb_build_array('material', 'living'), 'lenses', jsonb_build_array('place_based'), 'status', 'open'),
  'the public record is built from the draft''s fields alone');
select pg_temp.assert_draft((select source = 'draft' and saved_revision = 0 and entry_revision = 0
    and actor_id = 'e1000000-0000-4000-8000-000000000001' and session_id = 'e2000000-0000-4000-8000-000000000001'
    and expires_at <= clock_timestamp() + interval '10 minutes'
  from weave_workspace.support_reviews where id = (pg_temp.seen('review')->>'reviewId')::uuid), 'the review is kept briefly, as a draft''s');
select pg_temp.assert_draft(pg_temp.support('alice', (pg_temp.seen('draft')->>'id')::uuid, 'support_state', '{}')->'listings' = '[]'::jsonb,
  'a review publishes nothing');
select pg_temp.keep('published', pg_temp.support('alice', (pg_temp.seen('draft')->>'id')::uuid, 'support_publish', jsonb_build_object(
  'requestId', 'e7000000-0000-4000-8000-000000000001', 'reviewId', pg_temp.seen('review')->>'reviewId',
  'audience', 'public-atproto', 'confirmPublic', true)));
select pg_temp.assert_draft(pg_temp.seen('published')->>'status' = 'publish_pending' and pg_temp.seen('published')->'record' = pg_temp.seen('review')->'record'
    and pg_temp.seen('published')->>'rkey' ~ '^[2-7a-j][2-7a-z]{12}$', 'publishing keeps exactly the reviewed record at a new key');
select pg_temp.assert_draft(pg_temp.support('alice', (pg_temp.seen('draft')->>'id')::uuid, 'support_publish', jsonb_build_object(
    'requestId', 'e7000000-0000-4000-8000-000000000001', 'reviewId', pg_temp.seen('review')->>'reviewId',
    'audience', 'public-atproto', 'confirmPublic', true)) = pg_temp.seen('published'), 'the same request publishes once');
select pg_temp.assert_draft((pg_temp.listing((pg_temp.seen('draft')->>'id')::uuid, 'e6000000-0000-4000-8000-000000000001')).source = 'draft'
    and (pg_temp.listing((pg_temp.seen('draft')->>'id')::uuid, 'e6000000-0000-4000-8000-000000000001')).entry_revision = 0
    and not exists(select from weave_workspace.support_reviews where id = (pg_temp.seen('review')->>'reviewId')::uuid),
  'the listing is the draft''s, and its review is spent');
select pg_temp.keep('claim', pg_temp.support('alice', (pg_temp.seen('draft')->>'id')::uuid, 'support_checkpoint', jsonb_build_object(
  'kind', 'need', 'entryId', 'e6000000-0000-4000-8000-000000000001', 'operationId', pg_temp.seen('published')->>'operationId', 'event', 'sending')));
select pg_temp.assert_draft(pg_temp.seen('claim')->>'claimed' = 'true' and pg_temp.seen('claim')->>'status' = 'publish_pending',
  'a draft''s listing is claimed for sending with no saved entry to check');
select pg_temp.assert_draft(pg_temp.support('alice elsewhere', (pg_temp.seen('draft')->>'id')::uuid, 'support_checkpoint', jsonb_build_object(
    'kind', 'need', 'entryId', 'e6000000-0000-4000-8000-000000000001', 'operationId', pg_temp.seen('published')->>'operationId',
    'event', 'sending'))->>'claimed' = 'false', 'only one claim may send the create');
select pg_temp.assert_draft(pg_temp.support('alice', (pg_temp.seen('draft')->>'id')::uuid, 'support_checkpoint', jsonb_build_object(
    'kind', 'need', 'entryId', 'e6000000-0000-4000-8000-000000000001', 'operationId', pg_temp.seen('published')->>'operationId',
    'event', 'published', 'cid', 'b' || repeat('a', 58)))->>'status' = 'published', 'a read-back confirms the listing');
select pg_temp.assert_draft((select count(*) = 1 and bool_and(rkey = pg_temp.seen('published')->>'rkey' and record = pg_temp.seen('review')->'record')
  from private.weave_public_support_listings('at://did:plc:pppppppppppppppppppppppp/org.hypercerts.collection/3mdraftproject')),
  'the public page shows the listing published from the draft');
select pg_temp.assert_draft(pg_temp.refusal(format('select pg_temp.support(%L, %L, %L, %L)', 'alice', pg_temp.seen('draft')->>'id', 'support_review',
    pg_temp.draft_review('need', 'e6000000-0000-4000-8000-000000000001', '{"title":"Seed packets and gloves","capitalForms":["material"]}')))
  = 'PT409 withdrawal_required', 'a public listing is not replaced from an edited draft until it is withdrawn');

-- An offer with no description and no types of work leaves both out of its record.
select pg_temp.assert_draft(not (pg_temp.support('alice', (pg_temp.seen('draft')->>'id')::uuid, 'support_review',
    pg_temp.draft_review('offer', 'e6000000-0000-4000-8000-000000000002', '{"title":"Oral history workshop","capitalForms":["cultural"],"lenses":[]}'))
    ->'record' ?| array['description', 'lenses']), 'an empty description or list of types of work is left out');
select pg_temp.assert_draft(pg_temp.refusal(format('select pg_temp.support(%L, %L, %L, %L)', 'alice', pg_temp.seen('draft')->>'id', 'support_review',
    jsonb_build_object('kind', 'offer', 'entryId', 'e6000000-0000-4000-8000-000000000002', 'expiresAt', '2000-01-01T00:00:00Z',
      'entry', '{"title":"Oral history workshop","capitalForms":["cultural"]}'::jsonb))) = 'PT400 invalid_expiry', 'an end date in the past is refused');

-- 3. Withdrawal needs no draft: the same identity withdraws from a second browser, then publishes again at the same address.
select pg_temp.assert_draft(pg_temp.support('alice elsewhere', (pg_temp.seen('draft')->>'id')::uuid, 'support_withdraw', jsonb_build_object(
    'kind', 'need', 'entryId', 'e6000000-0000-4000-8000-000000000001', 'requestId', 'e7000000-0000-4000-8000-000000000002'))->>'status'
  = 'withdrawal_pending', 'a second browser asks to withdraw by the listing''s address');
select pg_temp.assert_draft(pg_temp.support('alice elsewhere', (pg_temp.seen('draft')->>'id')::uuid, 'support_checkpoint', jsonb_build_object(
    'kind', 'need', 'entryId', 'e6000000-0000-4000-8000-000000000001', 'operationId', pg_temp.seen('published')->>'operationId',
    'event', 'withdrawn'))->>'status' = 'withdrawn', 'and confirms the withdrawal');
select pg_temp.keep('review again', pg_temp.support('alice', (pg_temp.seen('draft')->>'id')::uuid, 'support_review',
  pg_temp.draft_review('need', 'e6000000-0000-4000-8000-000000000001', '{"title":"Seed packets and gloves","capitalForms":["material"]}')));
select pg_temp.keep('published again', pg_temp.support('alice', (pg_temp.seen('draft')->>'id')::uuid, 'support_publish', jsonb_build_object(
  'requestId', 'e7000000-0000-4000-8000-000000000003', 'reviewId', pg_temp.seen('review again')->>'reviewId',
  'audience', 'public-atproto', 'confirmPublic', true)));
select pg_temp.assert_draft(pg_temp.seen('published again')->>'rkey' = pg_temp.seen('published')->>'rkey'
    and pg_temp.seen('published again')->'record'->>'title' = 'Seed packets and gloves'
    and pg_temp.seen('published again')->'record'->>'createdAt' = pg_temp.seen('published')->'record'->>'createdAt'
    and (pg_temp.seen('published again')->'record'->>'updatedAt')::timestamptz > (pg_temp.seen('published')->'record'->>'updatedAt')::timestamptz,
  'publishing again keeps the listing''s address and first date, with a later update');

-- 4. A draft entry outside the listing's limits is refused at the owning boundary, and nothing is kept.
select pg_temp.assert_draft(pg_temp.refusal(format('select pg_temp.support(%L, %L, %L, %L)', 'alice', pg_temp.seen('draft')->>'id', 'support_review',
    jsonb_build_object('kind', c.kind, 'entryId', 'e6000000-0000-4000-8000-000000000009', 'expiresAt', null, 'entry', c.entry)))
  = 'PT400 invalid_support_entry', 'a draft review with ' || c.label || ' must be refused')
from (values
  ('no title', 'offer', '{"capitalForms":["social"]}'::jsonb),
  ('a blank title', 'offer', '{"title":"   ","capitalForms":["social"]}'),
  ('a title over 1400 bytes', 'offer', jsonb_build_object('title', repeat('é', 701), 'capitalForms', jsonb_build_array('social'))),
  ('a number for a title', 'offer', '{"title":7,"capitalForms":["social"]}'),
  ('a description over 6000 bytes', 'offer', jsonb_build_object('title', 'T', 'description', repeat('d', 6001), 'capitalForms', jsonb_build_array('social'))),
  ('a number for a description', 'offer', '{"title":"T","description":7,"capitalForms":["social"]}'),
  ('no kind of support', 'offer', '{"title":"T","capitalForms":[]}'),
  ('no list of kinds', 'offer', '{"title":"T"}'),
  ('nine kinds of support', 'offer', '{"title":"T","capitalForms":["living","material","intellectual","experiential","social","financial","cultural","spiritual","living"]}'),
  ('an unknown kind of support', 'offer', '{"title":"T","capitalForms":["money"]}'),
  ('a repeated kind of support', 'offer', '{"title":"T","capitalForms":["social","social"]}'),
  ('a kind of support that is not text', 'offer', '{"title":"T","capitalForms":[1]}'),
  ('kinds of support as text', 'offer', '{"title":"T","capitalForms":"social"}'),
  ('an unknown type of work', 'offer', '{"title":"T","capitalForms":["social"],"lenses":["gardening"]}'),
  ('a repeated type of work', 'offer', '{"title":"T","capitalForms":["social"],"lenses":["research","research"]}'),
  ('six types of work', 'offer', '{"title":"T","capitalForms":["social"],"lenses":["art_culture","research","technology","place_based","learning","funders"]}'),
  ('types of work as text', 'offer', '{"title":"T","capitalForms":["social"],"lenses":"research"}'),
  ('a private field', 'offer', '{"title":"T","capitalForms":["social"],"purpose":"Private purpose"}'),
  ('a status', 'offer', '{"title":"T","capitalForms":["social"],"status":"open"}'),
  ('an entry that is not an object', 'offer', '["T"]'),
  ('an unknown kind of listing', 'gift', '{"title":"T","capitalForms":["social"]}')
) as c(label, kind, entry);
select pg_temp.assert_draft(not exists(select from weave_workspace.support_reviews where entry_id = 'e6000000-0000-4000-8000-000000000009'),
  'a refused review keeps nothing');

-- 5. Publishing from a private save still works, beside a draft's listing on the same project, and only it follows the card.
select set_config('request.jwt.claims', '{"sub":"e1000000-0000-4000-8000-000000000001","session_id":"e2000000-0000-4000-8000-000000000001","role":"authenticated","exp":4102444800}', true);
set local role authenticated;
select pg_temp.saved_before('e4000000-0000-4000-8000-000000000001', 0, 'e8000000-0000-4000-8000-000000000001',
  pg_temp.card('e5000000-0000-4000-8000-000000000001', 'A fictional place to meet', '[]'));
select pg_temp.saved_before('e4000000-0000-4000-8000-000000000002', 0, 'e8000000-0000-4000-8000-000000000002',
  pg_temp.card('e5000000-0000-4000-8000-000000000002', 'A fictional tool library', '[]'));
reset role;
select pg_temp.assert_draft(pg_temp.project('alice', 'link', pg_temp.own('3mlegacyproject')
    || '{"initiativeId":"e4000000-0000-4000-8000-000000000001","expectedRevision":1}'::jsonb)->>'workspaceId' = 'e4000000-0000-4000-8000-000000000001',
  'a saved card still links its project at its own ID');
select pg_temp.assert_draft(pg_temp.workspaces('alice') @> '[{"workspaceId":"e4000000-0000-4000-8000-000000000001","kind":"personal"}]',
  'a personal link anchored on its saved card is listed as before');
select pg_temp.assert_draft(pg_temp.project('alice', 'link', pg_temp.own('3mdraftproject')
    || '{"initiativeId":"e4000000-0000-4000-8000-000000000002","expectedRevision":1}'::jsonb)->>'workspaceId' = pg_temp.seen('draft')->>'id',
  'a project linked from a draft keeps that one link when a saved card asks for it');
select pg_temp.keep('saved review', pg_temp.support('alice', 'e4000000-0000-4000-8000-000000000001', 'support_review', jsonb_build_object(
  'kind', 'need', 'entryId', 'e5000000-0000-4000-8000-000000000001', 'expectedRevision', 1,
  'expectedEntryRevision', pg_temp.entry_revision('e4000000-0000-4000-8000-000000000001', 'e5000000-0000-4000-8000-000000000001'),
  'expiresAt', null)));
select pg_temp.assert_draft((pg_temp.seen('saved review')->>'expectedRevision')::integer = 1
    and pg_temp.seen('saved review')->'record'->>'title' = 'A fictional place to meet'
    and (select source from weave_workspace.support_reviews where id = (pg_temp.seen('saved review')->>'reviewId')::uuid) = 'saved',
  'a saved card''s review is built from the saved entry, as before');
-- The DID rule holds the link, never another account's private save: the same DID on another account may
-- review from a draft, and may not read the saved card.
select pg_temp.assert_draft(pg_temp.refusal(format('select pg_temp.support(%L, %L, %L, %L)', 'alice''s other account',
    'e4000000-0000-4000-8000-000000000001', 'support_review', jsonb_build_object('kind', 'need', 'entryId', 'e5000000-0000-4000-8000-000000000001',
      'expectedRevision', 1, 'expectedEntryRevision', pg_temp.entry_revision('e4000000-0000-4000-8000-000000000001', 'e5000000-0000-4000-8000-000000000001'),
      'expiresAt', null))) = 'PT409 revision_conflict', 'another account holding the DID must not read the saved card');
select pg_temp.assert_draft(pg_temp.support('alice''s other account', 'e4000000-0000-4000-8000-000000000001', 'support_review',
    pg_temp.draft_review('need', 'e6000000-0000-4000-8000-000000000004', '{"title":"Shared tools","capitalForms":["material"]}'))->>'expectedRevision' = '0',
  'and may review a need from its own draft for the project');
select pg_temp.keep('saved published', pg_temp.support('alice', 'e4000000-0000-4000-8000-000000000001', 'support_publish', jsonb_build_object(
  'requestId', 'e7000000-0000-4000-8000-000000000010', 'reviewId', pg_temp.seen('saved review')->>'reviewId',
  'audience', 'public-atproto', 'confirmPublic', true)));
-- The same workspace also takes a draft's need that the saved card does not have.
select pg_temp.keep('mixed review', pg_temp.support('alice', 'e4000000-0000-4000-8000-000000000001', 'support_review',
  pg_temp.draft_review('need', 'e6000000-0000-4000-8000-000000000003', '{"title":"Volunteer drivers","capitalForms":["social"],"lenses":["research"]}')));
select pg_temp.assert_draft((pg_temp.seen('mixed review')->>'expectedRevision')::integer = 0
    and (pg_temp.seen('mixed review')->>'expectedEntryRevision')::integer = 0,
  'a draft review names no saved revision even where the workspace has a saved card');
select pg_temp.keep('mixed published', pg_temp.support('alice', 'e4000000-0000-4000-8000-000000000001', 'support_publish', jsonb_build_object(
  'requestId', 'e7000000-0000-4000-8000-000000000011', 'reviewId', pg_temp.seen('mixed review')->>'reviewId',
  'audience', 'public-atproto', 'confirmPublic', true)));
select pg_temp.assert_draft(pg_temp.support('alice', 'e4000000-0000-4000-8000-000000000001', 'support_checkpoint', jsonb_build_object(
    'kind', 'need', 'entryId', c.entry, 'operationId', pg_temp.seen(c.name)->>'operationId', 'event', 'sending'))->>'claimed' = 'true',
  c.name || ' must be claimed for sending')
from (values ('saved published', 'e5000000-0000-4000-8000-000000000001'), ('mixed published', 'e6000000-0000-4000-8000-000000000003')) c(name, entry);
select pg_temp.assert_draft(pg_temp.support('alice', 'e4000000-0000-4000-8000-000000000001', 'support_checkpoint', jsonb_build_object(
    'kind', 'need', 'entryId', c.entry, 'operationId', pg_temp.seen(c.name)->>'operationId', 'event', 'published',
    'cid', 'b' || repeat(c.letter, 58)))->>'status' = 'published', c.name || ' must be confirmed')
from (values ('saved published', 'e5000000-0000-4000-8000-000000000001', 'b'), ('mixed published', 'e6000000-0000-4000-8000-000000000003', 'c'))
  c(name, entry, letter);
-- Editing the saved card queues its own listing's withdrawal and leaves the draft's listing as it is,
-- even when the card's types of work change too.
select set_config('request.jwt.claims', '{"sub":"e1000000-0000-4000-8000-000000000001","session_id":"e2000000-0000-4000-8000-000000000001","role":"authenticated","exp":4102444800}', true);
set local role authenticated;
select pg_temp.saved_before('e4000000-0000-4000-8000-000000000001', 1, 'e8000000-0000-4000-8000-000000000003',
  pg_temp.card('e5000000-0000-4000-8000-000000000001', 'A fictional place to meet, changed', '["research"]'));
reset role;
select pg_temp.assert_draft((pg_temp.listing('e4000000-0000-4000-8000-000000000001', 'e5000000-0000-4000-8000-000000000001')).status = 'withdrawal_pending',
  'an edited saved entry still asks to withdraw its listing');
select pg_temp.assert_draft((pg_temp.listing('e4000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000003')).status = 'published',
  'a listing published from a draft never follows the saved card');
select pg_temp.assert_draft(pg_temp.refusal(format('select pg_temp.support(%L, %L, %L, %L)', 'alice', pg_temp.seen('draft')->>'id', 'support_review',
    jsonb_build_object('kind', 'need', 'entryId', 'e5000000-0000-4000-8000-000000000001', 'expectedRevision', 1,
      'expectedEntryRevision', 1, 'expiresAt', null))) = 'PT409 revision_conflict',
  'a link no saved card anchors has no saved entries to review');

-- 6. Deleting a saved card leaves its link and Weave's record of its public listing, held by the same DID.
select pg_temp.assert_draft(pg_temp.project('alice', 'link', pg_temp.own('3mdeletedcard')
    || '{"initiativeId":"e4000000-0000-4000-8000-000000000002","expectedRevision":1}'::jsonb)->>'workspaceId' = 'e4000000-0000-4000-8000-000000000002',
  'the second saved card links its own project');
select pg_temp.keep('deleted review', pg_temp.support('alice', 'e4000000-0000-4000-8000-000000000002', 'support_review', jsonb_build_object(
  'kind', 'need', 'entryId', 'e5000000-0000-4000-8000-000000000002', 'expectedRevision', 1,
  'expectedEntryRevision', pg_temp.entry_revision('e4000000-0000-4000-8000-000000000002', 'e5000000-0000-4000-8000-000000000002'),
  'expiresAt', null)));
select pg_temp.keep('deleted published', pg_temp.support('alice', 'e4000000-0000-4000-8000-000000000002', 'support_publish', jsonb_build_object(
  'requestId', 'e7000000-0000-4000-8000-000000000020', 'reviewId', pg_temp.seen('deleted review')->>'reviewId',
  'audience', 'public-atproto', 'confirmPublic', true)));
select pg_temp.support('alice', 'e4000000-0000-4000-8000-000000000002', 'support_checkpoint', jsonb_build_object('kind', 'need',
  'entryId', 'e5000000-0000-4000-8000-000000000002', 'operationId', pg_temp.seen('deleted published')->>'operationId', 'event', 'sending'));
select pg_temp.support('alice', 'e4000000-0000-4000-8000-000000000002', 'support_checkpoint', jsonb_build_object('kind', 'need',
  'entryId', 'e5000000-0000-4000-8000-000000000002', 'operationId', pg_temp.seen('deleted published')->>'operationId',
  'event', 'published', 'cid', 'b' || repeat('d', 58)));
-- The API's delete guard still refuses this card; deleting its account reaches the same foreign key.
delete from weave.initiatives where id = 'e4000000-0000-4000-8000-000000000002';
select pg_temp.assert_draft((select solo_initiative_id is null and repository_did = 'did:plc:pppppppppppppppppppppppp'
  from weave_workspace.project_links where id = 'e4000000-0000-4000-8000-000000000002'), 'the project link outlives its saved card');
select pg_temp.assert_draft((pg_temp.listing('e4000000-0000-4000-8000-000000000002', 'e5000000-0000-4000-8000-000000000002')).status = 'withdrawal_pending'
    and (pg_temp.listing('e4000000-0000-4000-8000-000000000002', 'e5000000-0000-4000-8000-000000000002')).rkey = pg_temp.seen('deleted published')->>'rkey',
  'Weave keeps the public listing''s address and asks to withdraw it with its entry gone');
select pg_temp.assert_draft(pg_temp.support('alice elsewhere', 'e4000000-0000-4000-8000-000000000002', 'support_checkpoint', jsonb_build_object(
    'kind', 'need', 'entryId', 'e5000000-0000-4000-8000-000000000002', 'operationId', pg_temp.seen('deleted published')->>'operationId',
    'event', 'withdrawn'))->>'status' = 'withdrawn', 'the DID that owns the repository finishes the withdrawal with no card');
select pg_temp.assert_draft(pg_temp.refusal(format('select pg_temp.support(%L, %L, %L, %L)', 'alice', 'e4000000-0000-4000-8000-000000000002',
    'support_review', jsonb_build_object('kind', 'need', 'entryId', 'e5000000-0000-4000-8000-000000000002', 'expectedRevision', 1,
      'expectedEntryRevision', 1, 'expiresAt', null))) = 'PT409 revision_conflict', 'a deleted card has nothing left to review');

-- 7. No new saved card may take a personal link's ID: not the deleted card's, not a draft's link.
insert into weave_workspace.project_links(id, project_uri, repository_did, cid, linked_by) values
  ('e3000000-0000-4000-8000-000000000005', 'at://did:plc:pppppppppppppppppppppppp/org.hypercerts.collection/3mcardless',
   'did:plc:pppppppppppppppppppppppp', 'bafyfixture', 'e1000000-0000-4000-8000-000000000001');
select set_config('request.jwt.claims', '{"sub":"e1000000-0000-4000-8000-000000000002","session_id":"e2000000-0000-4000-8000-000000000003","role":"authenticated","exp":4102444800}', true);
set local role authenticated;
select pg_temp.assert_draft(pg_temp.refusal(format('select pg_temp.saved_before(%L, 0, %L, %L)', c.id, c.request,
    pg_temp.card('e5000000-0000-4000-8000-000000000009', 'Someone else''s card', '[]'))) = 'PT409 revision_conflict',
  'a new saved card must not take the ID of ' || c.label)
from (values ('e4000000-0000-4000-8000-000000000002', 'e8000000-0000-4000-8000-000000000010', 'a deleted card''s link'),
  ('e3000000-0000-4000-8000-000000000005', 'e8000000-0000-4000-8000-000000000011', 'a draft''s link')) c(id, request, label);
select pg_temp.assert_draft(pg_temp.saved_before('e4000000-0000-4000-8000-000000000009', 0, 'e8000000-0000-4000-8000-000000000012',
    pg_temp.card('e5000000-0000-4000-8000-000000000009', 'Bob''s own card', '[]'))->>'revision' = '1', 'any other new card still passes the guard');
reset role;
select pg_temp.assert_draft(pg_temp.refusal($$insert into weave_workspace.project_links(id, project_uri, repository_did, solo_initiative_id, cid)
    values ('e3000000-0000-4000-8000-000000000006', 'at://did:plc:pppppppppppppppppppppppp/org.hypercerts.collection/3mmismatch',
      'did:plc:pppppppppppppppppppppppp', 'e4000000-0000-4000-8000-000000000009', 'bafyfixture')$$) like '23514 %',
  'a personal link anchored on a card has the card''s ID');
select pg_temp.assert_draft(pg_temp.refusal($$insert into weave_workspace.project_links(id, project_uri, repository_did, group_did, solo_initiative_id, cid)
    values ('e4000000-0000-4000-8000-000000000009', 'at://did:plc:rrrrrrrrrrrrrrrrrrrrrrrr/org.hypercerts.collection/3mgroupcard',
      'did:plc:rrrrrrrrrrrrrrrrrrrrrrrr', 'did:plc:rrrrrrrrrrrrrrrrrrrrrrrr', 'e4000000-0000-4000-8000-000000000009', 'bafyfixture')$$) like '23514 %',
  'a group link is never anchored on a saved card');

-- 8. A group project's editor may review from a draft too, with current membership; a viewer may not.
insert into weave_workspace.project_links(id, project_uri, repository_did, group_did, cid, linked_by) values
  ('e3000000-0000-4000-8000-000000000010', 'at://did:plc:rrrrrrrrrrrrrrrrrrrrrrrr/org.hypercerts.collection/3mgroupproject',
   'did:plc:rrrrrrrrrrrrrrrrrrrrrrrr', 'did:plc:rrrrrrrrrrrrrrrrrrrrrrrr', 'bafyfixture', 'e1000000-0000-4000-8000-000000000001');
insert into weave_workspace.access_grants(workspace_id, user_id, member_did, access_role) values
  ('e3000000-0000-4000-8000-000000000010', 'e1000000-0000-4000-8000-000000000001', 'did:plc:pppppppppppppppppppppppp', 'editor'),
  ('e3000000-0000-4000-8000-000000000010', 'e1000000-0000-4000-8000-000000000002', 'did:plc:qqqqqqqqqqqqqqqqqqqqqqqq', 'viewer');
select pg_temp.assert_draft(pg_temp.support('alice', 'e3000000-0000-4000-8000-000000000010', 'support_review',
    pg_temp.draft_review('need', 'e6000000-0000-4000-8000-000000000010', '{"title":"Group need","capitalForms":["social"]}'), 'member')
    - array['reviewId', 'reviewExpiresAt', 'record'] = jsonb_build_object('audience', 'public-atproto',
      'destination', 'did:plc:rrrrrrrrrrrrrrrrrrrrrrrr', 'expectedRevision', 0, 'expectedEntryRevision', 0),
  'a group editor with current membership reviews a draft''s need for the group''s repository');
select pg_temp.assert_draft(pg_temp.refusal(format('select pg_temp.support(%L, %L, %L, %L, %L)', 'bob', 'e3000000-0000-4000-8000-000000000010',
    'support_review', pg_temp.draft_review('need', 'e6000000-0000-4000-8000-000000000011', '{"title":"Group need","capitalForms":["social"]}'),
    'member')) = 'PT403 workspace_edit_required', 'a group viewer must not review for publishing');
select pg_temp.assert_draft(pg_temp.refusal(format('select pg_temp.support(%L, %L, %L, %L)', 'alice', 'e3000000-0000-4000-8000-000000000010',
    'support_review', pg_temp.draft_review('need', 'e6000000-0000-4000-8000-000000000012', '{"title":"Group need","capitalForms":["social"]}')))
  = 'PT404 not_found', 'a group grant without current membership opens nothing');

rollback;
