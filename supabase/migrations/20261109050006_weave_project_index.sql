-- Proposed migration for the website-owned schema. Apply via backend's migration path.
-- Configure a dedicated NO SUPERUSER, NO BYPASSRLS login outside this migration and
-- grant it only weave_index_job membership. Do not use the Platform service role.
-- The Platform extension convention is pgvector installed into extensions.
create extension if not exists vector with schema extensions;

do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_extension e join pg_catalog.pg_namespace n on n.oid=e.extnamespace
    where e.extname='vector' and n.nspname='extensions'
  ) then
    raise exception 'pgvector must be installed in the extensions schema';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'weave_index_job') then
    create role weave_index_job nologin nosuperuser nobypassrls nocreatedb nocreaterole noreplication;
  end if;
end;
$$;

create table private.weave_project_index_checkpoint (
  singleton boolean primary key default true check (singleton),
  revision bigint not null default 0,
  manifest_generation integer not null default 0,
  manifest_hash text not null default '',
  next_offset integer not null default 0 check (next_offset >= 0),
  project_count integer not null default 0 check (project_count >= 0),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  retry_after timestamptz
);

create table private.weave_project_index_source (
  project_uri text primary key,
  status text not null check (status in ('indexed', 'missing', 'restricted', 'failed')),
  permission_until timestamptz not null,
  cid text,
  content_hash text,
  extraction_version text,
  checked_at timestamptz not null,
  fetched_at timestamptz,
  source_indexed_at timestamptz,
  embedding_model text,
  error_code text
);

create table private.weave_project_index_evidence (
  id text primary key,
  project_uri text not null references private.weave_project_index_source(project_uri) on delete cascade,
  evidence jsonb not null,
  lexical_text text not null,
  embedding extensions.vector(256),
  embedding_model text,
  check ((embedding is null) = (embedding_model is null)),
  search_document tsvector generated always as (to_tsvector('simple', lexical_text)) stored
);

create index weave_project_index_evidence_search on private.weave_project_index_evidence using gin (search_document);
create index weave_project_index_evidence_source on private.weave_project_index_evidence (project_uri);

alter table private.weave_project_index_checkpoint enable row level security;
alter table private.weave_project_index_source enable row level security;
alter table private.weave_project_index_evidence enable row level security;
revoke all on private.weave_project_index_checkpoint, private.weave_project_index_source,
  private.weave_project_index_evidence from public, anon, authenticated, service_role;
grant usage on schema private, extensions to weave_index_job;
grant select, insert, update on private.weave_project_index_checkpoint to weave_index_job;
grant select, insert, update, delete on private.weave_project_index_source,
  private.weave_project_index_evidence to weave_index_job;

create policy weave_project_index_job on private.weave_project_index_checkpoint to weave_index_job using (true) with check (true);
create policy weave_project_index_job on private.weave_project_index_source to weave_index_job using (true) with check (true);
create policy weave_project_index_job on private.weave_project_index_evidence to weave_index_job using (true) with check (true);

-- Match the JavaScript passage normalization for common combining marks.
create function private.weave_public_project_lexical_query(p_text text)
returns tsquery
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.string_agg(pg_catalog.quote_literal(token), ' | ')::pg_catalog.tsquery
  from pg_catalog.unnest(pg_catalog.tsvector_to_array(pg_catalog.to_tsvector(
    'simple', pg_catalog.regexp_replace(
      pg_catalog.normalize(pg_catalog.left(p_text, 2400), 'NFKD'),
      U&'[\0300-\036F\1AB0-\1AFF\1DC0-\1DFF\20D0-\20FF\FE20-\FE2F]', '', 'g'
    )
  ))) as q(token);
$$;
revoke all on function private.weave_public_project_lexical_query(text) from public, anon, authenticated, service_role;

-- Backend calls these from its narrow authenticated matching RPC after its own
-- current-revision/audience/open/expiry check. No grants to API caller roles.
create function private.weave_public_project_shortlist(p_text text, p_limit integer default 80)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with terms as (
    select private.weave_public_project_lexical_query(p_text) as query
  ), ranked as (
    select e.id, e.project_uri, e.evidence, s.fetched_at,
      pg_catalog.ts_rank_cd(e.search_document, t.query) as rank
    from terms t
    join private.weave_project_index_evidence e on e.search_document @@ t.query
    join private.weave_project_index_source s using (project_uri)
    where s.status in ('indexed', 'failed')
      and s.permission_until > now()
      and s.fetched_at >= now() - interval '7 days'
  ), per_project as (
    select * from (
      select *, row_number() over (partition by project_uri order by rank desc, id) as passage_number
      from ranked
    ) p where passage_number <= 2
  ), limited as (
    select id, rank, passage_number, evidence || pg_catalog.jsonb_build_object('fetchedAt', fetched_at) as evidence
    from per_project order by passage_number, rank desc, id limit greatest(0, least(coalesce(p_limit, 80), 80))
  )
  select coalesce(pg_catalog.jsonb_agg(evidence order by passage_number, rank desc, id), '[]'::jsonb) from limited;
$$;

