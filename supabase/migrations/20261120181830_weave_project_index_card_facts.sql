-- Local candidate after the public project index (applied as 20261109050006_weave_project_index).
-- Not applied anywhere. Apply through the website's migration path as a new migration, before the
-- API that writes these columns is deployed.
--
-- What a public list card says about a project besides its own words: the publisher's display name,
-- the place the collection pins and the kinds of group the publisher says it is. They come from
-- records other than the collection, so they sit on the source row, not in the evidence passages or
-- their content hash. The index job writes them on every indexed read and clears them whenever it
-- deletes a project's evidence; a transient source failure keeps them with the evidence.
--
-- Adding nullable columns and one with a constant default rewrites no rows. Existing rows read as
-- having none of the three until the next complete refresh, whose new extraction version rewrites
-- every listed project.
alter table private.weave_project_index_source
  add column publisher_name text check (publisher_name is null or char_length(publisher_name) between 1 and 120),
  add column place_name text check (place_name is null or char_length(place_name) between 1 and 120),
  add column organization_types text[] not null default '{}'
    check (cardinality(organization_types) <= 5 and array_position(organization_types, null) is null);
