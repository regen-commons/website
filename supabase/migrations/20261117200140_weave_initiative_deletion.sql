-- Candidate for the website migration owner. Apply after every existing Weave
-- candidate, last after weave-open-ended-sharing. No hosted migration is implied.
-- An owner deletes one personal saved initiative at the exact revision it saw.
-- A card that anything else refers to is refused before any row is removed, so no
-- cascade can take a project link, a create intent, a matching record, a query
-- vector or a publication with it. Team documents are never deleted here.
do $$
begin
  if to_regprocedure('private.weave_save_document(uuid,integer,uuid,jsonb,boolean)') is null
    or to_regclass('weave_workspace.create_intents') is null
    or to_regclass('weave_workspace.support_requests') is null
    or to_regclass('private.weave_matching_query_vectors') is null
    or to_regclass('private.weave_matching_requests') is null then
    raise exception 'team content, matching vectors and support publication must be installed first';
  end if;
end $$;

-- A deleted initiative's ID stays reserved, so no client can bring the card back.
-- Account deletion still removes everything the account owns.
create table private.weave_deleted_initiatives (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  deleted_revision integer not null check (deleted_revision > 0),
  request_id uuid not null,
  response jsonb not null,
  deleted_at timestamptz not null default now(),
  unique (owner_id, request_id)
);
alter table private.weave_deleted_initiatives enable row level security;
revoke all on private.weave_deleted_initiatives from public, anon, authenticated, service_role;

-- A stale first save (expected revision 0) or a retried create for a removed ID
-- fails with initiative_deleted, so the client can save its words as a new card.
-- The trigger runs after the insert, so under READ COMMITTED (PostgREST and the
-- API's transactions) a create that waited for a concurrent deletion to commit reads
-- that deletion's tombstone and rolls back. Under REPEATABLE READ the same create
-- fails with a serialization error (40001) instead.
create function private.weave_initiative_not_deleted() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select from private.weave_deleted_initiatives where id = new.id) then
    raise sqlstate 'PT409' using message = 'initiative_deleted';
  end if;
  return null;
end $$;
revoke all on function private.weave_initiative_not_deleted() from public, anon, authenticated, service_role;
create trigger weave_initiative_not_deleted after insert on weave.initiatives
  for each row execute function private.weave_initiative_not_deleted();

-- Foreign keys into weave.initiatives, all ON DELETE CASCADE, and how each is handled:
--   weave.needs, weave.offers                 the card's own entries: removed with it
--   private.weave_save_requests               this owner's receipts hold only this card: removed;
--                                             another actor's receipt: refused
--   private.weave_matching_reviews            a review still open: refused; expired ones: removed
--   private.weave_matching_leads              refused
--   private.weave_matching_query_vectors      refused
--   weave_workspace.project_links             refused (a solo link would cascade grants,
--                                             invites and support listings)
--   weave_workspace.create_intents            refused
-- Nothing references weave.needs or weave.offers. References without a foreign key:
-- support listings, reviews and requests keyed by the workspace ID, any entry still
-- shared for matching, and another actor's matching receipt (command->>0): refused.
-- The owner's own matching receipts only replay commands on this card: removed. Other people's leads
-- naming this card as a candidate stay theirs and read as unavailable, as after a
-- withdrawal.
create function private.weave_delete_initiative(p_id uuid, p_expected_revision integer, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid = private.weave_actor(); current weave.initiatives%rowtype;
  previous private.weave_deleted_initiatives%rowtype; kept integer; result jsonb;
begin
  if actor is null then raise sqlstate 'PT401' using message = 'sign_in_required'; end if;
  if p_id is null or p_request_id is null or p_expected_revision is null
    or p_expected_revision < 1 or p_expected_revision >= 2147483647 then
    raise sqlstate 'PT400' using message = 'invalid_data';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('weave-delete:' || actor::text || ':' || p_request_id::text, 0));
  if exists (select from private.weave_deleted_initiatives
    where owner_id = actor and request_id = p_request_id and id <> p_id) then
    raise sqlstate 'PT409' using message = 'request_reused';
  end if;
  -- The same row lock as Save orders a save and a deletion of one card.
  select * into current from weave.initiatives
    where id = p_id and owner_id = actor and team_workspace_id is null for update;
  if not found then
    -- Read after any lock wait, so a retry racing its first attempt sees the result.
    select * into previous from private.weave_deleted_initiatives where id = p_id;
    if found and previous.owner_id = actor and previous.request_id = p_request_id
      and previous.deleted_revision = p_expected_revision then
      return previous.response;
    end if;
    -- Another owner's card, a team document, a removed card and no card look the same.
    raise sqlstate 'PT404' using message = 'not_found';
  end if;
  if private.weave_actor() is distinct from actor then
    raise sqlstate 'PT401' using message = 'sign_in_required';
  end if;
  if current.revision <> p_expected_revision then
    raise sqlstate 'PT409' using message = 'revision_conflict';
  end if;
  if exists (select from weave_workspace.project_links where id = p_id or solo_initiative_id = p_id)
    or exists (select from weave_workspace.create_intents where initiative_id = p_id)
    or exists (select from weave_workspace.support_listings where workspace_id = p_id)
    or exists (select from weave_workspace.support_reviews where workspace_id = p_id)
    or exists (select from weave_workspace.support_requests where workspace_id = p_id)
    or exists (select from private.weave_matching_reviews where initiative_id = p_id and valid_until > now())
    or exists (select from private.weave_matching_leads where initiative_id = p_id)
    or exists (select from private.weave_matching_requests where command->>0 = p_id::text and actor_id <> actor)
    or exists (select from private.weave_matching_query_vectors where initiative_id = p_id)
    or exists (select from private.weave_save_requests where initiative_id = p_id and actor_id <> actor)
    or exists (select from private.weave_matching_entries
      where initiative_id = p_id and matching_audience is not null and not matching_withdrawn) then
    raise sqlstate 'PT409' using message = 'initiative_referenced';
  end if;
  delete from weave.needs where initiative_id = p_id;
  delete from weave.offers where initiative_id = p_id;
  delete from private.weave_save_requests where actor_id = actor and initiative_id = p_id;
  delete from private.weave_matching_requests where actor_id = actor and command->>0 = p_id::text;
  delete from private.weave_matching_reviews where initiative_id = p_id;
  delete from weave.initiatives where id = p_id;
  select count(*) into kept from weave.initiatives where owner_id = actor and team_workspace_id is null;
  result = jsonb_build_object('id', p_id, 'deleted', true, 'revision', p_expected_revision,
    'removed', jsonb_build_array(p_id), 'kept', kept);
  insert into private.weave_deleted_initiatives(id, owner_id, deleted_revision, request_id, response)
    values (p_id, actor, p_expected_revision, p_request_id, result);
  return result;
end $$;
revoke all on function private.weave_delete_initiative(uuid, integer, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.weave_delete_initiative(uuid, integer, uuid) to authenticated;

create function weave.delete_initiative(p_id uuid, p_expected_revision integer, p_request_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.weave_delete_initiative(p_id, p_expected_revision, p_request_id)
$$;
revoke all on function weave.delete_initiative(uuid, integer, uuid) from public, anon, authenticated, service_role;
grant execute on function weave.delete_initiative(uuid, integer, uuid) to authenticated;
