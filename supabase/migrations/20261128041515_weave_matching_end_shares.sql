-- Candidate for the website migration owner, after weave-matching-published-listings. Not applied anywhere.
-- Apply through the website's migration path as a new migration, after the Weave API that refuses searching
-- shares, saved partners and withdrawal is deployed.
--
-- DL-155, step 5, second part: sharing for matching ends. Published listings took over matching in
-- weave-matching-published-listings, and Weave's API refuses searching shares, the saved and hidden partners kept
-- here, and withdrawing a share. This ends what is left on Platform, silently, as the user decided on
-- 27 November 2026:
-- - Every share still on is withdrawn, each with a new share version, so the prune triggers drop its query vectors
--   and private.weave_matching_current is left empty. With nothing current, the embedding job finds nothing to
--   embed. The entries, their values and their published listings are untouched.
-- - private.weave_matching_shortlist, weave_matching_leads and weave_matching_set_lead refuse by name, PT410
--   matching_shares_retired, as the API does. Partners are kept on the device's shortlist instead.
-- Unchanged: private.weave_matching_state, which publishing a team's saved card reads until step 6, and the
-- withdraw branch of weave_matching_change, which answers a replay as before. The tables and columns, and any
-- rows in them, stay until step 7 removes them.
do $$
begin
  if to_regprocedure('private.weave_listing_shortlist(uuid)') is null
    or to_regprocedure('private.weave_matching_state(uuid)') is null
    or to_regprocedure('private.weave_matching_shortlist(uuid,jsonb)') is null
    or to_regprocedure('private.weave_matching_leads(uuid)') is null
    or to_regprocedure('private.weave_matching_set_lead(uuid,jsonb,text,text,uuid)') is null
    or to_regclass('private.weave_matching_version') is null then
    raise exception 'weave-matching-published-listings and weave-team-content must be installed first';
  end if;
end $$;

-- Save, share, withdraw and the embedding job's store take each card's row lock. Taking it first makes a store
-- that starts now wait until this commits, then find nothing shared and store nothing.
do $$
begin
  perform from weave.initiatives i
  where exists(select from weave.needs n where n.initiative_id = i.id and n.matching_audience is not null and not n.matching_withdrawn)
    or exists(select from weave.offers o where o.initiative_id = i.id and o.matching_audience is not null and not o.matching_withdrawn)
  for update;
end $$;

-- Every share still on ends, whether current, expired or changed since it was shared. A new share version marks
-- the change, as a withdrawal always has, and the prune triggers drop the entry's query vectors.
update weave.needs set matching_withdrawn = true,
  matching_share_version = nextval('private.weave_matching_version')
where matching_audience is not null and not matching_withdrawn;
update weave.offers set matching_withdrawn = true,
  matching_share_version = nextval('private.weave_matching_version')
where matching_audience is not null and not matching_withdrawn;

-- Nobody searches shares any more. It reads nothing and writes nothing, so it runs as the caller.
create or replace function private.weave_matching_shortlist(p_id uuid, p_entries jsonb)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
begin
  raise sqlstate 'PT410' using message = 'matching_shares_retired';
end $$;

-- Saved and hidden partners are no longer kept here; a partner is kept on the device's shortlist.
create or replace function private.weave_matching_leads(p_id uuid)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
begin
  raise sqlstate 'PT410' using message = 'matching_shares_retired';
end $$;

create or replace function private.weave_matching_set_lead(
  p_id uuid, p_entry jsonb, p_candidate_id text, p_disposition text, p_request_id uuid
) returns jsonb language plpgsql volatile security invoker set search_path = '' as $$
begin
  raise sqlstate 'PT410' using message = 'matching_shares_retired';
end $$;
