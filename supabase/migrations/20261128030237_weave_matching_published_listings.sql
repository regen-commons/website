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
-- - private.weave_listing_shortlist takes one workspace's ten most recent current listings as queries. For
--   each it returns other projects' current listings of the other kind that share a word, and public project
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
-- is saved or shared but was never published. An expiry is cast only when it has the shape Weave writes
-- and is a real time, so a damaged stored value hides that listing instead of failing every read. With a
-- project, only that project's listings are read.
create function private.weave_current_support_listings(p_project_uri text default null)
returns table(workspace_id uuid, project_uri text, repository_did text, kind text, entry_id uuid, rkey text,
  uri text, cid text, record jsonb, created text)
language sql stable set search_path = '' as $$
  select s.workspace_id, l.project_uri, l.repository_did, s.kind, s.entry_id, s.rkey,
    'at://' || l.repository_did || '/com.regencommons.weave.supportListing/' || s.rkey,
    s.cid, s.record_value, s.record_value->>'createdAt'
  from weave_workspace.project_links l
  join weave_workspace.support_listings s on s.workspace_id = l.id
  where (p_project_uri is null or l.project_uri = p_project_uri)
    and not l.matching_paused
    and s.status = 'published' and s.cid is not null
    and s.record_value->>'$type' = 'com.regencommons.weave.supportListing'
    and s.record_value->>'projectUri' = l.project_uri
    and s.record_value->>'kind' = s.kind
    and s.record_value->>'status' = 'open'
    and case
      when not s.record_value ? 'expiresAt' then true
      when s.record_value->>'expiresAt' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?Z$'
        and pg_catalog.pg_input_is_valid(s.record_value->>'expiresAt', 'timestamptz')
        then (s.record_value->>'expiresAt')::timestamptz > now()
      else false
    end
$$;

-- The same rows as before, now from the one rule above. A project publishing from its draft may hold more
-- than the five needs and five offers a saved card held, so the page shows at most 100.
create or replace function private.weave_public_support_listings(p_project_uri text)
returns table(kind text, rkey text, uri text, cid text, record jsonb)
language sql stable strict security definer set search_path = '' as $$
  select c.kind, c.rkey, c.uri, c.cid, c.record
  from private.weave_current_support_listings(p_project_uri) c
  order by c.kind, c.rkey collate "C"
  limit 100
$$;

-- The projects the public list shows, each with its public name: listed at the last complete traversal,
-- unexpired, read within seven days and with current evidence, as `shownProject` in
-- packages/api/src/project-index-db.ts and the snapshot below decide. Every indexed passage carries its
-- project's name. Read once per search, it is joined to the listings rather than looked up for each.
create function private.weave_shown_projects()
returns table(project_uri text, name text) language sql stable set search_path = '' as $$
  select s.project_uri, min(e.evidence->>'projectName')
  from private.weave_project_index_source s
  join private.weave_project_index_evidence e
    on e.project_uri = s.project_uri and e.evidence->>'projectUri' = s.project_uri and e.evidence->>'cid' = s.cid
  where s.status = 'indexed' and s.permission_until > now() and s.fetched_at >= now() - interval '7 days'
  group by s.project_uri
$$;

-- A listing's title and description as search terms, normalized as the public index's lexical query
-- normalizes text, so the same words match with or without accents.
create function private.weave_listing_terms(p_record jsonb)
returns tsvector language sql immutable strict set search_path = '' as $$
  select pg_catalog.to_tsvector('simple', pg_catalog.regexp_replace(
    pg_catalog.normalize(pg_catalog.left(concat_ws(' ', p_record->>'title', p_record->>'description'), 2400), 'NFKD'),
    U&'[\0300-\036F\1AB0-\1AFF\1DC0-\1DFF\20D0-\20FF\FE20-\FE2F]', '', 'g'))
$$;

-- The words a listing is searched by: the first eight of its terms of three letters or more, in the order
-- they appear, title first, leaving out the words too common to show a fit. Each word widens the public
-- evidence search, so eight keep a search of ten listings near a second on Platform's index. The common
-- words are PARTNER_GENERIC_TERMS in packages/api/src/partner-matcher.ts, which ranks the results; a test
-- there keeps the two equal.
create function private.weave_listing_query_terms(p_record jsonb)
returns text[] language sql immutable strict set search_path = '' as $$
  select coalesce(array_agg(lexeme order by first_position, lexeme), '{}') from (
    select t.lexeme, t.positions[1] as first_position
    from unnest(private.weave_listing_terms(p_record)) t
    where length(t.lexeme) > 2 and t.lexeme <> all (array[
    'about', 'across', 'after', 'all', 'also', 'and', 'another', 'any', 'anyone', 'are', 'area', 'around',
    'assistance', 'available', 'before', 'been', 'being', 'both', 'but', 'can', 'could', 'development', 'did',
    'doing', 'each', 'enable', 'enough', 'even', 'every', 'first', 'for', 'from', 'give', 'good', 'group', 'had',
    'has', 'have', 'help', 'here', 'how', 'initiative', 'into', 'its', 'just', 'kind', 'local', 'looking', 'make',
    'may', 'might', 'more', 'most', 'must', 'need', 'needs', 'offer', 'offers', 'only', 'other', 'our', 'ours',
    'out', 'over', 'part', 'people', 'please', 'project', 'provide', 'public', 'relevant', 'same', 'seeking',
    'services', 'should', 'some', 'such', 'support', 'team', 'than', 'that', 'the', 'their', 'them', 'then',
    'there', 'these', 'they', 'this', 'those', 'through', 'together', 'too', 'under', 'until', 'very', 'want',
    'was', 'way', 'well', 'were', 'what', 'when', 'where', 'which', 'while', 'will', 'with', 'within', 'work',
    'working', 'would', 'you', 'your'
    ])
    order by t.positions[1], t.lexeme
    limit 8
  ) first_words
