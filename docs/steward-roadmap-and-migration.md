# Steward dashboard roadmap and Notion migration

Research baseline and proposed delivery sequence, 29 October 2026.

For current feature-branch implementation and outstanding hosted/import gates,
see [Seeds and Contributions management](content-management.md). Statements about
the read-only pilot below describe the pre-implementation research baseline.

The steward desk can become the working home for membership review, public
profiles, Seeds, and Contributions. The current desk is a read-only Supabase
pilot; the public site still uses Notion. Move one complete data flow at a time,
with an export, reconciliation, and recovery path before changing its writer.

**Confirmed product decision:** Seeds publish immediately after a successful
save. Stewards moderate afterward by hiding or restoring them. Preserve
anonymous submissions; no review queue before publication is required.

## What exists today

There are two storage systems in use. The code references **three Notion
collections**, through `NOTION_MEMBERS_DB_ID`, `NOTION_CONTRIBUTIONS_DB_ID`, and
`NOTION_SEEDS_DB_ID`. Their actual workspace ownership, schemas, and record
counts still need a live inventory. One Supabase project can hold all these
areas in separate related tables; a separate database per feature is unnecessary.
Supabase provides a full Postgres database per project, with Auth and Storage
alongside it ([database overview](https://supabase.com/docs/guides/database/overview)).

| Area | Public site today | Steward desk today | Useful next capability |
| --- | --- | --- | --- |
| Applications | Join form writes a Pending Notion Members row | Search, filters, original private answers, profile preview, recorded history | Review notes, assignment, and decisions once authority and transitions are agreed |
| Members and organizations | Map reads Active Notion Members | Read profiles, publication state, affiliations, and contribution attribution | Curate profiles; publish, hide, and restore; maintain organization links |
| Seeds | Notion read/write; new submissions are Active immediately | No view or table | Search, tags, hide/restore, reasons, and moderation history |
| Contributions | Library reads Active Notion Contributions | Related attribution is visible through member review | Dedicated list/editor for title, description, type, stage, terms, license, tags, and contributors |
| Notifications | Optional Resend/Telegram intake notices | No delivery management | Receipt status, failures, and controlled retries |
| Steward access | Separate from public membership | Email-code sign-in and an administrator-managed active role | Controlled provisioning/revocation; a role editor only if needed |

Live read-only inspection of Regen Commons / Website found zero rows in
`applications`, `members`, `contributions`, `affiliations`,
`contribution_members`, and `review_events`, and no `seeds` table. One steward
role is provisioned. New public applications therefore do not enter the
dashboard queue yet. Adding the desk did not migrate intake.

The [dashboard record](steward-dashboard.md) describes the verified real sign-in.
Deployment remains a separate dependency: the last hosted check returned 404
for `/admin`, and Vercel reported the existing Hobby/private-organization
repository restriction. A merged PR and a working local sign-in do not establish
that the public steward URL is deployed.

## Keep these meanings separate

- **Application:** a private submission with original answers and a reviewed
  revision. A receipt confirms submission, not acceptance.
- **Member profile:** curated fields intended for publication. Linking a draft
  profile does not accept the application, and accepting does not publish it.
- **Seed:** a public vision on save, independently subject to later moderation.
  A seed does not imply membership or a steward account.
- **Contribution:** a resource with its own publication state, license, terms,
  and attribution. Its author links need an explicit public visibility rule.
- **Steward account:** an Auth identity with separately granted authority.
  Importing a member must not create an Auth account or grant access.

Application decision rules remain open: who may decide, which transitions are
valid, and whether additional approval is required. Do not derive decisions from
profile publication or invent historic approvals during import. Future commands
should check current role/session and expected revision, then atomically record
the state change and its history. A stale second reviewer must receive a conflict
instead of silently overwriting a newer decision.

## Build Seeds as the first complete slice

Add a versioned migration for Seeds with stable identity, legacy source identity,
original text, existing author/tags, publication state, timestamps with known
provenance, and a revision. Use a dedicated moderation history or deliberately
extend the audit model: the current `review_events.application_id` is mandatory
and cannot represent a seed action.

Keep the existing 3–240 character submission rule. A valid new submission starts
published; hide changes it to hidden, and restore returns it to published. Record
actor, reason, time, and affected revision. Retain original text; any future text
editing should be a separate, attributable revision rather than a silent rewrite.
The current POST parses `author` but does not save it, so preserve existing stored
authors without fabricating missing authorship. Decide how any future author
input is presented before adding it.

Deliver schema, public GET/POST adapters, dashboard list/detail and hide/restore,
synthetic fixtures, and database authorization checks as one bounded feature.
Preserve request/response compatibility and retained drafts on errors. Add a
durable request identity so retrying an uncertain save returns the same result;
the same identity with different content must be rejected. Evaluate shared abuse
controls for anonymous writes; the current in-process quota is not shared across
server instances.

**Completion evidence:** a save appears publicly once; an authorized steward can
hide and restore it with history; anonymous and ordinary authenticated users
cannot moderate; revoked access is denied; stale revisions conflict. Verify
visibility through the deployed public route. Current public handlers permit
five minutes of CDN caching plus ten minutes of stale reuse, so moderation also
needs verified invalidation or a suitably changed cache policy.

## Prepare the target before importing

The pilot schema is a useful start, not a complete public-site replacement.

| Gap | Required treatment |
| --- | --- |
| No Seeds model | Add the table, moderation contract, and history described above |
| Member public fields | Add explicit avatar/storage reference, public vision, and applied-date mapping; `summary` and import-time `created_at` are not automatic substitutes |
| Legacy Members mixes applications and profiles | Split private submission evidence from curated profile fields; some manually curated profiles may have no application |
| Application constraints | `email` and submission time are required, and `member_id` is unique; resolve missing legacy evidence and repeat applications before import |
| Limited history model | Keep application review distinct from profile, contribution, and seed publication events |
| Import provenance | Track source/page identity, source edit time, capture digest, mapping version, import batch, and target identity in private migration records |
| Repeated writes and notifications | Add durable submission identities and notification jobs before intake cutover |

Do not create fictitious applications, emails, submission dates, consent, or
reviewers to satisfy constraints. Keep incomplete legacy evidence in private
staging until it has an agreed representation. If one member can apply more than
once, evolve the current one-to-one link deliberately.

Public reads must use an explicit allowlist and publication filter, even though
several private tables live in the `public` schema. Preserve the existing public
API shapes in [integration contracts](integrations.md). Keep provider credentials
on the server and retain the steward's user-scoped access checks; enabling action
buttons is not a reason to grant broad table writes. Supabase requires table
grants and RLS policies to work together
([API access control](https://supabase.com/docs/guides/api/securing-your-api)).

## Migrate in stages

### 1 Inventory the actual Notion sources

Obtain read-only access to the three configured collections and confirm who can
authorize their migration, including any inherited OpenCivics-owned content.
Record property IDs/types, status options, counts by status, duplicate candidates,
missing required values, affiliations, contributor relations, files, and source
edit times. Determine whether page bodies, comments, or extra properties contain
material that must be preserved beyond the current website fields.

Use a version-pinned exporter with explicit data source discovery. The website
currently pins `@notionhq/client` 2.2.15 and calls the older database-query API.
Notion introduced data sources in its
[2025 API change](https://developers.notion.com/guides/get-started/upgrade-guide-2025-09-03);
the [2026 upgrade](https://developers.notion.com/guides/get-started/upgrade-guide-2026-03-11)
also changes trash/archive semantics. Test the selected SDK/API pair, including
deleted or trashed records, independently of an unrelated public-site SDK upgrade.

### 2 Capture privately and approve the mapping

Export complete paginated records and relations with resumable progress and
rate-limit backoff. Notion's property endpoint paginates title, rich text, people,
and relation values; follow every cursor rather than assuming the initial page
contains everything
([property retrieval](https://developers.notion.com/reference/retrieve-a-page-property),
[request limits](https://developers.notion.com/reference/request-limits)).
Do not reuse the website's first-file reader or its truncating rich-text writer
as a full-fidelity migration tool. Preserve the available source without claiming
to recover answers already lost or truncated before export.

Map private Members application fields to private submission evidence and
approved public fields to profiles. Inventory all statuses: the current public
readers publish exactly `Active`, excluding even `Steward`. Preserve the current
public set unless a separate decision changes it. Unknown statuses need explicit
mapping. Keep full relations and a durable source-to-target ID map; do not merge
records merely because names or email addresses match.

Copy approved avatars and other in-scope files to durable storage, with private
application attachments kept private. Notion-hosted file URLs expire after an
hour, so importing their URLs alone is insufficient
([Notion files](https://developers.notion.com/reference/file-object)). Verify
file bytes/checksums and retain their source mapping. Use separate access rules
for public assets and private files
([Supabase Storage access](https://supabase.com/docs/guides/storage/security/access-control)).

Keep raw captures, manifests containing personal data, and credentials out of
Git and browser assets. Commit mapping code and synthetic examples only.

### 3 Rehearse a repeatable import

Import into a separate authorized test database or local real Postgres before
loading production. Resolve entities before affiliations and contributor links.
Use source identity to make reruns repeatable, with explicit rejects and conflict
reports. A repeat run must create zero duplicates and must not overwrite newer
steward edits. Keep original source status/time distinct from the time of import.

A controlled importer is preferable here to a manual CSV upload because the
source needs splitting, relationship reconstruction, and reconciliation. Supabase
supports both CSV and programmatic loading; choose the loading method after the
inventory establishes volume
([import options](https://supabase.com/docs/guides/database/import-data)).

Reconcile counts by collection and source status, source/target identities,
public API field parity, long and Unicode text, complete relations, and every
in-scope attachment. Account for every omitted or rejected record. Check that
public responses contain no private answers, email, or review notes. Exercise
anonymous, ordinary authenticated, active steward, revoked role, and revoked
session access against actual PostgreSQL; HTTP fixtures alone do not prove RLS.

### 4 Switch one coherent flow at a time

**Seeds first:** after its rehearsal, briefly pause Seed writes, capture a final
delta and removals, reconcile, and switch both its public reads and writes to
Supabase. This gives a small end-to-end migration before the membership graph.

**Membership graph next:** migrate Members, affiliations, Contributions, and
private applications together, then switch their public readers and application
intake in a coordinated release. Reconcile final edits and removals under a short
write pause. Maintain stable public relation identities or an explicit compatible
translation. Avoid indefinite dual writes; each area should have one writer.

The current Contributions reader resolves contributor names without checking
whether that related member is public. Agree the attribution rule before this
cutover; copying that behavior blindly could expose a nonpublic member's name.

Verify an authorized test submission reaches the dashboard, its receipt state
is accurate, public reads match the approved projection, and hide/restore behaves
correctly through the actual deployment and cache. Resolve the deployment
restriction before treating these checks as complete.

### 5 Preserve recovery and retire the old writer

Keep the source export and Notion read-only for an agreed retention period.
Back up and rehearse restoring the database **and file objects**: Supabase database
backups do not include Storage object bytes. Check the project's backup plan;
Supabase recommends separate regular exports for free projects
([backup coverage](https://supabase.com/docs/guides/platform/backups)).

Define a rollback checkpoint and owner before cutover. New Supabase submissions
must survive any reversal: reverting code to Notion alone strands those writes.
Pause and reconcile them into the chosen writer, or repair forward. Revoke the
old writer only after recovery and post-cutover reconciliation pass.

## Make communications manageable

Save an application and its notification job in one transaction, then send
asynchronously with bounded retries and visible delivery state. Mail failure
must not erase a saved application or tell the applicant their save failed.
Handle Resend's returned error objects as well as thrown errors.

Use stable event identities and a durable local send ledger. Resend's
[idempotency keys](https://resend.com/docs/dashboard/emails/idempotency-keys)
deduplicate for 24 hours; retries beyond that window need reconciliation rather
than an assumption of permanent provider deduplication. Keep submission, review,
and email-delivery states separate. Do not send welcome/acceptance messages for
historical imports.

Supabase SMTP covers authentication mail. Application receipts and steward
notifications use their own application-level Resend API configuration. The
preferred `membership@regencommons.com` sender needs root-domain verification
and an appropriately scoped sending key; the currently verified authentication
subdomain does not automatically enable it. Agree recipients and the minimum
private information each channel needs before enabling messages.

## Delivery boundaries and remaining decisions

Keep this work separate from public-site polish. Use the following bounded
changes, each with its own review and verification:

1. **Source inventory and mapping:** read-only evidence, status/field decisions,
   synthetic examples, migration ownership, and rejection criteria.
2. **Seeds feature:** schema, moderation, compatible public adapters, repeatable
   Seeds import, and an explicitly scheduled cutover after rehearsal.
3. **Application and profile actions:** agreed review authority, transactional
   commands, publication controls, history, and revision conflicts. Add the
   Contributions editor as a separate follow-on if needed.
4. **Membership importer and cutover:** complete graph/files, submission
   idempotency, notification handling, reconciliation, deployment, and recovery.

The outstanding decisions are application acceptance authority; profile and
contribution publication authority; visibility of nonpublic contributor names;
repeat applications and duplicate resolution; file/body/comment scope; source
ownership and retention; and notification recipients. Seed publication timing
is already decided above.

This research checked repository handlers/schema, live read-only Supabase
structure/counts, and current provider documentation. Live Notion inventory is
still required before estimating migration effort or declaring the mapping
complete. No schema, provider, submission, or deployment was changed for this
research. [The work plan](work-plan.md) remains the owner of overall priorities.
