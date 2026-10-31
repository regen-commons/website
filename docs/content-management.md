# Seeds and Contributions management

Status on 29 October 2026: dashboard, Supabase data adapters, versioned schema,
local fixtures, and regression checks are implemented on the feature branch.
The hosted schema and historical import are applied and reconciled after explicit
user approval. Runtime environment configuration and production cutover remain
pending. Do not deploy this branch against the old Notion environment or describe
the production cutover as complete.

## Steward behavior

The desk has Membership requests, Members, Seeds, and Contributions views.
Membership requests are private submissions from individuals or organizations;
the same two types describe members. Linking a profile, accepting a request, and
publishing a profile remain distinct. This change adds no membership decision or
role-grant actions.

Seeds publish on save, with anonymous submissions supported. Stewards can search
and filter Seeds, inspect their stored text/author/tags, and hide or restore them.
Original seed text is retained. A reason is required for moderation.

New Contributions publish immediately. Stewards can create and edit title,
description, type, stage, capital forms, tier, terms, license, tags, and contributor
links. Editing a hidden Contribution keeps it hidden. Hide/restore records a
reason. Only published member profiles receive attribution in the public library;
stewards can still retain links to unpublished profiles privately.

Every content change records the steward, action, revision, and time. Mutations
check the current active role and Auth session inside the database. Concurrent
edits reject stale revisions. Repeated Contribution saves use a retained request
identity; retrying an uncertain create does not create another Contribution.
Private form drafts stay in the page and survive a successful session recheck
when switching tabs. They clear on sign-out or loss of authorization.

## Supabase data boundary

The public `members`, `contributions`, `seeds`, `apply`, and `feedback` handlers use Supabase.
There is no runtime Notion fallback. Public reads use explicit projections in
security-invoker views; private application answers, contact details, and history
are not exposed. Published/hidden state is checked by RLS and the projection.
The routes return `no-store` headers so a new read reflects moderation; already
open pages require refresh. Previously cached production responses must be
invalidated during cutover.

Public intake uses a server-held `SUPABASE_INTAKE_SECRET` whose SHA-256 digest is
stored in `private.intake_settings`. This capability permits bounded intake and
notification processing only. It cannot read the private database, moderate
content, create Auth accounts, or grant roles. It is separate from the steward's
user-scoped client; no service-role key is required. Exposed RPC wrappers run as
the caller. Their narrowly scoped private implementations validate either the
steward/session or the intake capability before accessing protected tables.

Keep the secret in encrypted server configuration and never in browser assets,
chat, source, or a URL. Provision a cryptographically random secret and its digest
together through an authorized operator. The migration deliberately creates no
credential. Missing configuration fails closed.

Both public forms retain an idempotency key for retry within the current page.
Database uniqueness and advisory locks serialize repeated request identities
across instances. Changed content with the same identity is rejected. Reloading
or opening another page creates a new identity; this does not deduplicate people
or content across independent submissions. Quotas are shared in Postgres: three
valid membership saves and six valid Seed saves per connection per clock hour.
Invalid inputs and acknowledged retries do not consume additional quota.

Membership saves create private notification jobs in the same transaction.
Configured Resend/Telegram processing is separate from save success and sends
minimal summaries or a dashboard link, not raw private answers. Resend requests
use stable job identities, bounded requests, and a retry window under 24 hours.
Jobs use leases and a maximum of three attempts. Uncertain Telegram deliveries
require review because its receiver has no deduplication contract. Seed Telegram
notices remain best effort and run only for a newly saved request.

To process a pending notification batch in an authorized live environment:

```sh
node scripts/process-notifications.js
```

This command can send real mail/messages. Do not run it as a fixture smoke.
Use the intended recipients and verified sender configuration. Supabase SMTP
still handles sign-in mail separately; it does not configure receipt senders.

### Membership request receipts

Set production `RESEND_API_KEY` to a sending-only key scoped to the verified
`regencommons.com` domain and `RESEND_FROM_EMAIL=membership@regencommons.com`.
Store the key as a Vercel Secret. `RESEND_REPLY_TO_EMAIL` selects a monitored
reply inbox; it defaults to the website's public `regencommons@gmail.com` address.
These settings do not alter Supabase Auth SMTP or its existing auth subdomain.

