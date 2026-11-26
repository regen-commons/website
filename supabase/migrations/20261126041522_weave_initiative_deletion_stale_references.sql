-- Candidate for the website migration owner, after weave-initiative-deletion. Not applied anywhere.
-- Apply through the website's migration path as a new migration.
--
-- Two references no longer hold a personal saved card (QA notes, 26 November 2026):
-- - A project setup that finished (linked) or that Certified refused (group_rejected). A finished
--   setup's project lives in its own workspace, so the setup record is only a receipt; a refused one
--   created nothing. Both go with the card through their ON DELETE CASCADE. A setup still under way
--   (prepared, group_pending, group_confirmed, project_pending, project_confirmed) is still refused,
--   because it reads the card again before it finishes.
-- - The card's own needs and offers shared for matching. Matching now serves project workspaces
--   only, so a personal save cannot withdraw them first. Deleting the card removes them, which other
--   people see as after a withdrawal: their leads naming an entry read as unavailable.
-- Everything else is unchanged. Production's function matched weave-initiative-deletion exactly
-- on 26 November 2026. CREATE OR REPLACE keeps the function's owner and grants.
create or replace function private.weave_delete_initiative(p_id uuid, p_expected_revision integer, p_request_id uuid)
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
    -- The card's row lock above orders this read with a setup's next step, which locks the card too.
    or exists (select from weave_workspace.create_intents
      where initiative_id = p_id and status not in ('linked', 'group_rejected'))
    or exists (select from weave_workspace.support_listings where workspace_id = p_id)
    or exists (select from weave_workspace.support_reviews where workspace_id = p_id)
    or exists (select from weave_workspace.support_requests where workspace_id = p_id)
    or exists (select from private.weave_matching_reviews where initiative_id = p_id and valid_until > now())
    or exists (select from private.weave_matching_leads where initiative_id = p_id)
    or exists (select from private.weave_matching_requests where command->>0 = p_id::text and actor_id <> actor)
    or exists (select from private.weave_matching_query_vectors where initiative_id = p_id)
    or exists (select from private.weave_save_requests where initiative_id = p_id and actor_id <> actor) then
    raise sqlstate 'PT409' using message = 'initiative_referenced';
  end if;
  delete from weave_workspace.create_intents where initiative_id = p_id;
  -- Shared entries go too: removing them stops their sharing, as a withdrawal would.
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
