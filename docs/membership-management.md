# Membership review and profile management

This feature adds steward actions for private application review, curated member
profiles, membership standing, and profile visibility. It is separate from public
site polish. The reviewed migration is applied to Regen Commons / Website under
hosted version 20261031024410. Runtime release and temporary-record verification
are tracked in PR #9. No live member decisions or notification backfill are implied.

## Independent decisions

The user confirmed that one active steward may approve, decline, request changes,
or reopen an application with a recorded reason. Each command requires the current
steward role, a live Auth session, a request identity, and the expected record revision.

| Area                | States                                                                 | Effect                                                           |
| ------------------- | ---------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Application review  | pending, changes_requested, approved, declined; legacy_active retained | Records a decision on the private submission                     |
| Membership standing | unconfirmed, active, paused, ended                                     | Records the steward's explicit assessment of membership standing |
| Profile visibility  | draft, published, hidden                                               | Controls public website visibility                               |

Approval changes only application review. It does not create a member, activate
membership, publish a profile, change submitted consent, grant access, or send mail.
Standing and visibility are also independent: pausing membership does not hide an
already published profile. The UI describes each operation before its save action.
Standing can be maintained for manually curated members without an application;
it is not inferred from an application or a website visibility label.

Pending applications can be approved, declined, or marked changes_requested.
Changes_requested can move to approved, declined, or pending. Approved and declined
decisions must be reopened to pending before a different outcome is recorded.
Legacy_active can enter any current review state through an explicit steward
decision. Its source meaning is preserved until then.

Existing profiles start with standing unconfirmed. Their names, source identities,
publication states, affiliations, private applications, and original answers are
unchanged. No historical decisions or audit events are fabricated.

## Curated profiles

Members remain individuals or organizations in the same table. The Members view
links to profile management and supports creating a standalone draft. Application
details also support creating a draft linked to that application, linking an
existing matching-type profile, and clearing a link. A profile link is not a merge.

The creation form prefills the applicant name and type for explicit curation.
Original answers are never automatically mapped into profile prose. Saving a new
profile creates a draft with unconfirmed standing; linking it and recording its
history happen atomically. A repeated creation request returns the same result.

Editors cover name, location, summary, public vision, website/avatar URLs, focus
areas, contribution areas, and individual-to-organization affiliations. URLs must
use HTTP or HTTPS. This feature does not upload files. Member type is fixed after
creation to preserve identity and existing relationships; reclassification remains
a separate controlled operation.

Editing preserves standing and visibility. Edits to a published profile update its
public fields immediately; the form states that consequence. Public member views,
field projections, attribution rules, and page styling remain unchanged. The public
API's legacy Active label remains a publication compatibility value, not the new
private membership standing.

## Persistence and access

The migration adds membership_status, revision, and updated_at to members;
extends review_events with actor, state-transition, resulting-revision and link
evidence; and adds member_events with profile snapshots and state changes.
Private membership_requests retains actor-scoped command results for safe replay.

The exposed membership_command RPC runs as its caller. Its private implementation
checks current role/session before replay or mutation, validates allowlisted fields,
locks the affected row, rejects stale revisions, and records the change and history
in one transaction. It cannot change original answers, source identities, Auth
accounts, steward roles, or notification jobs. Direct table writes stay denied.
Neither a service-role key nor the public-intake capability is used.

New standing and audit fields have no anonymous grants. Existing published field
projections remain unchanged. Review and member histories paginate through provider
limits. Private forms remain in memory, retain values on write failures, and clear
on sign-out, lost authorization, navigation, or page exit. Uncertain requests retain
their exact command and identity. An uncertain save locks its values until retry
recovers the outcome. A definitive validation failure allows correction. Profile
revision and current affiliation choices are read in one PostgREST statement, so
a stale directory response cannot silently overwrite newer relationship edits.

## Verification and release

Run npm run check, npm test, and npm run smoke. The new membership-access.sql suite
belongs only in a disposable database and rolls back its synthetic records. CI
applies every migration to PostgreSQL 17 and runs it alongside the existing suites.
The owning work-plan entry records executed checks and browser evidence.

The applied
[20261031024410_membership_management.sql](../supabase/migrations/20261031024410_membership_management.sql)
matches the hosted migration history. Post-apply checks preserve the existing
profile/application digests and published counts. Deploy the matching API and
dashboard, then verify independent states and public privacy boundaries with
authorized temporary records. Do not run the broad synthetic Auth/role suites in
production or infer hosted verification from fixtures.
