-- Local candidate after the public project index. The workspace content command
-- calls this helper only after checking the session, grant and linked project.
create function private.weave_public_project_snapshot(p_own_uri text)
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
  )
  select jsonb_build_object(
    'corpusVersion', coverage->'corpusVersion', 'status', coverage->'status',
    'indexedAt', coverage->'updatedAt', 'availableUntil', snapshot.available_until,
    'truncated', (select count(*) > 80 from eligible), 'evidence', snapshot.evidence
  )
  from snapshot cross join lateral (select private.weave_public_project_coverage() as coverage) c;
$$;

revoke all on function private.weave_public_project_snapshot(text)
  from public, anon, authenticated, service_role, weave_workspace_runtime;
