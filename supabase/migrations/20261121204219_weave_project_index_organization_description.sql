-- Local candidate after weave-project-index-work-scope. Not applied anywhere. Apply through the website's
-- migration path as a new migration, before the API that writes this column is deployed.
--
-- The opening sentences of the description on the publisher's Certified organization record, which the
-- public list searches so a search for an organization's mission finds its projects. It describes the
-- publisher, not the project, so it sits on the source row beside the card's other facts and never among
-- the project's evidence passages, which matching reads. Cards do not show it. The index job writes it on
-- every indexed read, keeps it through a transient source failure and clears it whenever it deletes a
-- project's evidence.
--
-- A nullable column rewrites no rows. Existing rows read as having no description until the next refresh.
alter table private.weave_project_index_source
  add column organization_description text check (
    organization_description is null or char_length(organization_description) between 1 and 3000
  );
