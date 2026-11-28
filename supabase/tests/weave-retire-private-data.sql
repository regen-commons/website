-- Disposable database only; synthetic identities, a team workspace and its card, and all fixture rows roll back.
-- DL-155, step 7: the personal private saves and sharing for matching are gone from Platform. The functions and
-- tables only they used are dropped, and the workspace command no longer takes sharing's actions. A group
-- project's shared team draft stays (D48): it saves, loads, reports its entries' revisions and publishes from them,
-- and an entry the team removes still queues its listing's withdrawal. This suite runs after every migration, so it
-- cannot see the migration delete the personal cards; the release record gives the ordered replay that shows it.
begin;
create function pg_temp.assert_retired(ok boolean, message text) returns void
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

-- 1. What only personal saves and sharing used is gone.
select pg_temp.assert_retired(to_regprocedure(f) is null, f || ' must be dropped')
  from unnest(array['weave.save_initiative(uuid,integer,uuid,jsonb)', 'weave.list_initiatives(integer)',
    'weave.delete_initiative(uuid,integer,uuid)', 'weave.matching_preview(uuid,integer,jsonb,timestamptz)',
    'weave.matching_change(uuid,text,uuid,uuid,jsonb)', 'weave.matching_shortlist(uuid,jsonb)', 'weave.matching_leads(uuid)',
    'weave.matching_set_lead(uuid,jsonb,text,text,uuid)', 'private.weave_save_initiative(uuid,integer,uuid,jsonb)',
    'private.weave_delete_initiative(uuid,integer,uuid)', 'private.weave_matching_preview(uuid,integer,jsonb,timestamptz)',
    'private.weave_matching_change(uuid,text,uuid,uuid,jsonb)', 'private.weave_matching_selected(uuid,jsonb)',
    'private.weave_matching_refs(jsonb,boolean)', 'private.weave_matching_retry(uuid,uuid,jsonb)',
    'private.weave_matching_shortlist(uuid,jsonb)', 'private.weave_matching_leads(uuid)',
    'private.weave_matching_set_lead(uuid,jsonb,text,text,uuid)', 'private.weave_matching_public_status(text)',
    'private.weave_matching_weave_candidate(text)', 'private.weave_matching_indexed_public_evidence(uuid,text,uuid,bigint,bigint)',
    'private.weave_matching_vector_pending(text,integer)', 'private.weave_matching_embedding_text_supported(text)',
    'private.weave_matching_embedding_text(jsonb)', 'private.weave_matching_embedding_model()',
    'private.weave_matching_terms(jsonb)', 'private.weave_matching_prune_query_vectors()']) f;
select pg_temp.assert_retired(not exists(select from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname in ('weave_matching_vector_store', 'weave_matching_projection')), 'the vector store must be dropped');
select pg_temp.assert_retired(to_regclass(t) is null, t || ' must be dropped')
  from unnest(array['private.weave_matching_leads', 'private.weave_matching_requests', 'private.weave_matching_query_vectors',
    'private.weave_matching_retrieval_settings', 'private.weave_matching_current', 'weave.needs_weave_matching_terms_idx',
    'weave.offers_weave_matching_terms_idx']) t;
select pg_temp.assert_retired(not exists(select from pg_trigger where tgname = 'prune_matching_query_vectors'),
  'the query vector prune triggers must be dropped');
select pg_temp.assert_retired(not exists(select from weave.initiatives where team_workspace_id is null),
  'no personal saved card may remain');

-- 2. What a team draft and the public listings read stays, with the deletion's trigger hold released.
select pg_temp.assert_retired(to_regprocedure(f) is not null, f || ' must remain')
  from unnest(array['weave.load_initiative(uuid)', 'weave.matching_state(uuid)', 'weave.account_access()',
    'private.weave_matching_state(uuid)', 'private.weave_matching_owner(uuid,boolean)', 'private.weave_matching_summary(jsonb)',
    'private.weave_save_document(uuid,integer,uuid,jsonb,boolean)', 'private.weave_reconcile_matching_entries(regclass,uuid,jsonb)',
    'private.weave_listing_shortlist(uuid)', 'private.weave_public_support_listings(text)']) f;
select pg_temp.assert_retired(to_regclass('private.weave_matching_entries') is not null
  and to_regclass('private.weave_matching_reviews') is not null, 'the team entries view and the reviews table must remain');
select pg_temp.assert_retired((select count(*) from information_schema.columns where table_schema = 'weave'
    and table_name in ('needs', 'offers') and column_name like 'matching\_%') = 16
  and exists(select from information_schema.columns where table_schema = 'weave_workspace' and table_name = 'project_links'
    and column_name = 'matching_paused'), 'the team entries and the project links must keep their matching columns');
select pg_temp.assert_retired(t.tgenabled = 'O', t.tgrelid::regclass || ' must queue withdrawals again')
  from pg_trigger t where t.tgname = 'support_entry_changed';
