-- Candidate for the website migration owner, after weave-retire-private-saves. Not applied anywhere.
-- Apply through the website's migration path as a new migration.
--
-- DL-155, step 5, first part: matching reads published listings. It adds reads and changes nothing the
-- deployed Weave server calls, so it can be applied before the code that uses it:
-- - private.weave_current_support_listings() is the one rule for a current published listing:
--   confirmed by read-back with its CID, its stored record naming its link's project and open, not
--   expired, and its link not paused. weave_public_support_listings, behind the public initiative page,
--   now reads it and returns what it returned before.
-- - private.weave_public_project_snapshot, the public snapshot the device matches a draft against, also
--   returns other projects' current listings, only for projects the public list shows.
-- - private.weave_listing_shortlist takes one workspace's current listings as queries. For each it
--   returns other projects' current listings of the other kind that share a term, and public project
--   evidence, as the share search does for a shared entry. It reads no saved card and no share.
-- - weave_workspace.content_command gains the read-only listing_shortlist action. Viewer access is
--   enough, and the project is checked as for every other matching action. The rest of its body is the
--   one weave-team-content created, unchanged.
-- Every result is a public record Weave published and read back, its address and CID, and the project's
-- public name. Nothing about a draft, a saved card or a share is read.
do $$
begin
  if to_regprocedure('private.weave_public_support_listings(text)') is null
    or to_regprocedure('private.weave_public_project_snapshot(text)') is null
    or to_regprocedure('private.weave_public_project_shortlist(text,integer)') is null
    or to_regprocedure('private.weave_public_project_coverage()') is null
    or to_regprocedure('weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)') is null
    or to_regprocedure('weave_workspace.initiative_link_guard()') is null
    or to_regprocedure('private.weave_matching_preview(uuid,integer,jsonb,timestamptz)') is null then
    raise exception 'weave-public-support-listings, weave-publish-from-draft and weave-retire-private-saves must be installed first';
  end if;
end $$;

-- A listing is current when its publication is confirmed (`published` is set only after read-back
-- equality, with the CID read back), its stored record names its link's project and is open, and it has
-- not expired. A link paused by confirmed deletion or unlisting has none, even before its withdrawals
-- finish. Pending, withdrawing, withdrawn and conflicting publications are left out, as is any entry that
-- is saved or shared but was never published. The expiry is cast only when it has the shape Weave
-- writes, so a malformed stored value hides that listing instead of failing the read.
create function private.weave_current_support_listings()
returns table(workspace_id uuid, project_uri text, repository_did text, kind text, entry_id uuid, rkey text,
  uri text, cid text, record jsonb, updated_at timestamptz)
language sql stable set search_path = '' as $$
  select s.workspace_id, l.project_uri, l.repository_did, s.kind, s.entry_id, s.rkey,
    'at://' || l.repository_did || '/com.regencommons.weave.supportListing/' || s.rkey,
    s.cid, s.record_value, s.updated_at
  from weave_workspace.project_links l
  join weave_workspace.support_listings s on s.workspace_id = l.id
  where not l.matching_paused
    and s.status = 'published' and s.cid is not null
    and s.record_value->>'$type' = 'com.regencommons.weave.supportListing'
    and s.record_value->>'projectUri' = l.project_uri
    and s.record_value->>'kind' = s.kind
    and s.record_value->>'status' = 'open'
    and case
      when not s.record_value ? 'expiresAt' then true
      when s.record_value->>'expiresAt' ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$'
        then (s.record_value->>'expiresAt')::timestamptz > now()
      else false
    end
$$;

-- The same rows as before, now from the one rule above. A saved card holds at most five needs and five
-- offers, so the limit only bounds a damaged table.
create or replace function private.weave_public_support_listings(p_project_uri text)
returns table(kind text, rkey text, uri text, cid text, record jsonb)
language sql stable strict security definer set search_path = '' as $$
  select c.kind, c.rkey, c.uri, c.cid, c.record
  from private.weave_current_support_listings() c
  where c.project_uri = p_project_uri
  order by c.kind, c.rkey collate "C"
  limit 100
$$;

