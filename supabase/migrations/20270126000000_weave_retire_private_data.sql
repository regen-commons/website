-- Candidate for the website migration owner, after weave-matching-end-shares. Not applied anywhere.
-- Do not apply before 26 January 2027, and only with the user's yes (D49). Apply it only after the Weave build that
-- no longer lists, opens or deletes earlier private saves is deployed, since that build stops calling the
-- functions this drops.
--
-- DL-155, step 7: the personal private saves and the retired matching data go. D49 kept the saves readable and
-- downloadable for at least 60 days after new saves stopped on 27 November 2026, then asks the user again.
-- - Every personal saved card (weave.initiatives with no team_workspace_id) is deleted, with its needs and offers.
--   Its project link and that link's published listings stay: the link's card reference is cleared (on delete
--   set null) and the listings hang off the link. Deleting a card's entries would otherwise queue a withdrawal of
--   each listing published from it (support_entry_changed), so that trigger is held off for this delete alone.
-- - The share tables (saved partners, share requests, query vectors and the retrieval setting) and every function
--   that only sharing, the embedding job or a personal save used are dropped, as are the read, list and delete
--   functions for personal saves.
-- - weave_workspace.content_command loses its retired matching actions.
-- Kept for group projects' shared team drafts (D48): their cards, needs and offers with every matching_* column,
-- private.weave_matching_entries, weave_matching_state and weave_matching_owner (the entry revisions team
-- publishing reads), weave_save_document, weave_reconcile_matching_entries and weave_matching_summary (team save),
-- weave.load_initiative (team load), and private.weave_matching_reviews, which is empty but still cleared by
-- content_command's pause and support_command. weave_workspace.project_links.matching_paused stays: the public
-- listings read uses it. weave.accounts and the deletion tombstones stay; they hold no saved content.
do $$
begin
  if to_regprocedure('private.weave_matching_shortlist(uuid,jsonb)') is null
    or to_regprocedure('weave.save_initiative(uuid,integer,uuid,jsonb)') is null
    or to_regprocedure('private.weave_listing_shortlist(uuid)') is null
    or to_regclass('weave_workspace.support_listings') is null then
    raise exception 'weave-matching-end-shares and weave-retire-private-saves must be installed first';
  end if;
  if exists(select from weave.needs where matching_audience is not null and not matching_withdrawn)
    or exists(select from weave.offers where matching_audience is not null and not matching_withdrawn) then
    raise exception 'a share is still on: weave-matching-end-shares must have withdrawn every share';
  end if;
  -- A project being set up from a personal card is the one case the delete guard refuses that a migration
  -- cannot finish for the person. None existed on 28 November 2026; if one does now, stop and look.
  if exists(select from weave_workspace.create_intents c join weave.initiatives i on i.id = c.initiative_id
      where i.team_workspace_id is null and c.status not in ('linked', 'group_rejected')) then
    raise exception 'a project is still being set up from a personal saved card';
  end if;
end $$;

-- What must not change: every published listing, every project link but its card reference, and every team card
-- with its entries. The view is compared before and after the delete, in both directions.
create temporary view weave_retire_kept as
  select 'listing' what, md5(s::text) fingerprint from weave_workspace.support_listings s
  union all select 'link', md5((l.id, l.project_uri, l.repository_did, l.group_did, l.cid, l.verified_at, l.linked_by,
    l.matching_paused)::text) from weave_workspace.project_links l
  union all select 'team card', md5(i::text) from weave.initiatives i where i.team_workspace_id is not null
  union all select 'team need', md5(n::text) from weave.needs n join weave.initiatives i on i.id = n.initiative_id
    where i.team_workspace_id is not null
  union all select 'team offer', md5(o::text) from weave.offers o join weave.initiatives i on i.id = o.initiative_id
    where i.team_workspace_id is not null;
create temporary table weave_retire_before on commit drop as select * from weave_retire_kept;