The receipt uses the website's light palette and wordmark with inline styles,
table-cell padding, system font fallbacks, and a plain-text alternative. It
confirms that the request was saved and remains subject to steward review. It
does not grant membership, publish a profile, or include private application
answers or a dashboard link. Each receipt goes only to its applicant. Optional
steward recipients remain independently configured by `STEWARD_NOTIFY_EMAILS`.

The existing notification job controls retries and the provider identity. Do not
reset historical skipped/sent jobs to backfill email as part of setup. Real
Gmail delivery and formatting require the verified sender, an approved test
recipient, and live-provider proof; a browser preview is only a layout check.

## Export inventory and migration gates

The supplied Members, Seeds, Contributions, and Participant Feedback exports and
four recovered applications are reconciled in the
[initial import guide](notion-import.md). The import passed direct and staged
local PostgreSQL rehearsals and is now applied and reconciled in hosted Supabase.
These exports contain no attachments. No Notion plugin is needed.
Keep those files private and preserve their folder structure. Run:

```sh
node scripts/inspect-notion-export.js /absolute/path/to/export artifacts/notion-inventory.json
```

The inventory preserves CSV fields and statuses, file paths and checksums, and
page IDs available in filenames. It rejects malformed CSV and symbolic links.
The report may contain private answers; it is created with restricted permissions
under ignored `artifacts/`, refuses to overwrite an existing report, and performs
no database writes. Standard output contains aggregate counts only.

Before hosted cutover:

1. Inspect all three exports and reconcile duplicate views, statuses, source
   identities, full relationships, page bodies, and attachment coverage. Resolve
   names-only CSV relations explicitly where identity is ambiguous.
2. Complete and rehearse the mapping against these actual exports. Preserve raw
   source evidence and import identities in private records. Treat recovered
   messages as a separate source; do not invent submission dates or approvals,
   or silently merge them with saved applications. Legacy applications may lack
   an email/date; absence is now representable without fabrication.
3. Import entities before relations; verify counts, public projections, private
   fields, file bytes, repeat-run behavior, and rejects. The inventory is not an
   importer and does not establish data completeness. An export-specific import
   is now applied and reconciled against the supplied files in hosted Supabase.
4. The user-approved
   [schema migration](../supabase/migrations/20261030030022_content_management.sql)
   and import are complete. Provision the intake credential and configure the exact HTTPS origin and
   Supabase environment. Use separate test and production configuration.
5. Reconcile a final source snapshot under a write pause, retain one writer per
   area, deploy and verify public reads/intake plus steward moderation, and purge
   old caches. Preserve post-cutover Supabase submissions in any rollback.
6. Retain Notion read-only for the agreed recovery period, then revoke its writer
   and remove the retired configuration. Supabase must hold the durable content,
   private submissions, relations, history, source archive, and attachments before
   retiring the source. Store file bytes in Supabase Storage and back them up
   separately from the database.