-- The project's public name when the public list shows the project, and null otherwise: listed at the
-- last complete traversal, unexpired, read within seven days and with current evidence, as
-- `shownProject` in packages/api/src/project-index-db.ts and the snapshot below decide. Every indexed
-- passage carries its project's name.
create function private.weave_shown_project_name(p_project_uri text)
returns text language sql stable strict set search_path = '' as $$
  select min(e.evidence->>'projectName')
  from private.weave_project_index_source s
  join private.weave_project_index_evidence e
    on e.project_uri = s.project_uri and e.evidence->>'projectUri' = s.project_uri and e.evidence->>'cid' = s.cid
  where s.project_uri = p_project_uri and s.status = 'indexed' and s.permission_until > now()
    and s.fetched_at >= now() - interval '7 days'
$$;

-- A listing's title and description as search terms, normalized as the public index's lexical query
-- normalizes text, so the same words match with or without accents.
create function private.weave_listing_terms(p_record jsonb)
returns tsvector language sql immutable strict set search_path = '' as $$
  select pg_catalog.to_tsvector('simple', pg_catalog.regexp_replace(
    pg_catalog.normalize(pg_catalog.left(concat_ws(' ', p_record->>'title', p_record->>'description'), 2400), 'NFKD'),
    U&'[\0300-\036F\1AB0-\1AFF\1DC0-\1DFF\20D0-\20FF\FE20-\FE2F]', '', 'g'))
$$;

-- The device's public snapshot, as weave-public-evidence-snapshot made it, with other projects' current
-- listings added: the 100 most recently confirmed, for projects the public list shows, leaving out every
-- project in the person's own repository. `listingsTruncated` says when there were more.
create or replace function private.weave_public_project_snapshot(p_own_uri text)
returns jsonb language sql stable set search_path = '' as $$
  with eligible as materialized (
    select s.project_uri, s.cid, s.fetched_at, s.permission_until
    from private.weave_project_index_source s
    where s.status = 'indexed' and s.project_uri <> p_own_uri
      and s.permission_until > statement_timestamp()
      and s.fetched_at >= statement_timestamp() - interval '7 days'
      and exists (
        select 1 from private.weave_project_index_evidence e
        where e.project_uri = s.project_uri and e.evidence->>'projectUri' = s.project_uri
          and e.evidence->>'cid' = s.cid
      )
    order by s.fetched_at desc, s.project_uri
    limit 81
  ), projects as (
    select * from eligible order by fetched_at desc, project_uri limit 80
  ), passages as (
    select p.project_uri, p.fetched_at, p.permission_until, e.id,
      e.evidence || jsonb_build_object('fetchedAt', p.fetched_at) as evidence
    from projects p
    cross join lateral (
      select e.id, e.evidence from private.weave_project_index_evidence e
      where e.project_uri = p.project_uri and e.evidence->>'projectUri' = p.project_uri
        and e.evidence->>'cid' = p.cid
      order by e.id limit 2
    ) e
  ), snapshot as (
    select coalesce(jsonb_agg(evidence order by project_uri, id), '[]'::jsonb) as evidence,
      least(statement_timestamp() + interval '5 minutes',
        min(permission_until), min(fetched_at + interval '7 days')) as available_until
    from passages
  ), listings as materialized (
    select c.kind, c.uri, c.cid, c.project_uri, n.name, c.record, c.updated_at
    from private.weave_current_support_listings() c
    cross join lateral (select private.weave_shown_project_name(c.project_uri) as name) n
    where c.project_uri <> p_own_uri and c.repository_did <> split_part(p_own_uri, '/', 3)
      and n.name is not null
    order by c.updated_at desc, c.uri
    limit 101
  ), listed as (
    select * from listings order by updated_at desc, uri limit 100
  )
  select jsonb_build_object(
    'corpusVersion', coverage->'corpusVersion', 'status', coverage->'status',
    'indexedAt', coverage->'updatedAt', 'availableUntil', snapshot.available_until,
    'truncated', (select count(*) > 80 from eligible), 'evidence', snapshot.evidence,
    'listings', (select coalesce(jsonb_agg(jsonb_build_object('kind', l.kind, 'uri', l.uri, 'cid', l.cid,
        'projectUri', l.project_uri, 'projectName', l.name, 'record', l.record) order by l.updated_at desc, l.uri),
      '[]'::jsonb) from listed l),
    'listingsTruncated', (select count(*) > 100 from listings)
  )
  from snapshot cross join lateral (select private.weave_public_project_coverage() as coverage) c;
