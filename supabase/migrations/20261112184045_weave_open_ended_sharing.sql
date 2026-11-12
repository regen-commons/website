-- Candidate only. Apply after weave-team-content and weave-matching-vectors.
-- Existing finite shares retain their expiry. A new review without an explicit
-- expiry remains active until closed, edited or withdrawn. Retrieval stays off.
-- Replacements retain each existing function's grants and restricted role access.
do $$
begin
  if to_regprocedure('private.weave_matching_vector_pending(text,integer)') is null
    or to_regprocedure('private.weave_matching_vector_store(uuid,text,uuid,bigint,bigint,text,extensions.vector)') is null
    or to_regprocedure('private.weave_matching_indexed_public_evidence(uuid,text,uuid,bigint,bigint)') is null
    or to_regprocedure('weave_workspace.content_command(uuid,uuid,text,uuid,text,text,text,jsonb)') is null then
    raise exception 'team content and matching vectors must be installed first';
  end if;
end $$;

alter table private.weave_matching_reviews alter column expires_at drop not null;

create or replace view private.weave_matching_current as
  select e.*, i.owner_id, i.matching_summary_revision, private.weave_matching_summary(i.card) as summary,
    private.weave_matching_terms(e.value) as terms
  from private.weave_matching_entries e join weave.initiatives i on i.id=e.initiative_id
  join weave_workspace.project_links l on l.id=i.id
  where not l.matching_paused and e.matching_audience='weave_users' and not e.matching_withdrawn
    and e.matching_reviewed_revision=e.matching_revision
    and e.matching_reviewed_summary_revision=i.matching_summary_revision
    and e.value->>'status'='open' and jsonb_array_length(e.value->'capitalForms')>0
    and (e.matching_expires_at is null or e.matching_expires_at>now());

create or replace function private.weave_matching_preview(p_id uuid,p_revision integer,p_entries jsonb,p_expires_at timestamptz)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare parent weave.initiatives=private.weave_matching_owner(p_id,true);
  expiration timestamptz=p_expires_at;
  selected jsonb; review_id uuid;
begin
  if p_revision is null or p_revision<1 or (p_expires_at is not null and not isfinite(p_expires_at)) or expiration<=now()
    then raise sqlstate 'PT400' using message='invalid_data'; end if;
  if parent.revision<>p_revision then raise sqlstate 'PT409' using message='matching_conflict'; end if;
  select jsonb_agg(jsonb_build_object('kind',e.kind,'entryId',e.id,'revision',e.matching_revision,
    'shareVersion',e.matching_share_version,'value',e.value) order by e.kind,e.position)
    into selected from private.weave_matching_selected(p_id,p_entries) e where e.value->>'status'='open' and jsonb_array_length(e.value->'capitalForms')>0;
  if coalesce(jsonb_array_length(selected),0)<>jsonb_array_length(p_entries) then
    raise sqlstate 'PT409' using message='matching_conflict';
  end if;
  delete from private.weave_matching_reviews where initiative_id=p_id and valid_until<=now();
  if (select count(*) from private.weave_matching_reviews where initiative_id=p_id)>=30
    then raise sqlstate 'PT429' using message='rate_limited'; end if;
  insert into private.weave_matching_reviews(initiative_id,initiative_revision,entries,expires_at,valid_until)
    values(p_id,p_revision,p_entries,expiration,least(expiration,now()+interval '15 minutes')) returning id into review_id;
  return jsonb_build_object('reviewId',review_id,'initiativeId',p_id,'initiativeRevision',p_revision,
    'audience','weave_users','expiresAt',expiration,'summary',private.weave_matching_summary(parent.card),'entries',selected);
end $$;