-- Save, team save and deletion take a card's row lock; taking it first makes any of them that starts now wait.
do $$ begin perform from weave.initiatives where team_workspace_id is null for update; end $$;
alter table weave.needs disable trigger support_entry_changed;
alter table weave.offers disable trigger support_entry_changed;
-- The cascade takes the cards' needs, offers, saved partners, query vectors, share reviews, save receipts and
-- finished setup intents with them.
delete from weave.initiatives where team_workspace_id is null;
alter table weave.needs enable trigger support_entry_changed;
alter table weave.offers enable trigger support_entry_changed;

do $$
begin
  if exists(select from weave.initiatives where team_workspace_id is null)
    or exists(select from weave.needs n where not exists(select from weave.initiatives i where i.id = n.initiative_id))
    or exists(select from weave.offers o where not exists(select from weave.initiatives i where i.id = o.initiative_id))
    or exists(select from weave_workspace.project_links l where l.solo_initiative_id is not null) then
    raise exception 'a personal saved card or its reference remains';
  end if;
  if exists((select * from weave_retire_before except all select * from weave_retire_kept)
      union all (select * from weave_retire_kept except all select * from weave_retire_before)) then
    raise exception 'a published listing, a project link or a team draft changed';
  end if;
end $$;
drop view weave_retire_kept;

-- weave-matching-published-listings's command without the actions sharing for matching used. Viewers keep every
-- read; only team_save needs edit access now.
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
  if p_action='team_save' and access->>'accessRole' not in ('editor','admin') then
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

  -- Only this restricted command can enter the team and matching functions.
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

-- The public functions for personal saves and sharing. No cascade: anything still depending on one fails the apply.
drop function weave.save_initiative(uuid,integer,uuid,jsonb);
drop function weave.list_initiatives(integer);
drop function weave.delete_initiative(uuid,integer,uuid);
drop function weave.matching_preview(uuid,integer,jsonb,timestamp with time zone);
drop function weave.matching_change(uuid,text,uuid,uuid,jsonb);
drop function weave.matching_shortlist(uuid,jsonb);
drop function weave.matching_leads(uuid);
drop function weave.matching_set_lead(uuid,jsonb,text,text,uuid);

-- Sharing's tables go first: the query vectors' check calls the embedding model function. Their prune triggers go
-- with them.
drop trigger prune_matching_query_vectors on weave.initiatives;
drop trigger prune_matching_query_vectors on weave.needs;
drop trigger prune_matching_query_vectors on weave.offers;
drop function private.weave_matching_prune_query_vectors();
drop table private.weave_matching_leads;
drop table private.weave_matching_requests;
drop table private.weave_matching_query_vectors;
drop table private.weave_matching_retrieval_settings;

-- The private bodies of personal saves and sharing, the share search and the embedding job.
drop function private.weave_save_initiative(uuid,integer,uuid,jsonb);
drop function private.weave_delete_initiative(uuid,integer,uuid);
drop function private.weave_matching_preview(uuid,integer,jsonb,timestamp with time zone);
drop function private.weave_matching_change(uuid,text,uuid,uuid,jsonb);
drop function private.weave_matching_selected(uuid,jsonb);
drop function private.weave_matching_refs(jsonb,boolean);
drop function private.weave_matching_retry(uuid,uuid,jsonb);
drop function private.weave_matching_shortlist(uuid,jsonb);
drop function private.weave_matching_leads(uuid);
drop function private.weave_matching_set_lead(uuid,jsonb,text,text,uuid);
drop function private.weave_matching_public_status(text);
drop function private.weave_matching_weave_candidate(text);
drop function private.weave_matching_indexed_public_evidence(uuid,text,uuid,bigint,bigint);
drop function private.weave_matching_vector_pending(text,integer);
drop function private.weave_matching_vector_store(uuid,text,uuid,bigint,bigint,text,extensions.vector);
drop function private.weave_matching_embedding_text_supported(text);
drop function private.weave_matching_embedding_text(jsonb);
drop function private.weave_matching_embedding_model();
drop function private.weave_matching_projection(private.weave_matching_current);
drop view private.weave_matching_current;
-- The share search's word indexes on needs and offers; listing search has its own words.
drop index weave.needs_weave_matching_terms_idx;
drop index weave.offers_weave_matching_terms_idx;
drop function private.weave_matching_terms(jsonb);