$$;

-- One workspace's current listings, each with the other projects' current listings of the other kind
-- that share a term of three letters or more, and the public project evidence its words find. Other
-- projects in the same repository are left out, as the share search left out the same owner, and so
-- are projects the public list does not show. At most 75 listings and 80 passages per query.
create function private.weave_listing_shortlist(p_workspace uuid)
returns jsonb language plpgsql stable set search_path = '' as $$
declare own weave_workspace.project_links; query record; ts tsquery; result jsonb = '[]'::jsonb;
begin
  select * into own from weave_workspace.project_links where id = p_workspace;
  if not found then raise sqlstate 'PT404' using message = 'not_found'; end if;
  for query in
    select c.kind, c.entry_id, c.uri, c.cid, c.record from private.weave_current_support_listings() c
    where c.workspace_id = p_workspace
    order by c.kind, c.rkey collate "C"
    limit 100
  loop
    select string_agg(quote_literal(term), ' | ')::tsquery into ts
      from unnest(tsvector_to_array(private.weave_listing_terms(query.record))) term where length(term) > 2;
    result = result || jsonb_build_array(jsonb_build_object(
      'listing', jsonb_build_object('kind', query.kind, 'entryId', query.entry_id, 'uri', query.uri,
        'cid', query.cid, 'record', query.record),
      'publicEvidence', private.weave_public_project_shortlist(
        concat_ws(' ', query.record->>'title', query.record->>'description'), 80),
      'candidates', coalesce((
        select jsonb_agg(jsonb_build_object('kind', m.kind, 'uri', m.uri, 'cid', m.cid,
            'projectUri', m.project_uri, 'projectName', m.name, 'record', m.record)
          order by m.rank desc, m.updated_at desc, m.uri)
        from (
          select c.kind, c.uri, c.cid, c.project_uri, n.name, c.record, c.updated_at,
            ts_rank(private.weave_listing_terms(c.record), ts) as rank
          from private.weave_current_support_listings() c
          cross join lateral (select private.weave_shown_project_name(c.project_uri) as name) n
          where ts is not null and c.kind <> query.kind
            and c.project_uri <> own.project_uri and c.repository_did <> own.repository_did
            and n.name is not null and private.weave_listing_terms(c.record) @@ ts
          order by rank desc, c.updated_at desc, c.uri
          limit 75
        ) m
      ), '[]'::jsonb)));
  end loop;
  return jsonb_build_object('groups', result, 'externalCoverage', private.weave_public_project_coverage());
end $$;

revoke all on function private.weave_current_support_listings(), private.weave_shown_project_name(text),
  private.weave_listing_terms(jsonb), private.weave_listing_shortlist(uuid)
  from public, anon, authenticated, service_role, weave_workspace_runtime;

