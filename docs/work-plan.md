# Initial development work

Ordered after the 29 October 2026 [assessment](assessment-2026-10-29.md).
These are repository-local work items, not tickets created in an external system.
Each item can become a bounded PR; product/account decisions are explicit.

## 0. Development foundation — implemented

Credential-free local server, Node selection, agent guidance, one focused skill,
current setup/integration documentation, tests, smoke, and GitHub CI configuration
are implemented. The default local server is independent of Vercel and the shared
workbench. The GitHub Actions Check workflow passed on the foundation commit
([run](https://github.com/regen-commons/website/actions/runs/40947030458)).
This establishes fixture checks, not a deployed preview or live-provider proof.

## 1. Make seed and map feedback truthful — implemented

**Scope:** shared request/save helpers, both seed forms, map states, and local
failure scenarios. See the verification record below for repeatable checks and
their limits.

**Verified:** seed submission waits for HTTP success and `{ ok: true }` before
confirmation; 3–240 character validation matches the API. Network/429/5xx failures
retain the draft and offer retry. Pending and acknowledged saves reject duplicate
clicks. Direct entry and Learn → Plant work; Learn navigation/reload does not post
again. Graph and library independently distinguish loading, empty, failed, and
loaded reads, with keyboard-accessible retries and a separate filter-empty state.

**Evidence:** automated behavior tests, HTTP smoke, and rendered local fixtures at
desktop and 390px mobile widths. See the [verification record](local-flow-verification.md)
for cases, repeatable controls, and limits. No live provider or deployment proof
is implied.

**Publication wording:** the form states “Your seed becomes public when saved.”
Drafts remain in browser storage; confirmed saves retain the existing immediate
publication rule. An uncertain network result can still have persisted remotely;
manual retry is not a guarantee of exactly-once persistence. Durable idempotency
for seed and application writes remains follow-up work in item 3.

## 2. Establish a verified integration environment — parallel ownership work

**Updated direction:** Supabase and `/admin` email-code access are confirmed;
Directus is not part of the plan. The [read-only dashboard slice](steward-dashboard.md)
was merged in [PR #3](https://github.com/regen-commons/website/pull/3), after the
foundation PRs. Its schema and PostgreSQL access
tests ran against Regen Commons / Website. Local auth and review flows use
synthetic fixtures. Resend's `auth.regencommons.com` domain is verified, custom
SMTP and the code template are saved, and the approved steward is provisioned.
Resend confirms real test-code delivery. The approved steward completed code
entry, and authenticated application/member reads succeeded; no public provider
cutover has occurred. Dashboard design alignment uses shared website tokens and
self-hosted dashboard fonts on `codex/steward-smtp-design`. It reuses the website's
mycelium logo in still mode. Gmail desktop feedback prompted a table-based email
layout; the revised email is delivered and the recipient confirmed correct
padding in Gmail desktop.

**Next boundary:** deploy the verified steward surface, then agree
acceptance/publication authority and migration scope. The remaining
Notion work below is source inventory/export and reconciliation, not investment
in a lasting replacement development database. Preserve separate acceptance and
publication until council policy is agreed.

**Scope:** account inventory and development configuration, followed by an
explicitly authorized live smoke. No production migration is implied.

**Done when:** record responsible owners and access paths for GitHub, Vercel,
Notion, Resend, and the separate agent without storing secrets. Confirm ownership
of the inherited Members data, exact schema, member-publication expectations,
domain status, branch protections, and deployment linkage. Select separate
development databases and notification destinations. Pin a tested Vercel CLI and
prove `dev:live` serves actual handlers rather than invoking the fixture command.
Then demonstrate read → authorized synthetic write → steward publish/hide → read,
plus email/Telegram delivery if enabled. Record cleanup and rollback steps.

**Decision:** keep or migrate the OpenCivics-backed workspace; identify who can
authorize any data move. Review the database-creation script's legacy default ID
before use. Live test writes/messages require authorization for the targets.

## 2a. Seeds and Contributions management and Supabase cutover — in progress

**Implemented on the feature branch:** Seeds list/search/filter and hide/restore;
Contribution creation/editing, attribution, immediate publishing, and hide/restore;
recorded actors/reasons/revisions; Supabase public projections and private intake;
durable request identities, shared quotas, and notification jobs. Membership
requests are private applications; Members has Individual and Organization types.
See [implementation and migration gates](content-management.md) and the
[research roadmap](steward-roadmap-and-migration.md).

**Verified locally:** check, regression tests, HTTP smoke, native Postgres 17
migrations and both permission suites. Rendered desktop/mobile proof uses
synthetic fixtures. This work stays separate from public-site polish.

**Historical import complete:** after explicit user approval, the supplied
exports and four recovered application messages were imported into hosted
Supabase and reconciled. The
[import guide](notion-import.md) records counts, private source preservation,
confirmed member typing/merge, repeat-run behavior, and verification.

**Cutover in progress:** the user confirmed the exports are final and source edits
are paused; a fresh inventory matches the hosted receipt. Production runtime and
the bounded intake credential are configured. Review fixed queue ordering for
unknown dates and, at the user's request, replaced the public Notion feedback
form. See the [cutover record](production-cutover.md).

**Pending:** feedback migration, current-head CI, merge/deployment, live flow
verification, cache checks, and Notion runtime retirement. Public production
remains on its deployed provider until release verification completes.

## 3. Make application and notification failures observable

**Membership confirmation email:** add `regencommons.com` as a separate Resend
sender, then enable application receipts from `membership@regencommons.com` after
DNS verification. Receipt wording confirms a saved request and pending steward
review. Use the website's light palette and wordmark, table-cell padding, system
font fallbacks, a plain-text alternative, and the public contact inbox for replies.
Retain durable notification jobs and stable provider retry identities. Verify one
named test recipient in Gmail before enabling the production sender. Do not send
historical applicants a backfill or enable additional steward recipients.

**Current proof:** the template and delivery adapter pass 55 tests, check, and
smoke. Synthetic browser previews verify desktop and 320px padding without
horizontal overflow. On 30 October, the three authoritative DNS records matched
Resend's values, the root domain became Verified, and the operator saved a
domain-scoped sending key as a production Vercel Secret. A single QA-copy email
to the approved test recipient was delivered to Gmail's inbox with the intended
padding, colors, and typography. Gmail shows the root-domain signature and reply
inbox. Release and automatic form-to-receipt verification remain pending. The QA
template is a test copy; the application module remains the runtime authority.

**Scope:** `api/apply.js`, `api/seeds.js`, `api/_lib/notify.js`, provider-boundary tests.

**Done when:** handle Resend's fulfilled `{ error }` results; bound notification
timeouts; distinguish a saved application with failed notifications from a failed
save; remove claims that fallback capture cannot lose data. Verify 429/5xx retry,
schema rejection, all capture channels unavailable, and duplicate/repeated submits.
Choose a recoverable capture/idempotency strategy with clear data retention.

**Decision:** who may receive raw application answers on recovery, and whether
Telegram is an appropriate destination for those private fields. Do not expand
recipients or data sharing as an incidental implementation detail.

### Steward email delivery status and retry — separate draft PR

**Scope:** add a private email card to membership request details, with safe failure
reasons, attempts, attempt timestamps, Resend IDs, refresh, and one-job retry.
Preserve duplicate-send protection, active steward/session checks, existing
membership semantics, and public-site styling. No public-site polish, schema
application, production deployment, live send, webhook, or scheduled worker.

**Acceptance:** an authorized steward can inspect and retry one eligible email;
anonymous/non-steward/revoked sessions cannot read or retry; stale/concurrent
commands cannot send twice; accepted, expired and exhausted jobs cannot be retried;
status errors remain visible independently of application data. Verify database
rules, injected provider failures, desktop/mobile rendering and keyboard access.
Release requires the new migration before runtime deployment. See
[email delivery contract](content-management.md#email-delivery-status-and-controlled-retries).

**Local proof:** 64 Node tests, syntax/link checks, HTTP smoke, and all four SQL
access suites pass in disposable PGlite PostgreSQL. Rendered fixtures cover
1280×720 desktop and 390×844 mobile, both themes, keyboard retry, status-error
recovery, empty history, expired retries, and clearing pending data on sign-out.
GitHub CI supplies native PostgreSQL 17 proof for the draft revision. No real
email was sent and the hosted schema remains unchanged.

## 4. Define publication rules and validate input at the API boundary

**Scope:** all API handlers, Notion schema inspection, focused behavior tests.

**Done when:** decide whether contribution attribution may reveal a non-Active
member; preserve the agreed rule in tests. Validate request types, field lengths,
URLs, and accepted options before provider writes. Confirm intentional anonymous
seed behavior (the current author input is not saved). Provide read-only schema
validation that reports exact missing/mismatched properties without altering data.
Evaluate durable abuse controls against actual traffic; do not add infrastructure
without a demonstrated need.

## 5. Make the five-page experience accessible and maintainable

**Public polish slice:** font delivery, Join step focus/validation, named site
navigation, and keyboard/touch Learn controls are implemented on the independent
`codex/public-fonts-join-navigation` branch. The [verification record](public-polish-verification.md)
records 100 in all four standard Lighthouse categories on the five public pages,
mobile and desktop, with local UI evidence and earlier score variation retained.
Dashboard changes landed independently in PR #4. Canvas alternatives, broader
reduced-motion coverage, and a deployed-site rerun remain follow-up work; automated scores do
not close those manual accessibility requirements.

**Scope:** navigation, canvas alternatives, forms, modal behavior, shared styling.

**Done when:** keyboard users can complete key journeys and access graph content;
form groups/errors have useful accessible names and focus; reduced motion is
respected; the pages work at 390px and a normal desktop width without unintended
overflow. Capture reproducible browser evidence and check console errors.
Extract large inline scripts into feature files only where it improves this work,
preserving behavior. A framework migration is not a prerequisite.

## 6. Refine the development loop once the first changes land

**Scope:** optional Dev Workbench registration, dependency maintenance, browser CI.

**Done when:** decide whether cross-repo launch adds value; if so register the
native server and health URL without making this repo depend on the workbench.
Modernize the npm lockfile in a dedicated change, review SDK upgrade compatibility
and the Node deprecation warning, and add repeatable browser smoke for the five
routes and form success/failure paths. Keep one authoritative package manager and
avoid a large formatter-only diff mixed into a product change.

### Email delivery release follow-up — 30 October 2026

Review reproduced client-authored acceptance metadata and loss of completion when
queue cleanup retired an active send. The result path now uses the existing
server-held intake capability, so the initiating session can end without losing
the provider outcome. Active leases survive cleanup, and email claims stop a
minute before the 24-hour cutoff to allow for bounded network calls.

The corrected migration is applied to Regen Commons / Website as
`20261031001734_steward_email_delivery.sql`; the local filename matches hosted
history. Read-only hosted checks confirm active-steward projection grants,
anonymous denial, closed private tables and no client completion endpoint. The
64 Node tests, check, smoke and disposable SQL suites pass. The broad synthetic
Auth/role mutation suite was not run in production. Native PostgreSQL CI, merge,
deployment and the named-account email verification complete the release.
# Membership review and profile management

Separate draft PR from public-site polish. User confirmed one active steward may
record review decisions, request changes, and reopen with a reason. Approval,
membership standing, and visibility remain separate.

- [x] Add transactional, revision-checked review and profile commands with
  actor-scoped retry identities and private audit evidence.
- [x] Preserve original answers and legacy visibility; initialize standing as
  unconfirmed without inventing historical decisions.
- [x] Add draft creation/linking, curated profile editing, affiliations, standing
  and visibility controls to the steward desk.
- [x] Add API and disposable SQL coverage for independent states, stale writes,
  replay, private projections, validation, and current authorization.
- [x] Check, all 74 Node tests, smoke, and all five SQL suites pass locally.
  Browser checks cover 1280×800, 390×844 and 320×568; both themes, keyboard
  submission/menu, required reasons, independent state changes, draft creation,
  conflict recovery with retained values, and private-state clearing on sign-out.
- [x] PR #9 review fixes preserve a revision-consistent affiliation snapshot and
  replay the original command after uncertain saves. All 74 tests pass.
- [x] Applied hosted migration 20261031024410; prior member/application digests
  and all 19 published profiles are unchanged. Standing is unconfirmed for all 24 profiles.
- [x] PR #9 merged as dafc048 and deployed. Live temporary records verified
  independent review, standing, visibility, profile edits, and affiliations; all
  temporary records were removed and original digests reconciled.

The separate PR records publication and current-head CI results. Local screenshots
are ignored artifacts under artifacts/membership-management; no real data or live
messages were used.

Contract, tradeoffs, and later release prerequisites:
[membership management](membership-management.md).

## Membership decision emails

Separate draft PR from public-site polish; automatic production release is outside
this task. Add approved, declined, and changes-requested emails using the website
design and existing Resend delivery diagnostics. Preserve private review reasons
and independent membership/profile states. Test real delivery only with the named
account authorized in the chat.

- [x] Atomic decision/outbox command with immutable recipient/content snapshot,
  idempotent replay, private/public text separation, and obsolete-email blocking.
- [x] Steward recipient/message controls and per-decision email status/retries.
- [x] Shared branded HTML shell and text alternative for all three decisions.
- [x] 79 Node tests, check, smoke, and six disposable SQL suites pass.
- [x] Desktop/mobile, both themes, keyboard submission, required public message,
  reopening without mail, and uncertain-save recovery verified with synthetic data.
- [x] Three labeled Resend template test emails arrived in Gmail for the named
  account; padding, typography, content, sender, and Reply-To verified.

The separate draft PR owns publication and current-head CI results. The migration
is unapplied and automatic production dispatch remains a release verification step.

Contract and release limits: [membership decision emails](membership-decision-emails.md).
