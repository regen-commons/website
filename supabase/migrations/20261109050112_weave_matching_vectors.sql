-- Candidate for the website migration owner. Apply after weave-matching.sql
-- and weave-project-index.sql. Provision a separate worker login outside SQL.
do $$
begin
  if not exists(select from pg_catalog.pg_roles where rolname='weave_query_embedding_job') then
    create role weave_query_embedding_job nologin nosuperuser nobypassrls nocreatedb nocreaterole noreplication;
  elsif exists(select from pg_catalog.pg_roles where rolname='weave_query_embedding_job'
    and (rolcanlogin or rolsuper or rolbypassrls or rolcreatedb or rolcreaterole or rolreplication)) then
    raise exception 'unsafe weave_query_embedding_job role';
  end if;
end $$;

create function private.weave_matching_embedding_model() returns text
language sql immutable set search_path = '' as $$
  select 'mxbai-xsmall:b0561d9a97e6b298da39f0ef3e7d3cf153b1b29a:q8:mean:unit:passage-v1'::text
$$;

-- Keep the reviewed fields and JavaScript trim/join projection in agreement.
create function private.weave_matching_embedding_text(value jsonb) returns text
language sql immutable set search_path = '' as $$
  select coalesce(string_agg(trimmed,'. ' order by position),'')
  from (select position,btrim(value->>field,
    U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF') as trimmed
    from unnest(array['title','description','purpose']) with ordinality as f(field,position)) parts
  where trimmed<>''
$$;

create function private.weave_matching_embedding_text_supported(value text) returns boolean
language sql immutable strict set search_path = '' as $$
  -- The worker bounds text in JavaScript UTF-16 units. Supplementary
  -- characters count as two units there, and as one character in Postgres.
  select length(value)+regexp_count(value,U&'[\+010000-\+10FFFF]') between 1 and 1200
$$;

create table private.weave_matching_query_vectors (
  initiative_id uuid not null references weave.initiatives(id) on delete cascade,
  kind text not null check(kind in ('need','offer')),
  entry_id uuid not null,
  revision bigint not null check(revision>0),
  share_version bigint not null check(share_version>0),
  model_version text not null check(model_version=private.weave_matching_embedding_model()),
  embedding extensions.vector(256) not null check(abs(extensions.vector_norm(embedding)-1)<=0.001),
  primary key(initiative_id,kind,entry_id,revision,share_version,model_version)
);
alter table private.weave_matching_query_vectors enable row level security;

-- The migration has no path for a browser or worker to enable hybrid retrieval.
create table private.weave_matching_retrieval_settings (
  singleton boolean primary key default true check(singleton),
  hybrid_enabled boolean not null default false
);
insert into private.weave_matching_retrieval_settings default values;
alter table private.weave_matching_retrieval_settings enable row level security;
revoke all on private.weave_matching_query_vectors, private.weave_matching_retrieval_settings
  from public,anon,authenticated,service_role,weave_index_job,weave_query_embedding_job;

create function private.weave_matching_vector_pending(p_model_version text,p_limit integer)
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
      where e.matching_expires_at>statement_timestamp()
        and private.weave_matching_embedding_text_supported(projected.text)
        and not exists(select from private.weave_matching_query_vectors v where
          (v.initiative_id,v.kind,v.entry_id,v.revision,v.share_version,v.model_version)=
          (e.initiative_id,e.kind,e.id,e.matching_revision,e.matching_share_version,p_model_version))
      order by e.matching_confirmed_at,e.initiative_id,e.kind,e.id limit p_limit) q),'[]'::jsonb);
end $$;

create function private.weave_matching_vector_store(
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
      and e.matching_expires_at>clock_timestamp()
      and private.weave_matching_embedding_text_supported(private.weave_matching_embedding_text(e.value)))
    then return false; end if;
  insert into private.weave_matching_query_vectors(initiative_id,kind,entry_id,revision,share_version,model_version,embedding)
    values(p_id,p_kind,p_entry_id,p_revision,p_share_version,p_model_version,p_embedding)
    on conflict do nothing;
  return true;
end $$;

create function private.weave_matching_prune_query_vectors() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_table_name='initiatives' then
    if old.matching_summary_revision is distinct from new.matching_summary_revision then
      delete from private.weave_matching_query_vectors where initiative_id=old.id;
    end if;
  elsif tg_op='DELETE' or (old.matching_revision,old.matching_share_version) is distinct from
    (new.matching_revision,new.matching_share_version) then
    delete from private.weave_matching_query_vectors
      where initiative_id=old.initiative_id and kind=tg_argv[0] and entry_id=old.id;
  end if;
  return null;
end $$;
create trigger prune_matching_query_vectors after update of matching_summary_revision on weave.initiatives
  for each row execute function private.weave_matching_prune_query_vectors();
create trigger prune_matching_query_vectors after update of matching_revision,matching_share_version or delete on weave.needs
  for each row execute function private.weave_matching_prune_query_vectors('need');
create trigger prune_matching_query_vectors after update of matching_revision,matching_share_version or delete on weave.offers
  for each row execute function private.weave_matching_prune_query_vectors('offer');

-- Called only inside the existing owner-checked shortlist. Never return the
-- embedding. Recheck the same eligible projection even if a vector exists.
create function private.weave_matching_indexed_public_evidence(
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
    and e.matching_expires_at>statement_timestamp();
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

revoke all on function private.weave_matching_embedding_model(),private.weave_matching_embedding_text(jsonb),
  private.weave_matching_embedding_text_supported(text),
  private.weave_matching_prune_query_vectors(),private.weave_matching_indexed_public_evidence(uuid,text,uuid,bigint,bigint),
  private.weave_matching_vector_pending(text,integer),
  private.weave_matching_vector_store(uuid,text,uuid,bigint,bigint,text,extensions.vector)
  from public,anon,authenticated,service_role,weave_index_job,weave_query_embedding_job;
grant usage on schema private,extensions to weave_query_embedding_job;
grant execute on function private.weave_matching_vector_pending(text,integer),
  private.weave_matching_vector_store(uuid,text,uuid,bigint,bigint,text,extensions.vector)
  to weave_query_embedding_job;
