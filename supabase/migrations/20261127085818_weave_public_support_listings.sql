-- Candidate only. Apply after weave-project-index and weave-support-publication (and, in the website's
-- order, after weave-project-index-organization-description); no hosted migration is implied.
-- One public initiative's current needs and offers, for the signed-out public initiative page. The
-- public reader logs in with weave_index_job membership, as the public project list does. It cannot
-- read the workspace schema: this function returns only what Weave published to the project's public
-- repository and confirmed by reading it back, and nothing private (no workspace, actor, entry or request).

do $$
begin
  if to_regclass('weave_workspace.support_listings') is null or to_regclass('weave_workspace.project_links') is null
      or to_regrole('weave_index_job') is null then
    raise exception 'apply weave-project-index and weave-support-publication first';
  end if;
end;
$$;

-- A listing is current when its publication is confirmed (`published` is set only after read-back
-- equality, with the CID read back), its stored record names this exact project and is open, and it has
-- not expired. A link paused by confirmed deletion or unlisting shows none, even before its withdrawals
-- finish. Pending, withdrawing, withdrawn and conflicting publications are left out, as is any entry that
-- is saved or shared for matching but was never published. The expiry is cast only when it has the shape
-- Weave writes, so a malformed stored value hides that listing instead of failing the read. A saved card
-- holds at most five needs and five offers, so the limit only bounds a damaged table.
create function private.weave_public_support_listings(p_project_uri text)
returns table(kind text, rkey text, uri text, cid text, record jsonb)
language sql stable strict security definer set search_path = '' as $$
  select s.kind, s.rkey, 'at://' || l.repository_did || '/com.regencommons.weave.supportListing/' || s.rkey,
    s.cid, s.record_value
  from weave_workspace.project_links l
  join weave_workspace.support_listings s on s.workspace_id = l.id
  where l.project_uri = p_project_uri and not l.matching_paused
    and s.status = 'published' and s.cid is not null
    and s.record_value->>'$type' = 'com.regencommons.weave.supportListing'
    and s.record_value->>'projectUri' = p_project_uri
    and s.record_value->>'kind' = s.kind
    and s.record_value->>'status' = 'open'
    and case
      when not s.record_value ? 'expiresAt' then true
      when s.record_value->>'expiresAt' ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$'
        then (s.record_value->>'expiresAt')::timestamptz > now()
      else false
    end
  order by s.kind, s.rkey collate "C"
  limit 100
$$;

revoke all on function private.weave_public_support_listings(text)
  from public, anon, authenticated, service_role, weave_workspace_runtime;
grant execute on function private.weave_public_support_listings(text) to weave_index_job;
