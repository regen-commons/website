-- Candidate for the website migration owner, after weave-initiative-deletion. Not applied anywhere.
-- Apply through the website's migration path as a new migration.
--
-- Matching now serves project workspaces only, so a personal saved card can no longer withdraw its
-- sharing, clear its saved partners or let its query vectors be pruned first. These references no
-- longer hold a personal card (QA notes, 26 November 2026); each goes with it:
-- - A project setup that finished (linked) or that Weave marked group_rejected. A finished setup's
--   project lives in its own workspace, so its record is only a receipt. group_rejected follows a
--   refused registration, but also a timeout or server error, after which a group may exist on
--   Certified; nothing recovers from that record, but deleting it removes the only row tying such a
--   group to this card. A setup still under way (prepared, group_pending, group_confirmed,
--   project_pending, project_confirmed) is still refused, because it reads the card again to finish.
-- - The card's own needs and offers shared for matching. Removing them stops the sharing: other
--   people's partners naming an entry read as unavailable, as after a withdrawal.
-- - The owner's saved and dismissed partners for the card (private.weave_matching_leads), and the
--   query vectors derived from its entries (private.weave_matching_query_vectors).
-- Everything else is unchanged. Production's function matched weave-initiative-deletion exactly on
-- 26 November 2026. CREATE OR REPLACE keeps the function's owner and grants, so this file refuses to
-- run before that candidate has created them.
do $$
begin
  if to_regprocedure('private.weave_delete_initiative(uuid,integer,uuid)') is null
    or to_regclass('private.weave_deleted_initiatives') is null then
    raise exception 'weave-initiative-deletion must be installed first';
  end if;
end $$;

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
    -- Starting a setup, claiming its group step and finishing it lock the card, so they wait for this deletion.
    -- The other steps only move a setup between statuses refused here or into group_rejected,
    -- and neither linked nor group_rejected changes again.
    or exists (select from weave_workspace.create_intents
      where initiative_id = p_id and status not in ('linked', 'group_rejected'))
    or exists (select from weave_workspace.support_listings where workspace_id = p_id)
    or exists (select from weave_workspace.support_reviews where workspace_id = p_id)
    or exists (select from weave_workspace.support_requests where workspace_id = p_id)
    or exists (select from private.weave_matching_reviews where initiative_id = p_id and valid_until > now())
    or exists (select from private.weave_matching_requests where command->>0 = p_id::text and actor_id <> actor)
    or exists (select from private.weave_save_requests where initiative_id = p_id and actor_id <> actor) then
    raise sqlstate 'PT409' using message = 'initiative_referenced';
  end if;
  delete from weave_workspace.create_intents
    where initiative_id = p_id and status in ('linked', 'group_rejected');
  delete from private.weave_matching_leads where initiative_id = p_id;
  delete from private.weave_matching_query_vectors where initiative_id = p_id;
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