select pg_temp.assert_retired((select count(*) from pg_trigger where tgname = 'support_entry_changed') = 2,
  'both entry tables must keep support_entry_changed');
-- The replaced command keeps its owner and grants: only the workspace runtime reaches it.
select pg_temp.assert_retired(not r.rolsuper, 'content_command must be created under a non-superuser')
  from pg_proc p join pg_roles r on r.oid = p.proowner
  where p.oid = 'weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)'::regprocedure;
select pg_temp.assert_retired(has_function_privilege('weave_workspace_runtime',
    'weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)', 'execute')
  and not has_function_privilege('anon', 'weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)', 'execute'),
  'content_command must keep its grants');
select pg_temp.assert_retired(pg_get_functiondef('weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)'::regprocedure)
  !~ 'matching_(preview|change|shortlist|leads|set_lead)', 'content_command must not name sharing''s actions');

-- Dana is an admin of a group's workspace and Eli a viewer of it.
insert into auth.users(id, email_confirmed_at) values
  ('e7100000-0000-4000-8000-000000000001', now()), ('e7100000-0000-4000-8000-000000000002', now());
insert into auth.sessions(id, user_id) values
  ('e7200000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000001'),
  ('e7200000-0000-4000-8000-000000000002', 'e7100000-0000-4000-8000-000000000002');
insert into auth.identities(user_id, provider, provider_id) values
  ('e7100000-0000-4000-8000-000000000001', 'custom:certified', 'https://certified.one|did:plc:danadddddddddddddddddddd'),
  ('e7100000-0000-4000-8000-000000000002', 'custom:certified', 'https://certified.one|did:plc:elieeeeeeeeeeeeeeeeeeeee');
insert into weave_workspace.project_links(id, project_uri, repository_did, group_did, cid, linked_by) values
  ('e7300000-0000-4000-8000-000000000001', 'at://did:plc:retireggggggggggggggggggg/org.hypercerts.collection/3mretiredata1',
   'did:plc:retireggggggggggggggggggg', 'did:plc:retireggggggggggggggggggg', 'bafyfixture', 'e7100000-0000-4000-8000-000000000001');
insert into weave_workspace.access_grants(workspace_id, user_id, member_did, access_role) values
  ('e7300000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000001', 'did:plc:danadddddddddddddddddddd', 'admin'),
  ('e7300000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000002', 'did:plc:elieeeeeeeeeeeeeeeeeeeee', 'viewer');

-- A checked team card with the given open needs, as a team saves it.
create function pg_temp.card(p_needs jsonb) returns jsonb language sql immutable as $$
  select jsonb_build_object('version', 1,
    'initiative', jsonb_build_object('name', 'Fictional seed swap', 'description', 'Team card summary', 'locations', '[]'::jsonb,
      'isGlobal', false, 'links', '[]'::jsonb, 'stage', null, 'lenses', '[]'::jsonb, 'themes', '[]'::jsonb,
      'beneficiaries', '[]'::jsonb, 'languages', '[]'::jsonb),
    'needs', coalesce((select jsonb_agg(jsonb_build_object('id', n->>'id', 'value', jsonb_build_object('title', n->>'title',
      'description', 'Fictional details', 'capitalForms', jsonb_build_array('social'), 'amount', null, 'timeframe', null,
      'urgency', null, 'placeScope', 'here', 'exchangeTerms', jsonb_build_array('open'), 'purpose', null,
      'capacity', null, 'audience', null, 'status', 'open'))) from jsonb_array_elements(p_needs) n), '[]'::jsonb),
    'offers', '[]'::jsonb,
    'funding', jsonb_build_object('form', jsonb_build_object('workCountries', '', 'benefitCountries', '', 'applicantBaseCountry', '',
      'registrationCountry', '', 'applicantType', 'unknown', 'fundingInstruments', '[]'::jsonb, 'goalMin', '', 'goalMax', '',
      'currency', '', 'usWorkStates', '', 'usBenefitStates', ''), 'programAnswers', '{}'::jsonb)) $$;
-- A person's command to the group workspace, as the Weave server sends it through the workspace runtime.
create function pg_temp.team(p_person integer, p_action text, p_data jsonb) returns jsonb language sql as $$
  select weave_workspace.content_command(('e7100000-0000-4000-8000-' || lpad(p_person::text, 12, '0'))::uuid,
    ('e7200000-0000-4000-8000-' || lpad(p_person::text, 12, '0'))::uuid,
    case p_person when 1 then 'did:plc:danadddddddddddddddddddd' else 'did:plc:elieeeeeeeeeeeeeeeeeeeee' end,
    'e7300000-0000-4000-8000-000000000001', 'owner', 'bafyfixture', p_action, p_data) $$;