create function private.weave_public_project_coverage()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'status', case
      when c.completed_at is null then 'partial'
      when c.completed_at < now() - interval '24 hours' then 'stale'
      when c.next_offset <> 0 or s.unverified > 0 then 'partial'
      else 'bounded'
    end,
    'corpusVersion', 'certified-pilot:' || coalesce(nullif(c.manifest_hash, ''), 'unconfigured') || ':' || coalesce(c.revision, 0),
    'modelVersion', null,
    'updatedAt', c.completed_at,
    'projectCount', s.indexed
  )
  from (select count(*) filter (where status = 'indexed' and permission_until > now()
                                 and fetched_at >= now() - interval '7 days') as indexed,
               count(*) filter (where error_code in ('source_unavailable', 'source_access_denied', 'source_rate_limited', 'invalid_source_record') and permission_until > now()) as unverified
        from private.weave_project_index_source) s
  left join private.weave_project_index_checkpoint c on c.singleton;
$$;
revoke all on function private.weave_public_project_shortlist(text, integer),
  private.weave_public_project_coverage() from public, anon, authenticated, service_role;

-- Internal only. Authenticated route uses lexical search until pilot evaluation
-- authorizes this method. Lexical and vector lists each represent distinct projects
-- before the cap. Compare only the exact model, pooling and text projection.
create function private.weave_public_project_hybrid_shortlist(
  p_text text, p_limit integer, p_query_vector extensions.vector, p_model_version text
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  cap integer := greatest(0, least(coalesce(p_limit, 80), 80));
  result jsonb;
begin
  if p_model_version is distinct from 'mxbai-xsmall:b0561d9a97e6b298da39f0ef3e7d3cf153b1b29a:q8:mean:unit:passage-v1'
    or p_query_vector is null or extensions.vector_dims(p_query_vector) <> 256
    or abs(extensions.vector_norm(p_query_vector) - 1) > 0.001
    or not exists (
      select 1 from private.weave_project_index_evidence e
      join private.weave_project_index_source s using (project_uri)
      where e.embedding_model = p_model_version and s.embedding_model = p_model_version
        and s.status in ('indexed', 'failed') and s.permission_until > now()
        and s.fetched_at >= now() - interval '7 days'
    ) then
    return private.weave_public_project_shortlist(p_text, cap);
  end if;

  with terms as (
    select private.weave_public_project_lexical_query(p_text) as query
  ), lexical_best as (
    select distinct on (e.project_uri) e.id, e.project_uri,
      pg_catalog.ts_rank_cd(e.search_document, t.query) as rank
    from terms t
    join private.weave_project_index_evidence e on e.search_document @@ t.query
    join private.weave_project_index_source s using (project_uri)
    where s.status in ('indexed', 'failed') and s.permission_until > now()
      and s.fetched_at >= now() - interval '7 days'
    order by e.project_uri, rank desc, e.id
  ), lexical as (
    select id, project_uri, row_number() over (order by rank desc, id) as rank_position
    from lexical_best order by rank desc, id limit 80
  ), semantic_best as (
    select distinct on (e.project_uri) e.id, e.project_uri,
      e.embedding operator(extensions.<=>) p_query_vector as distance
    from private.weave_project_index_evidence e
    join private.weave_project_index_source s using (project_uri)
    where e.embedding_model = p_model_version and s.embedding_model = p_model_version
      and s.status in ('indexed', 'failed') and s.permission_until > now()
      and s.fetched_at >= now() - interval '7 days'
    order by e.project_uri, distance, e.id
  ), semantic as (
    select id, project_uri, row_number() over (order by distance, id) as rank_position
    from semantic_best order by distance, id limit 80
  ), fused as (
    select coalesce(l.project_uri, v.project_uri) as project_uri, l.id as lexical_id, v.id as semantic_id,
      coalesce(1.0 / (60 + l.rank_position), 0) + coalesce(1.0 / (60 + v.rank_position), 0) as rank
    from lexical l full join semantic v using (project_uri)
  ), shortlist as (
    select f.rank, choice.id, choice.preference
    from fused f
    cross join lateral (
      select f.lexical_id as id, 0 as preference where f.lexical_id is not null
      union all select f.semantic_id, case when f.lexical_id is null then 0 else 1 end where f.semantic_id is distinct from f.lexical_id and f.semantic_id is not null
    ) choice
    order by choice.preference, f.rank desc, f.project_uri limit cap
  )
  select coalesce(pg_catalog.jsonb_agg(
    e.evidence || pg_catalog.jsonb_build_object('fetchedAt', s.fetched_at)
    order by f.preference, f.rank desc, e.project_uri
  ), '[]'::jsonb) into result
  from shortlist f join private.weave_project_index_evidence e using (id)
  join private.weave_project_index_source s using (project_uri);
  return result;
end;
$$;

create function private.weave_public_project_status(p_project_uri text)
returns text
language sql
stable
set search_path = ''
as $$
  select coalesce((
    select case
      when s.permission_until <= now() or s.status in ('missing', 'restricted') then 'unavailable'
      when s.status = 'indexed' and s.fetched_at >= now() - interval '24 hours'
        and exists (select 1 from private.weave_project_index_evidence e where e.project_uri = s.project_uri)
        then 'current'
      when s.status = 'indexed' and not exists (
        select 1 from private.weave_project_index_evidence e where e.project_uri = s.project_uri
      ) then 'unavailable'
      else 'unknown' end
    from private.weave_project_index_source s where s.project_uri = p_project_uri
  ), 'unknown');
$$;

revoke all on function private.weave_public_project_hybrid_shortlist(text, integer, extensions.vector, text),
  private.weave_public_project_status(text) from public, anon, authenticated, service_role;
