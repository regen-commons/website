-- Disposable database only; synthetic identities, a team workspace and its card, and all fixture rows roll back.
-- DL-155, step 5: sharing for matching has ended. Searching shares and the saved and hidden partners kept on Platform
-- are refused by name through the workspace runtime. A team card still saves, and its matching state still reads
-- for publishing its saved card, until step 6. A viewer still cannot edit, and the three replaced functions keep
-- their owner and grants. This suite runs after every migration, so it cannot see the migration withdraw the shares
-- still on; the release record gives the ordered replay that shows it.
begin;
create function pg_temp.assert_ended(ok boolean, message text) returns void
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

-- The replaced functions are owned by a non-superuser and reached only by their owner, through the workspace
-- command; nobody calls them directly.
select pg_temp.assert_ended(not r.rolsuper, p.oid::regprocedure::text || ' must be created under a non-superuser')
  from pg_proc p join pg_roles r on r.oid = p.proowner
  where p.oid in ('private.weave_matching_shortlist(uuid,jsonb)'::regprocedure, 'private.weave_matching_leads(uuid)'::regprocedure,
    'private.weave_matching_set_lead(uuid,jsonb,text,text,uuid)'::regprocedure);
select pg_temp.assert_ended(not has_function_privilege(r, f, 'execute'), r || ' must not run ' || f)
  from unnest(array['anon', 'authenticated', 'service_role', 'weave_workspace_runtime', 'weave_index_job']) r,
    unnest(array['private.weave_matching_shortlist(uuid,jsonb)', 'private.weave_matching_leads(uuid)',
      'private.weave_matching_set_lead(uuid,jsonb,text,text,uuid)']) f;
select pg_temp.assert_ended(not exists(select from information_schema.routine_privileges
  where specific_schema = 'private' and routine_name in ('weave_matching_shortlist', 'weave_matching_leads', 'weave_matching_set_lead')
    and grantee = 'PUBLIC'), 'PUBLIC must not run the retired matching functions');
-- The state and the listing search stay in reach of the workspace command.
select pg_temp.assert_ended(to_regprocedure('private.weave_matching_state(uuid)') is not null
  and to_regprocedure('private.weave_listing_shortlist(uuid)') is not null, 'matching state and the listing search must remain');

-- Dana is an admin of a group's workspace and Eli a viewer of it.
insert into auth.users(id, email_confirmed_at) values
  ('e1000000-0000-4000-8000-000000000001', now()), ('e1000000-0000-4000-8000-000000000002', now());
insert into auth.sessions(id, user_id) values
  ('e2000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001'),
  ('e2000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000002');
insert into auth.identities(user_id, provider, provider_id) values
  ('e1000000-0000-4000-8000-000000000001', 'custom:certified', 'https://certified.one|did:plc:danadddddddddddddddddddd'),
  ('e1000000-0000-4000-8000-000000000002', 'custom:certified', 'https://certified.one|did:plc:elieeeeeeeeeeeeeeeeeeeee');
insert into weave_workspace.project_links(id, project_uri, repository_did, group_did, cid, linked_by) values
  ('e3000000-0000-4000-8000-000000000001', 'at://did:plc:endshareggggggggggggggggg/org.hypercerts.collection/3mendshares1',
   'did:plc:endshareggggggggggggggggg', 'did:plc:endshareggggggggggggggggg', 'bafyfixture', 'e1000000-0000-4000-8000-000000000001');
insert into weave_workspace.access_grants(workspace_id, user_id, member_did, access_role) values
  ('e3000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'did:plc:danadddddddddddddddddddd', 'admin'),
  ('e3000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000002', 'did:plc:elieeeeeeeeeeeeeeeeeeeee', 'viewer');

-- A checked card with one open need, as a team saves it.
create function pg_temp.card(p_entry uuid, p_title text) returns jsonb language sql immutable as $$
  select jsonb_build_object('version', 1,
    'initiative', jsonb_build_object('name', 'Fictional seed swap', 'description', 'Team card summary', 'locations', '[]'::jsonb,
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
-- A person's command to the group workspace, as the Weave server sends it through the workspace runtime.
create function pg_temp.team(p_person integer, p_action text, p_data jsonb) returns jsonb language sql as $$
  select weave_workspace.content_command(('e1000000-0000-4000-8000-' || lpad(p_person::text, 12, '0'))::uuid,
    ('e2000000-0000-4000-8000-' || lpad(p_person::text, 12, '0'))::uuid,
    case p_person when 1 then 'did:plc:danadddddddddddddddddddd' else 'did:plc:elieeeeeeeeeeeeeeeeeeeee' end,
    'e3000000-0000-4000-8000-000000000001', 'owner', 'bafyfixture', p_action, p_data) $$;

set local role weave_workspace_runtime;
-- 1. A team card still saves, and its matching state still reads for everyone with access (until step 6).
select pg_temp.assert_ended(pg_temp.team(1, 'team_save', jsonb_build_object('expectedRevision', 0,
    'requestId', 'e8000000-0000-4000-8000-000000000001', 'document', pg_temp.card('e5000000-0000-4000-8000-000000000001', 'Seed swap')))
  ->>'revision' = '1', 'a team card must still save');
select pg_temp.assert_ended((pg_temp.team(p, 'matching_state', '{}')->>'initiativeRevision')::int = 1
    and jsonb_array_length(pg_temp.team(p, 'matching_state', '{}')->'entries') = 1, 'matching state must still read for person ' || p)
  from unnest(array[1, 2]) p;

-- 2. Searching shares and the partners kept on Platform are refused by name, for an admin and a viewer alike.
select pg_temp.assert_ended(pg_temp.refusal(format('select pg_temp.team(%s, %L, %L)', p, a, '{}')) = 'PT410 matching_shares_retired',
    a || ' must be refused by name for person ' || p)
  from unnest(array[1, 2]) p, unnest(array['matching_shortlist', 'matching_leads']) a;
select pg_temp.assert_ended(pg_temp.refusal(format('select pg_temp.team(1, %L, %L)', 'matching_set_lead', jsonb_build_object(
    'p_entry', jsonb_build_object('kind', 'need', 'entryId', 'e5000000-0000-4000-8000-000000000001'),
    'p_candidate_id', 'public:at://did:plc:otherrrrrrrrrrrrrrrrrrrr/org.hypercerts.collection/3mother',
    'p_disposition', 'saved', 'p_request_id', 'e8000000-0000-4000-8000-000000000002')))
  = 'PT410 matching_shares_retired', 'keeping a partner on Platform must be refused by name');
-- A viewer is still refused editing first, as before.
select pg_temp.assert_ended(pg_temp.refusal(format('select pg_temp.team(2, %L, %L)', 'matching_set_lead', '{}'))
  = 'PT403 workspace_edit_required', 'a viewer must still not edit');
-- 3. The listing search answers in their place.
select pg_temp.assert_ended(pg_temp.team(2, 'listing_shortlist', '{}') ? 'groups', 'the listing search must answer');
reset role;

rollback;
