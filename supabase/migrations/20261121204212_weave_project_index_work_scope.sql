-- Local candidate after weave-project-index-card-facts. Not applied anywhere. Apply through the website's
-- migration path as a new migration, before the API that writes this column is deployed.
--
-- The kinds of work a project's own Certified activity names: the keys of the work scope tags it uses,
-- such as restoration or biodiversity-monitoring, which the public list filters on as Focus. They come
-- from the activity and its tags, not the collection, so they sit on the source row beside the card's
-- other facts. The all-public refresh writes them on every read that reached the activity, keeps them
-- through a failed or skipped read and clears them whenever it deletes a project's evidence.
--
-- A column with a constant default rewrites no rows. Existing rows read as naming no kind of work until
-- the next refresh reads their activities.
alter table private.weave_project_index_source
  add column work_scope text[] not null default '{}'
    check (cardinality(work_scope) <= 10 and array_position(work_scope, null) is null);