$$;

-- The device's public snapshot, as weave-public-evidence-snapshot made it, with other projects' current
-- listings added: the 100 most recently created, at most ten from any one project, for projects the public
-- list shows, leaving out every project in the person's own repository. `listingsTruncated` says when there
-- were more.
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
    select * from (
      select c.kind, c.uri, c.cid, c.project_uri, n.name, c.record, c.created,
        row_number() over (partition by c.project_uri order by c.created desc nulls last, c.uri) as per_project
      from private.weave_current_support_listings() c
      join private.weave_shown_projects() n on n.project_uri = c.project_uri
      where c.project_uri <> p_own_uri and c.repository_did <> split_part(p_own_uri, '/', 3)
        and n.name is not null
    ) ranked
    where per_project <= 10
    order by created desc nulls last, uri
    limit 101
  ), listed as (
    select * from listings order by created desc nulls last, uri limit 100
  )
  select jsonb_build_object(
    'corpusVersion', coverage->'corpusVersion', 'status', coverage->'status',
    'indexedAt', coverage->'updatedAt', 'availableUntil', snapshot.available_until,
    'truncated', (select count(*) > 80 from eligible), 'evidence', snapshot.evidence,
    'listings', (select coalesce(jsonb_agg(jsonb_build_object('kind', l.kind, 'uri', l.uri, 'cid', l.cid,
        'projectUri', l.project_uri, 'projectName', l.name, 'record', l.record) order by l.created desc nulls last, l.uri),
      '[]'::jsonb) from listed l),
    'listingsTruncated', (select count(*) > 100 from listings)
  )
  from snapshot cross join lateral (select private.weave_public_project_coverage() as coverage) c;
$$;

-- One workspace's ten most recent current listings, each with the other projects' current listings of the
-- other kind that share one of its search words, and the public project evidence those words find. Other
-- projects in the same repository are left out, as the share search left out the same owner, and so are
-- projects the public list does not show. Other projects' listings are read once for the whole search. At
-- most 75 listings and 80 passages per query.
create function private.weave_listing_shortlist(p_workspace uuid)
returns jsonb language sql stable set search_path = '' as $$
  with own as (
    select l.project_uri, l.repository_did from weave_workspace.project_links l where l.id = p_workspace
  ), queries as (
    select c.kind, c.entry_id, c.uri, c.cid, c.record, private.weave_listing_query_terms(c.record) as terms
    from own o cross join lateral private.weave_current_support_listings(o.project_uri) c
    where c.workspace_id = p_workspace
    order by c.created desc nulls last, c.uri
    limit 10
  ), searched as (
    select q.*, case when cardinality(q.terms) > 0 then array_to_string(
        array(select quote_literal(term) from unnest(q.terms) term), ' | ')::tsquery end as query
    from queries q
  ), others as materialized (
    select c.kind, c.uri, c.cid, c.project_uri, n.name, c.record, c.created,
      private.weave_listing_terms(c.record) as document
    from own o cross join private.weave_current_support_listings() c
    join private.weave_shown_projects() n on n.project_uri = c.project_uri
    where c.project_uri <> o.project_uri and c.repository_did <> o.repository_did and n.name is not null
  )
  select jsonb_build_object(
    'groups', coalesce((select jsonb_agg(jsonb_build_object(
        'listing', jsonb_build_object('kind', s.kind, 'entryId', s.entry_id, 'uri', s.uri, 'cid', s.cid, 'record', s.record),
        'publicEvidence', case when s.query is null then '[]'::jsonb
          else private.weave_public_project_shortlist(array_to_string(s.terms, ' '), 80) end,
        'candidates', coalesce((
          select jsonb_agg(jsonb_build_object('kind', m.kind, 'uri', m.uri, 'cid', m.cid,
              'projectUri', m.project_uri, 'projectName', m.name, 'record', m.record)
            order by m.rank desc, m.created desc nulls last, m.uri)
          from (
            select o.*, ts_rank(o.document, s.query) as rank from others o
            where s.query is not null and o.kind <> s.kind and o.document @@ s.query
            order by rank desc, o.created desc nulls last, o.uri
            limit 75
          ) m
        ), '[]'::jsonb))
      order by s.kind, s.uri) from searched s), '[]'::jsonb),
    'externalCoverage', private.weave_public_project_coverage())
$$;

revoke all on function private.weave_current_support_listings(text), private.weave_shown_projects(),
  private.weave_listing_terms(jsonb), private.weave_listing_query_terms(jsonb), private.weave_listing_shortlist(uuid)
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
