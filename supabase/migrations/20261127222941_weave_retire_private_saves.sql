-- Candidate for the website migration owner, after weave-publish-from-draft. Not applied anywhere.
-- Apply through the website's migration path as a new migration.
--
-- DL-155, step 4: nothing new is saved privately or shared for matching. Weave's API refuses both in
-- regen-commons/weave#280, with `private_saves_retired` and `matching_shares_retired`. This makes the
-- database refuse them too, with the same names, so neither a session's own access token through
-- PostgREST nor any build of the Weave server can save or share anew:
-- - private.weave_save_initiative, behind weave.save_initiative, refuses every personal save: a new
--   card, an update and a retry of an earlier request alike. A team workspace's save calls
--   private.weave_save_document with p_team from weave_workspace.content_command, and is unchanged
--   until step 6.
-- - private.weave_matching_preview refuses every review, for a personal card or a team's. A review
--   exists only to share.
-- - private.weave_matching_change refuses share and renew once the command is checked and is not a
--   replay, so a malformed one is still invalid data and one that committed before answers as it did.
--   Withdrawing is unchanged, as are matching state, partner search, saved partners and leads, until
--   step 5.
-- Loading, listing and deleting the private saves already here, which Weave's Download reads, are
-- unchanged (D49).
-- weave-team-content already took the matching wrappers away from authenticated, so only the
-- workspace runtime reaches the matching functions; weave.save_initiative stays executable by
-- authenticated and now answers with the refusal.
-- Production's three functions matched weave-team-content and weave-open-ended-sharing byte for byte
-- on 27 November 2026. CREATE OR REPLACE keeps each function's owner and grants, so this file refuses
-- to run before those candidates have created them.
do $$
begin
  if to_regprocedure('private.weave_save_initiative(uuid,integer,uuid,jsonb)') is null
    or to_regprocedure('private.weave_save_document(uuid,integer,uuid,jsonb,boolean)') is null
    or to_regprocedure('private.weave_matching_preview(uuid,integer,jsonb,timestamptz)') is null
    or to_regprocedure('private.weave_matching_change(uuid,text,uuid,uuid,jsonb)') is null
    or to_regprocedure('weave_workspace.initiative_link_guard()') is null then
    raise exception 'weave-team-content and weave-publish-from-draft must be installed first';
  end if;
end $$;

-- Nothing is saved privately any more. It reads nothing and writes nothing, so it runs as the caller.
create or replace function private.weave_save_initiative(p_id uuid,p_expected_revision integer,p_request_id uuid,p_document jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
begin
  raise sqlstate 'PT410' using message='private_saves_retired';
end $$;

-- A review exists only to share, so none is made. It reads nothing and writes nothing.
create or replace function private.weave_matching_preview(p_id uuid,p_revision integer,p_entries jsonb,p_expires_at timestamptz)
returns jsonb language plpgsql security invoker set search_path = '' as $$
begin
  raise sqlstate 'PT410' using message='matching_shares_retired';
end $$;

-- Withdrawing, as before. Sharing and renewing are refused once the command is known to be well formed
-- and is not a replay: a share or renewal that committed before answers as it did, as any replay does.
create or replace function private.weave_matching_change(
  p_id uuid,p_action text,p_request_id uuid,p_review_id uuid,p_entries jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
-- Checks the caller and locks the card, as before.
declare parent weave.initiatives=private.weave_matching_owner(p_id,true);
  command jsonb=jsonb_build_array(p_id,p_action,p_review_id,p_entries);
  entry private.weave_matching_entries; target regclass;
begin
  if p_action is null or p_action not in ('share','renew','withdraw')
    or (p_action='withdraw' and (p_review_id is not null or p_entries is null))
    or (p_action<>'withdraw' and (p_review_id is null or p_entries is not null))
    then raise sqlstate 'PT400' using message='invalid_data'; end if;
  if private.weave_matching_retry(private.weave_actor(),p_request_id,command) then return private.weave_matching_state(p_id); end if;
  if p_action<>'withdraw' then raise sqlstate 'PT410' using message='matching_shares_retired'; end if;
  for entry in select * from private.weave_matching_selected(p_id,p_entries) loop
    target=case entry.kind when 'need' then 'weave.needs'::regclass else 'weave.offers'::regclass end;
    if entry.matching_audience is null or entry.matching_withdrawn then
      raise sqlstate 'PT409' using message='matching_conflict';
    end if;
    execute format('update %s set matching_withdrawn=true,
      matching_share_version=nextval(''private.weave_matching_version'') where initiative_id=$1 and id=$2',target)
      using p_id,entry.id;
  end loop;
  insert into private.weave_matching_requests(actor_id,request_id,command) values(private.weave_actor(),p_request_id,command);
  return private.weave_matching_state(p_id);
end $$;