Hosted application proceeded only after explicit user approval of the exact
schema and data import. Hosted SQL and PostgREST checks match the reconciled
counts, private answers and all source file hashes. Post-change advisors were
inspected; the [import guide](notion-import.md#hosted-reconciliation) records the
receipt and remaining runtime/cutover boundaries.

## Verification

Run `npm run check`, `npm test`, and `npm run smoke`. The same local provider
serves public handlers and the desk, so tests cover public save → desk → hide →
public omission → restore. Notification tests use synthetic transports only.
The default server removes inherited Notion, Supabase, and notification settings.

For a disposable native Postgres 17 database, apply
[local Auth stubs](../supabase/tests/local-auth.sql), both migrations in order,
then run [steward access checks](../supabase/tests/steward-access.sql) and
[content checks](../supabase/tests/content-access.sql) with `psql -v ON_ERROR_STOP=1`.
The role/session stubs are test-only and must never be applied to hosted Supabase.
SQL test records roll back. CI runs these checks against its own Postgres service.
They establish PostgreSQL grants, RLS, and transaction behavior, not hosted Auth,
PostgREST configuration, provider delivery, or deployment.

The rendered synthetic dashboard was exercised at desktop and 390px mobile
widths, including Seed moderation, Contribution creation/editing, keyboard form
access, sign-out, and preserved drafts during session rechecks. Browser evidence
is local fixture proof; no real notifications or membership records were created.

The sign-in layout was compacted after laptop-height feedback. At 1280×720 the
initial card is about 413px tall, down from 646px. Email entry, code entry, and
invalid-code feedback fit without page scrolling at 1280×720, 1024×600, and
390×667. At 480px height the document scrolls naturally; the card has no fixed
height or nested scrolling. Demo instructions use a native, keyboard-accessible
disclosure. The fixture banner stays in document flow during sign-in so it cannot
cover the form. These layout changes preserve the existing sign-in behavior.

The dashboard and public pages share [theme control styles](../theme-toggle.css)
and the same sun/moon artwork and `rc-theme` preference. The steward header uses
44px controls. On screens up to 850px wide, a header button opens the workspace
navigation as a native popover, with an ordinary disclosure fallback for browsers
without Popover support. Desktop keeps the sidebar. Only one navigation element
exists, and sign-out or lost authorization closes the menu and hides its trigger.
Repeated workspace labels and the global governance notice were removed from
the content header; private request descriptions and publication guidance remain
in the views where they help the steward.

Rendered verification covers all four destinations, current-section state,
keyboard opening and Escape dismissal with focus return, outside dismissal,
mobile/desktop resizing, menu access after scrolling, and sign-out. The menu fits
320×568 and 390×667 without horizontal overflow; at 844×390 it scrolls within its
available height. The website-to-admin theme update and reload persistence were
checked with synthetic local data. The legacy disclosure fallback was reviewed
in code, not exercised in an older browser.

The [work plan](work-plan.md) owns remaining migration work; the
[roadmap](steward-roadmap-and-migration.md) records the research baseline.
The [production cutover record](production-cutover.md) records final-source
confirmation, runtime setup, review fixes, and release verification.

## Email delivery status and controlled retries

Each membership request detail loads its email ledger separately. A status outage
leaves the original application visible and offers **Refresh email status**.
The card shows receipt/steward-email status, attempts, the last known attempt time,
the Resend message ID with a provider link, and a fixed, safe failure reason.
Provider response bodies, credentials and arbitrary error messages are never
stored or returned. Older attempts without diagnostics remain **Not recorded**;
imported requests with no jobs are not emailed automatically.

**Accepted by Resend** means the send API returned a message ID. This release does
not track inbox delivery, bounces, opens or clicks; those require provider events.
It does not change the membership receipt template or membership decision rules.

**Retry receipt email** and **Retry steward email** send only their selected saved
job. The database checks the active steward role and live Auth session, application
identity, current attempt count, and lease under a row lock. It retains the original
`membership/<job ID>` Resend idempotency key and the three-attempt / 24-hour limits. New claims stop one minute
early to leave time for bounded network calls.
Fresh in-flight attempts, accepted messages, stale commands, exhausted jobs and
expired windows are rejected. An abandoned email lease can be reclaimed after five
minutes within the original window. Attempts are never reset, and Telegram cannot
be retried through this action. A retry records the actor and time. Only the server-held intake capability can
record its provider outcome, including if the initiating session ends after the
send. The recipient
comes from the saved application, not the browser command.

Apply `20261031001734_steward_email_delivery.sql` before deploying this branch.
The previous worker API remains compatible during rollout, but older runtime code
cannot record new provider diagnostics. No historical status or message ID is
backfilled. The reviewed migration is applied to Regen Commons / Website under hosted
version `20261031001734`; the local filename matches that migration history.
Runtime release and live retry verification are recorded in the PR. No scheduled worker or Resend
webhook is introduced.

The disposable database checks in
[notification-access.sql](../supabase/tests/notification-access.sql) exercise
private projections, non-steward denial, metadata spoofing, role/session revocation,
lease fencing, stale commands, retry limits, session expiry during sending,
active-lease cleanup and provider-result persistence.
Node transport tests use synthetic Resend responses; the default fixture dashboard
simulates a failed receipt, an accepted steward email, an expired window and an
empty imported ledger without making external calls.
