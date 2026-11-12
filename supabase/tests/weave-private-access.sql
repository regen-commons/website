-- Disposable PostgreSQL only. All identities are synthetic and all changes roll back.
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception '%',message;end if;end$$;
create function pg_temp.expect_error(statement text,expected text) returns void language plpgsql as $$begin begin execute statement;exception when others then if sqlstate=expected then return;end if;raise;end;raise exception 'Expected SQLSTATE %',expected;end$$;
create function pg_temp.document() returns jsonb language sql immutable as $doc$ select '{"version": 1, "initiative": {"name": "Synthetic river circle", "description": "Restoring water and sharing skills", "locations": ["Upper valley"], "isGlobal": false, "links": [], "stage": null, "lenses": [], "themes": [], "beneficiaries": [], "languages": []}, "needs": [{"id": "b4000000-0000-4000-8000-000000000001", "value": {"title": "Seedlings and tools", "description": null, "capitalForms": ["living", "material", "intellectual", "experiential", "social", "financial", "cultural", "spiritual"], "amount": {"min": 5000, "max": 10000, "currency": "BRL"}, "timeframe": "November 2026", "urgency": "now", "placeScope": "region", "exchangeTerms": ["gift", "exchange"], "purpose": "Plant seedlings", "capacity": null, "audience": null, "status": "open"}}], "offers": [{"id": "b4000000-0000-4000-8000-000000000002", "value": {"title": "Water mapping workshop", "description": null, "capitalForms": ["experiential", "intellectual"], "amount": null, "timeframe": null, "urgency": null, "placeScope": "region", "exchangeTerms": ["gift", "exchange"], "purpose": null, "capacity": "Monthly", "audience": "Local growers", "status": "open"}}], "funding": {"form": {"workCountries": "", "benefitCountries": "", "applicantBaseCountry": "", "registrationCountry": "", "goalMin": "", "goalMax": "", "currency": "", "usWorkStates": "", "usBenefitStates": "", "applicantType": "unknown", "fundingInstruments": []}, "programAnswers": {}}}'::jsonb $doc$;
insert into auth.users(id,email,raw_user_meta_data) values
('b1000000-0000-4000-8000-000000000001','weave-owner@example.test','{}'),
('b1000000-0000-4000-8000-000000000002','weave-other@example.test','{"owner":true,"steward":true}'),
('b1000000-0000-4000-8000-000000000003','weave-steward@example.test','{}');
update auth.users set email_confirmed_at=now();
-- Trusted Certified identity, including an account with no email address.
insert into auth.identities(user_id,provider,provider_id) values
('b1000000-0000-4000-8000-000000000001','custom:certified','https://certified.one|did:plc:aaaaaaaaaaaaaaaaaaaaaaaa'),
('b1000000-0000-4000-8000-000000000002','custom:certified','https://certified.one|did:plc:bbbbbbbbbbbbbbbbbbbbbbbb'),
('b1000000-0000-4000-8000-000000000003','custom:certified','https://certified.one|did:plc:cccccccccccccccccccccccc');
update auth.users set email=null,email_confirmed_at=null where id='b1000000-0000-4000-8000-000000000001';
insert into auth.sessions(id,user_id,not_after) values
('b2000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001',now()+interval '1 hour'),
('b2000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000002',now()+interval '1 hour'),
('b2000000-0000-4000-8000-000000000003','b1000000-0000-4000-8000-000000000003',now()+interval '1 hour');
insert into private.steward_roles(user_id,active) values('b1000000-0000-4000-8000-000000000003',true);
set local role anon;
select pg_temp.expect_error($q$select weave.account_access()$q$,'42501');
select pg_temp.expect_error($q$select * from weave.initiatives$q$,'42501');
select pg_temp.expect_error($q$select * from weave.needs$q$,'42501');
select pg_temp.expect_error($q$select weave.save_initiative(gen_random_uuid(),0,gen_random_uuid(),pg_temp.document())$q$,'42501');
reset role;
select set_config('request.jwt.claims', ('{"sub":"b1000000-0000-4000-8000-000000000001","session_id":"b2000000-0000-4000-8000-000000000001","role":"authenticated"}'::jsonb || jsonb_build_object('exp',extract(epoch from now())+3600))::text,true);
set local role authenticated;
select pg_temp.assert_true(weave.account_access(),'owner session denied');
select pg_temp.assert_true((weave.save_initiative('b3000000-0000-4000-8000-000000000001',0,'b5000000-0000-4000-8000-000000000001',pg_temp.document())->>'revision')::int=1,'initial revision wrong');
select pg_temp.assert_true((select count(*)=1 from weave.initiatives),'owner cannot read initiative');
select pg_temp.assert_true((select count(*)=1 from weave.needs),'needs missing');
select pg_temp.assert_true((select count(*)=1 from weave.offers),'offers missing');
select pg_temp.assert_true((weave.load_initiative('b3000000-0000-4000-8000-000000000001')->'document')=pg_temp.document(),'saved data did not roundtrip');
select pg_temp.assert_true(jsonb_array_length(weave.list_initiatives())=1,'owner list wrong');
select pg_temp.assert_true((weave.save_initiative('b3000000-0000-4000-8000-000000000001',0,'b5000000-0000-4000-8000-000000000001',pg_temp.document())->>'revision')::int=1,'retry created a second save');
select pg_temp.expect_error($q$select weave.save_initiative('b3000000-0000-4000-8000-000000000001',0,'b5000000-0000-4000-8000-000000000001',jsonb_set(pg_temp.document(),'{initiative,name}','"Changed"'))$q$,'PT409');
select pg_temp.expect_error($q$select weave.save_initiative('b3000000-0000-4000-8000-000000000001',0,gen_random_uuid(),pg_temp.document())$q$,'PT409');
select pg_temp.expect_error($q$update weave.initiatives set visibility='public'$q$,'42501');
select pg_temp.expect_error($q$delete from weave.needs$q$,'42501');
select pg_temp.expect_error($q$insert into weave.accounts(user_id) values(auth.uid())$q$,'42501');
select pg_temp.expect_error($q$select * from private.weave_save_requests$q$,'42501');
select pg_temp.expect_error($q$select weave.save_initiative(gen_random_uuid(),0,gen_random_uuid(),pg_temp.document()||'{"owner_id":"spoofed"}')$q$,'PT400');
select pg_temp.expect_error($q$select weave.save_initiative(gen_random_uuid(),0,gen_random_uuid(),pg_temp.document()||'{"attachments":["private file"]}')$q$,'PT400');
select pg_temp.expect_error($q$select weave.save_initiative(gen_random_uuid(),0,gen_random_uuid(),jsonb_set(pg_temp.document(),'{needs,0,value,placeScope}','null'))$q$,'PT400');
select pg_temp.expect_error($q$select weave.save_initiative(gen_random_uuid(),0,gen_random_uuid(),jsonb_set(pg_temp.document(),'{needs,0,value,capitalForms}','["unknown"]'))$q$,'PT400');
select pg_temp.expect_error($q$select weave.save_initiative(gen_random_uuid(),0,gen_random_uuid(),jsonb_set(pg_temp.document(),'{needs,0,value,exchangeTerms}','["open","gift"]'))$q$,'PT400');
select pg_temp.expect_error($q$select weave.save_initiative(gen_random_uuid(),0,gen_random_uuid(),jsonb_set(pg_temp.document(),'{needs,0,value,amount,currency}','null'))$q$,'PT400');
select pg_temp.expect_error($q$select weave.save_initiative(gen_random_uuid(),0,gen_random_uuid(),jsonb_set(pg_temp.document(),'{needs,0,value,amount,min}','11000'))$q$,'PT400');
select pg_temp.expect_error($q$select weave.save_initiative(gen_random_uuid(),0,gen_random_uuid(),jsonb_set(pg_temp.document(),'{initiative,links}','["javascript:alert(1)"]'))$q$,'PT400');
select pg_temp.assert_true((weave.save_initiative('b3000000-0000-4000-8000-000000000001',1,'b5000000-0000-4000-8000-000000000002',jsonb_set(pg_temp.document(),'{initiative,name}','"Updated circle"'))->>'revision')::int=2,'update revision wrong');
select pg_temp.expect_error($q$select weave.save_initiative('b3000000-0000-4000-8000-000000000001',1,gen_random_uuid(),pg_temp.document())$q$,'PT409');
select weave.save_initiative('b3000000-0000-4000-8000-000000000001',0,'b5000000-0000-4000-8000-000000000001',pg_temp.document());
select pg_temp.assert_true(weave.load_initiative('b3000000-0000-4000-8000-000000000001')->'document'->'initiative'->>'name'='Updated circle','replayed old command rewrote newer data');
reset role;
select set_config('request.jwt.claims', ('{"sub":"b1000000-0000-4000-8000-000000000002","session_id":"b2000000-0000-4000-8000-000000000002","role":"authenticated","user_metadata":{"steward":true,"owner_id":"b1000000-0000-4000-8000-000000000001"}}'::jsonb || jsonb_build_object('exp',extract(epoch from now())+3600))::text,true);
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from weave.initiatives),'another account read a private initiative');
select pg_temp.assert_true((select count(*)=0 from weave.needs),'another account read private needs');
select pg_temp.assert_true(jsonb_array_length(weave.list_initiatives())=0,'another account saw names');
select pg_temp.expect_error($q$select weave.load_initiative('b3000000-0000-4000-8000-000000000001')$q$,'PT404');
select pg_temp.expect_error($q$select weave.save_initiative('b3000000-0000-4000-8000-000000000001',2,gen_random_uuid(),pg_temp.document())$q$,'PT404');
reset role;
select set_config('request.jwt.claims', ('{"sub":"b1000000-0000-4000-8000-000000000003","session_id":"b2000000-0000-4000-8000-000000000003","role":"authenticated"}'::jsonb || jsonb_build_object('exp',extract(epoch from now())+3600))::text,true);
set local role authenticated;
select pg_temp.assert_true(public.steward_access(),'fixture steward is not active');
select pg_temp.assert_true((select count(*)=0 from weave.initiatives),'active steward read a private initiative');
select pg_temp.expect_error($q$select weave.load_initiative('b3000000-0000-4000-8000-000000000001')$q$,'PT404');
reset role;
select set_config('request.jwt.claims', ('{"sub":"b1000000-0000-4000-8000-000000000001","session_id":"b2000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":true}'::jsonb || jsonb_build_object('exp',extract(epoch from now())+3600))::text,true);
set local role authenticated;
select pg_temp.assert_true(not weave.account_access(),'anonymous Auth session accepted');
select pg_temp.expect_error($q$select weave.list_initiatives()$q$,'PT401');
reset role;
update auth.sessions set not_after=now()-interval '1 minute' where id='b2000000-0000-4000-8000-000000000001';
select set_config('request.jwt.claims', ('{"sub":"b1000000-0000-4000-8000-000000000001","session_id":"b2000000-0000-4000-8000-000000000001","role":"authenticated"}'::jsonb || jsonb_build_object('exp',extract(epoch from now())+3600))::text,true);
set local role authenticated;
select pg_temp.assert_true(not weave.account_access(),'expired session accepted');
select pg_temp.assert_true((select count(*)=0 from weave.initiatives),'expired session read rows');
select pg_temp.expect_error($q$select weave.save_initiative(gen_random_uuid(),0,gen_random_uuid(),pg_temp.document())$q$,'PT401');
reset role;
delete from auth.sessions where id='b2000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.assert_true(not weave.account_access(),'revoked session accepted');
select pg_temp.expect_error($q$select weave.load_initiative('b3000000-0000-4000-8000-000000000001')$q$,'PT401');
reset role;
select pg_temp.assert_true((select bool_and(relrowsecurity) from pg_class where relnamespace='weave'::regnamespace and relkind='r'),'RLS missing');
select pg_temp.assert_true(not exists(select 1 from pg_proc where pronamespace='weave'::regnamespace and prosecdef),'exposed definer function');
select pg_temp.assert_true(not has_function_privilege('anon','weave.save_initiative(uuid,integer,uuid,jsonb)','execute'),'anonymous command grant');
select pg_temp.assert_true((select count(*)=0 from public.members),'saving promoted membership');
-- Confirmed email and editable metadata cannot replace a trusted identity.
delete from auth.identities where user_id='b1000000-0000-4000-8000-000000000002';
update auth.users set raw_user_meta_data='{"provider":"custom:certified","did":"did:plc:bbbbbbbbbbbbbbbbbbbbbbbb"}'
where id='b1000000-0000-4000-8000-000000000002';
select set_config('request.jwt.claims', ('{"sub":"b1000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"b2000000-0000-4000-8000-000000000002"}'::jsonb || jsonb_build_object('exp',extract(epoch from now())+3600))::text,true);
set local role authenticated;
select pg_temp.assert_true(not weave.account_access(),'email or editable metadata substituted for Certified identity');
reset role;
-- The shared schema adds no direct workspace command capability to clients.
select pg_temp.assert_true(not has_function_privilege('authenticated','weave_workspace.command(uuid,uuid,text,text,jsonb)','execute'),'authenticated workspace bypass');
select pg_temp.assert_true(not has_function_privilege('anon','weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)','execute'),'anonymous team content bypass');
select pg_temp.assert_true(not has_table_privilege('weave_platform_bridge','weave.initiatives','select'),'bridge reads private initiatives');
select pg_temp.assert_true(not has_table_privilege('weave_platform_app','weave.initiatives','select'),'app-auth login reads initiatives');
select pg_temp.assert_true((select not hybrid_enabled from private.weave_matching_retrieval_settings where singleton),'hybrid retrieval enabled');
-- Quota is charged only for new acknowledged commands. Replays remain free.
reset role;
update private.weave_save_limits set total=30;
set local role authenticated;
select set_config('request.jwt.claims', ('{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b2000000-0000-4000-8000-000000000001"}'::jsonb || jsonb_build_object('exp',extract(epoch from now())+3600))::text,true);
-- The earlier owner session was revoked in this suite; restore a synthetic session below.
reset role;
insert into auth.sessions(id,user_id) values('b2000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.expect_error($q$select weave.save_initiative('b3000000-0000-4000-8000-000000000001',2,'b5000000-0000-4000-8000-000000000099',pg_temp.document())$q$,'PT429');
select pg_temp.assert_true((weave.save_initiative('b3000000-0000-4000-8000-000000000001',0,'b5000000-0000-4000-8000-000000000001',pg_temp.document())->>'revision')::int=1,'retry charged quota');
reset role;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b2000000-0000-4000-8000-000000000001","exp":1}',true);
set local role authenticated;
select pg_temp.assert_true(not weave.account_access(),'expired JWT accepted');
reset role;
select set_config('request.jwt.claims', ('{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b2000000-0000-4000-8000-000000000001"}'::jsonb || jsonb_build_object('exp',extract(epoch from now())+3600))::text,true);
update auth.users set banned_until=now()+interval '1 hour' where id='b1000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.assert_true(not weave.account_access(),'banned account accepted');
reset role;
update auth.users set banned_until=null,is_anonymous=true where id='b1000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.assert_true(not weave.account_access(),'anonymous stored user accepted');
reset role;
rollback;