-- weave-team-content's command, with one new action. listing_shortlist is not in the list that needs edit
-- access, and it is not team_load or team_save, so the project is checked and matching resumes as for
-- the other matching actions. Every other line is unchanged; the suite compares the two.
create or replace function weave_workspace.content_command(
  p_actor uuid,p_session uuid,p_did text,p_id uuid,p_group_role text,p_cid text,p_action text,p_data jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare link weave_workspace.project_links; access jsonb; result jsonb;
  previous_claims text; previous_sub text;
begin
  if p_did is null or weave_workspace.weave_project_actor(p_actor,p_session) is distinct from p_did then
    raise sqlstate 'PT401' using message='sign_in_required';
  end if;
  select * into link from weave_workspace.project_links where id=p_id;
  if not found then raise sqlstate 'PT404' using message='not_found'; end if;
  -- Same lock as setup, grant and suspension. Check authority again after it.
  perform pg_advisory_xact_lock(hashtextextended('weave-project:'||link.project_uri,0));
  if weave_workspace.weave_project_actor(p_actor,p_session) is distinct from p_did then
    raise sqlstate 'PT401' using message='sign_in_required';
  end if;
  select * into link from weave_workspace.project_links where id=p_id;
  access := weave_workspace.link_result(link,p_actor,p_did,p_group_role);
  if access->>'status' <> 'linked' then raise sqlstate 'PT404' using message='not_found'; end if;
  if p_action in ('team_save','matching_preview','matching_change','matching_set_lead')
    and access->>'accessRole' not in ('editor','admin') then
    raise sqlstate 'PT403' using message='workspace_edit_required';
  end if;

  if p_action in ('team_load','team_save') and link.group_did is null then
    raise sqlstate 'PT404' using message='not_found';
  end if;
  if p_action='pause_matching' then
    if not link.matching_paused then
      update weave_workspace.project_links set matching_paused=true where id=p_id;
      update weave.initiatives set matching_summary_revision=matching_summary_revision+1 where id=p_id;
      delete from private.weave_matching_reviews where initiative_id=p_id;
    end if;
    return null;
  end if;
  if p_action not in ('team_load','team_save') then
    if not coalesce(weave_workspace.valid_project(link.project_uri,link.repository_did,p_cid),false) then
      raise sqlstate 'PT403' using message='project_verification_required';
    end if;
    if link.matching_paused or link.cid<>p_cid then
      update weave_workspace.project_links set matching_paused=false,cid=p_cid,verified_at=clock_timestamp() where id=p_id;
    end if;
  end if;

  -- Only this restricted command can enter the old matching functions.
  -- They reuse the checked actor for locking and mutation receipts.
  previous_claims := current_setting('request.jwt.claims',true);
  previous_sub := current_setting('request.jwt.claim.sub',true);
  begin
    perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'session_id',p_session,
      'role','authenticated','exp',extract(epoch from clock_timestamp()+interval '1 minute'))::text,true);
    perform set_config('request.jwt.claim.sub',p_actor::text,true);
    case p_action
      when 'team_load' then
        result := jsonb_build_object('accessRole',access->>'accessRole','saved',
          case when exists(select from weave.initiatives where team_workspace_id=p_id)
            then weave.load_initiative(p_id) end);
      when 'team_save' then
        result := private.weave_save_document(p_id,(p_data->>'expectedRevision')::integer,
          (p_data->>'requestId')::uuid,p_data->'document',true);
      when 'public_evidence' then
        result := private.weave_public_project_snapshot(link.project_uri) || jsonb_build_object('workspaceId',p_id);
      when 'matching_state' then result := private.weave_matching_state(p_id);
      when 'matching_preview' then result := private.weave_matching_preview(p_id,(p_data->>'p_revision')::integer,
        p_data->'p_entries',(p_data->>'p_expires_at')::timestamptz);
      when 'matching_change' then result := private.weave_matching_change(p_id,p_data->>'p_action',
        (p_data->>'p_request_id')::uuid,(p_data->>'p_review_id')::uuid,nullif(p_data->'p_entries','null'::jsonb));
      when 'matching_shortlist' then result := private.weave_matching_shortlist(p_id,nullif(p_data->'p_entries','null'::jsonb));
      when 'matching_leads' then result := private.weave_matching_leads(p_id);
      when 'matching_set_lead' then result := private.weave_matching_set_lead(p_id,p_data->'p_entry',
        p_data->>'p_candidate_id',p_data->>'p_disposition',(p_data->>'p_request_id')::uuid);
      when 'listing_shortlist' then result := private.weave_listing_shortlist(p_id);
      else raise sqlstate 'PT400' using message='invalid_data';
    end case;
  exception when others then
    perform set_config('request.jwt.claims',coalesce(previous_claims,''),true);
    perform set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
    raise;
  end;
  -- Hosted migration roles cannot declare custom JWT parameters in proconfig.
  -- Restore explicitly on both success and rejection; never leak the actor into
  -- a later command on the same pooled connection or transaction.
  perform set_config('request.jwt.claims',coalesce(previous_claims,''),true);
  perform set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
  return result;
end $$;