create or replace function private.weave_matching_vector_pending(p_model_version text,p_limit integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if p_model_version is distinct from private.weave_matching_embedding_model()
    or p_limit is null or p_limit not between 1 and 25 then
    raise sqlstate 'PT400' using message='invalid_embedding_request';
  end if;
  return coalesce((select jsonb_agg(q.result order by q.confirmed_at,q.initiative_id,q.kind,q.id)
    from (select e.matching_confirmed_at as confirmed_at,e.initiative_id,e.kind,e.id,
      jsonb_build_object('initiativeId',e.initiative_id,'kind',e.kind,'entryId',e.id,
        'revision',e.matching_revision,'shareVersion',e.matching_share_version,
        'text',projected.text) as result
      from private.weave_matching_current e
      cross join lateral (select private.weave_matching_embedding_text(e.value) as text) projected
      where (e.matching_expires_at is null or e.matching_expires_at>statement_timestamp())
        and private.weave_matching_embedding_text_supported(projected.text)
        and not exists(select from private.weave_matching_query_vectors v where
          (v.initiative_id,v.kind,v.entry_id,v.revision,v.share_version,v.model_version)=
          (e.initiative_id,e.kind,e.id,e.matching_revision,e.matching_share_version,p_model_version))
      order by e.matching_confirmed_at,e.initiative_id,e.kind,e.id limit p_limit) q),'[]'::jsonb);
end $$;

create or replace function private.weave_matching_vector_store(
  p_id uuid,p_kind text,p_entry_id uuid,p_revision bigint,p_share_version bigint,
  p_model_version text,p_embedding extensions.vector
) returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_id is null or p_kind is null or p_kind not in ('need','offer') or p_entry_id is null
    or p_revision is null or p_revision not between 1 and 9007199254740991
    or p_share_version is null or p_share_version not between 1 and 9007199254740991
    or p_model_version is distinct from private.weave_matching_embedding_model()
    or p_embedding is null or extensions.vector_dims(p_embedding)<>256
    or abs(extensions.vector_norm(p_embedding)-1)>0.001 then
    raise sqlstate 'PT400' using message='invalid_embedding_request';
  end if;
  -- Save, share and withdraw use this same lock. Check again after waiting.
  perform from weave.initiatives where id=p_id for update;
  if not found or not exists(select from private.weave_matching_current e
    where (e.initiative_id,e.kind,e.id,e.matching_revision,e.matching_share_version)=
      (p_id,p_kind,p_entry_id,p_revision,p_share_version)
      and (e.matching_expires_at is null or e.matching_expires_at>clock_timestamp())
      and private.weave_matching_embedding_text_supported(private.weave_matching_embedding_text(e.value)))
    then return false; end if;
  insert into private.weave_matching_query_vectors(initiative_id,kind,entry_id,revision,share_version,model_version,embedding)
    values(p_id,p_kind,p_entry_id,p_revision,p_share_version,p_model_version,p_embedding)
    on conflict do nothing;
  return true;
end $$;

create or replace function private.weave_matching_indexed_public_evidence(
  p_id uuid,p_kind text,p_entry_id uuid,p_revision bigint,p_share_version bigint
) returns jsonb language plpgsql stable set search_path = '' as $$
declare query_text text; vector extensions.vector; model text=private.weave_matching_embedding_model();
  hybrid_enabled boolean;
begin
  select s.hybrid_enabled into hybrid_enabled from private.weave_matching_retrieval_settings s where s.singleton;
  select private.weave_matching_embedding_text(e.value),v.embedding into query_text,vector
  from private.weave_matching_current e
  left join private.weave_matching_query_vectors v on hybrid_enabled
    and (v.initiative_id,v.kind,v.entry_id,v.revision,v.share_version,v.model_version)=
      (e.initiative_id,e.kind,e.id,e.matching_revision,e.matching_share_version,model)
  where (e.initiative_id,e.kind,e.id,e.matching_revision,e.matching_share_version)=
    (p_id,p_kind,p_entry_id,p_revision,p_share_version)
    and (e.matching_expires_at is null or e.matching_expires_at>statement_timestamp());
  if not found then return jsonb_build_object('evidence','[]'::jsonb,'modelVersion',null); end if;
  if vector is not null and exists(
    select from private.weave_project_index_evidence e
    join private.weave_project_index_source s using(project_uri)
    where e.embedding_model=model and s.embedding_model=model and s.status in ('indexed','failed')
      and s.permission_until>now() and s.fetched_at>=now()-interval '7 days'
  ) then
    begin
      return jsonb_build_object('evidence',private.weave_public_project_hybrid_shortlist(query_text,80,vector,model),
        'modelVersion',model);
    exception when others then
      -- A vector retrieval failure must not hide usable lexical evidence.
      null;
    end;
  end if;
  return jsonb_build_object('evidence',private.weave_public_project_shortlist(query_text,80),'modelVersion',null);
end $$;