create function pg_temp.support(p_action text, p_data jsonb) returns jsonb language sql as $$
  select weave_workspace.support_command('e7100000-0000-4000-8000-000000000001', 'e7200000-0000-4000-8000-000000000001',
    'did:plc:danadddddddddddddddddddd', 'e7300000-0000-4000-8000-000000000001', 'owner', 'bafyfixture', p_action, p_data) $$;

set local role weave_workspace_runtime;
-- 3. The team draft saves for an admin, and loads and reports its entries for an admin and a viewer alike.
select pg_temp.assert_retired(pg_temp.team(1, 'team_save', jsonb_build_object('expectedRevision', 0,
    'requestId', 'e7800000-0000-4000-8000-000000000001', 'document', pg_temp.card(jsonb_build_array(
      jsonb_build_object('id', 'e7500000-0000-4000-8000-000000000001', 'title', 'Seed swap'),
      jsonb_build_object('id', 'e7500000-0000-4000-8000-000000000002', 'title', 'Drying racks')))))
  ->>'revision' = '1', 'a team draft must still save');
select pg_temp.assert_retired((pg_temp.team(p, 'team_load', '{}')->'saved'->>'revision')::int = 1
    and (pg_temp.team(p, 'matching_state', '{}')->>'initiativeRevision')::int = 1
    and jsonb_array_length(pg_temp.team(p, 'matching_state', '{}')->'entries') = 2, 'the team draft must read for person ' || p)
  from unnest(array[1, 2]) p;
select pg_temp.assert_retired(pg_temp.refusal(format('select pg_temp.team(2, %L, %L)', 'team_save', jsonb_build_object(
    'expectedRevision', 1, 'requestId', 'e7800000-0000-4000-8000-000000000002', 'document', pg_temp.card('[]'))))
  = 'PT403 workspace_edit_required', 'a viewer must still not edit the team draft');
select pg_temp.assert_retired(pg_temp.team(2, 'listing_shortlist', '{}') ? 'groups', 'the listing search must answer');
-- 4. Sharing's actions are not commands any more, for an admin and a viewer alike.
select pg_temp.assert_retired(pg_temp.refusal(format('select pg_temp.team(%s, %L, %L)', p, a, '{}')) = 'PT400 invalid_data',
    a || ' must not be a command for person ' || p)
  from unnest(array[1, 2]) p, unnest(array['matching_preview', 'matching_change', 'matching_shortlist', 'matching_leads',
    'matching_set_lead']) a;

-- 5. The team publishes a saved entry at the revision matching state reports.
create temporary table team_entry on commit drop as
  select e->>'entryId' entry_id, (e->>'revision')::bigint revision
  from jsonb_array_elements(pg_temp.team(1, 'matching_state', '{}')->'entries') e;
grant select on team_entry to weave_workspace_runtime;
select pg_temp.assert_retired(pg_temp.support('support_review', jsonb_build_object('kind', 'need',
    'entryId', 'e7500000-0000-4000-8000-000000000001', 'expectedRevision', 1,
    'expectedEntryRevision', (select revision from team_entry where entry_id = 'e7500000-0000-4000-8000-000000000001')))
  ->>'expectedEntryRevision' = (select revision::text from team_entry where entry_id = 'e7500000-0000-4000-8000-000000000001'),
  'a team entry must be reviewed for publishing at its matching revision');
select pg_temp.assert_retired(pg_temp.refusal(format('select pg_temp.support(%L, %L)', 'support_review', jsonb_build_object('kind', 'need',
    'entryId', 'e7500000-0000-4000-8000-000000000001', 'expectedRevision', 1, 'expectedEntryRevision', 0)))
  = 'PT409 entry_conflict', 'a stale entry revision must conflict');
reset role;

-- 6. A listing published from the team draft is withdrawn when the team removes its entry: the trigger the deletion
-- held off is on again.
insert into weave_workspace.support_listings(workspace_id, kind, entry_id, rkey, operation_id, actor_id, entry_revision,
    record_value, status, cid, source)
  select 'e7300000-0000-4000-8000-000000000001', 'need', 'e7500000-0000-4000-8000-000000000002', '3mretireaaaaa', gen_random_uuid(),
    'e7100000-0000-4000-8000-000000000001', revision, '{}', 'published', 'b' || repeat('r', 58), 'saved'
  from team_entry where entry_id = 'e7500000-0000-4000-8000-000000000002';
set local role weave_workspace_runtime;
select pg_temp.team(1, 'team_save', jsonb_build_object('expectedRevision', 1, 'requestId', 'e7800000-0000-4000-8000-000000000003',
  'document', pg_temp.card(jsonb_build_array(jsonb_build_object('id', 'e7500000-0000-4000-8000-000000000001', 'title', 'Seed swap')))));
reset role;
select pg_temp.assert_retired((select status from weave_workspace.support_listings
    where workspace_id = 'e7300000-0000-4000-8000-000000000001' and entry_id = 'e7500000-0000-4000-8000-000000000002')
  = 'withdrawal_pending', 'removing a published team entry must queue its withdrawal');

rollback;
