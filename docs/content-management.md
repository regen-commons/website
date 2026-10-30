# Seeds and Contributions management

Implementation status on 29 October 2026: dashboard, Supabase data adapters,
versioned schema, local fixtures, and regression checks are implemented on the
feature branch. The hosted schema, historical import, environment configuration,
and production cutover are pending. Do not deploy this branch against the old
Notion environment or describe the migration as complete before reconciliation.

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

The public `members`, `contributions`, `seeds`, and `apply` handlers use Supabase.
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

## Export inventory and migration gates

The user will provide Members, Seeds, and Contributions CSV/Markdown exports,
attachments, and messages about failed submissions. No Notion plugin is needed.
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
   remains pending until the real files arrive.
4. Obtain hosted migration approval, apply the
   [schema migration](../supabase/migrations/20261030004638_content_management.sql),
   provision the intake credential, and configure the exact HTTPS origin and
   Supabase environment. Use separate test and production configuration.
5. Reconcile a final source snapshot under a write pause, retain one writer per
   area, deploy and verify public reads/intake plus steward moderation, and purge
   old caches. Preserve post-cutover Supabase submissions in any rollback.
6. Retain Notion read-only for the agreed recovery period, then revoke its writer
   and remove the retired configuration. Supabase must hold the durable content,
   private submissions, relations, history, source archive, and attachments before
   retiring the source. Store file bytes in Supabase Storage and back them up
   separately from the database.

Automatic approval review rejected a hosted DDL rehearsal because production
schema/grant changes can acquire locks even inside a rolled-back transaction.
No hosted migration was applied. Local proof uses a disposable Postgres 17
container; hosted migration and post-change advisors remain pending approval.

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
