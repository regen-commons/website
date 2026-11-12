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

**Updated direction:** Supabase and `/council` email-code access are confirmed;
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

**Council access and route (11 November 2026):** make `/council` the canonical
dashboard URL, redirect `/admin` and `/admin.html`, and retain the existing
user-scoped API and role/session checks. Provision the four user-confirmed
council addresses in hosted Auth and grant their active steward roles without
committing the roster. Completion requires account/role readback, route checks,
the repository suites, and rendered fixture sign-in/denial at desktop/mobile
widths. Account provisioning, local verification, and hosted deployment are
separate evidence; the production route is now deployed and verified.
The route implementation, `check`, all 30 tests, smoke, and rendered Brave
fixtures passed; see [verification](steward-verification.md#council-route--11-november-2026).
The four user-confirmed council accounts were created through the explicitly
authorized Auth admin API and granted active steward roles. Committed database
readback verified four confirmed email identities with active roles, plus the
existing steward. The temporary credential copy was removed. No invitations
were sent; the project's default invitation URL still points to localhost.
Recipients still need to complete their own code sign-in. `/council` is live,
and the legacy entry points redirect there. Release `b3a8a6b` on the published
`codex/council-route` branch is Vercel production READY. Source integration into
`main` preserves the deployed route and redirects for subsequent deployments.
The production-based release passed all 81 tests, check, and smoke; live HTTP and
desktop/mobile browser checks passed. See the
[production record](steward-verification.md#production-release).


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

### 5a. Council-call polish round — merged and deployed

From the 5 November council call and the maintainer's site review. Separate
from the Supabase cutover and steward work.

- **Join:** the form restructure shipped in PR #15 was rolled back the same
  day, because it had not been discussed with the team. The original questions,
  steps, required fields, copy and server checks are restored. Only presentation
  fixes remain: questions in full colour above muted hints, 16px inputs, a left
  column that fits beside the form, and browser autofill for name and email.
- **Learn:** practice card no longer tilts; seed cards sit beside their seed in
  the top layer, stay on screen, and close on Escape or an outside tap. Cards
  fit between the header and step dots from 1280×720 up.
- **Map:** every node is labeled, with collision-aware placement; the hover
  card is 280px wide, structured, and kept inside the map.
- **Site:** visible em dashes rewritten in context; page titles become
  "Page · Regen Commons"; Open Graph and Twitter tags, 1200×630 share images,
  PNG and touch icons, robots.txt and sitemap.xml.

**Evidence:** check, 86 Node tests (6 new) and smoke pass. Rendered local
fixtures in the in-app browser: Join submission and every validation path at
1440×900 and 375×812; API rejections over local HTTP; Learn seed cards and card
fit at 1280×720, 1280×800, 1366×768, 1440×900, 1536×864 and 1920×1080; map
labels and hover card with 19 synthetic members. Merged as PR #15 and deployed
on 11 November; the live pages, share images, photos and links were checked
after deploy. No application was submitted through the live form.

**Join form changes for team discussion:** the cohort-commitment question
(those calls have passed), a rework of the participation section, the
colleague and repeated-representative questions, optional Telegram, minimum
answer lengths, the values and contribution questions, and the left-column
wording on cohorts and what becomes public.

**Added in the same round:** `/about` with the five stewards (photos supplied by
the maintainer, alphabetical by first name), governance and contact; `/constitution`
with the v2 MVP text word for word, a labelled plain-words summary, contents and
print styles. The nav's Email link became About; the address now sits on About and
the Join error messages. Rendered locally at desktop and 375px widths.

**Pending, needs council input:** approval of the photos, affiliations and
LinkedIn links (supplied by the maintainer) and of the constitution summary. For
the next council sync: a monthly community onboarding call, and the Membership
Agreement's quarterly cohort and onboarding wording, which no longer matches
practice. The team brief lives in a shared doc outside the repository.

**Constitution synced to the current text (11 November):** `/constitution` now
carries the Notion page "Regen Commons Constitution - MVP" instead of the v2 text,
which Notion lists as legacy. Its seven values and its worldview now match the
Membership Agreement, so the earlier six-or-seven values question is settled. The
page was checked word for word against the maintainer's Notion export (markdown
and PDF). Metadata tables are collapsed, as in Notion. Left out on purpose: the
"Temporary Archive" drafts in three protocols, the empty Principles metadata table
and the Steward Protocol's unfinished "Evolution" sentence. The plain-words
summary was rewritten for the new text and needs the same council review.

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

## About and contact messages — live, 11 November 2026

Scope: one organization per line with verified links; a private contact form on
About; Supabase persistence and retry identities; an authorized Messages inbox in
`/council`; minimal Telegram alerts through the existing agent. Sender addresses
and message bodies remain in the dashboard. Contact intake does not create a
membership application or a public profile. The agent’s stale Notion link label
will be corrected in its repository, with a separate review of Weave integration.

Acceptance: validate and bound input, save before notifying, deduplicate retries,
show truthful success/failure feedback, deny anonymous and non-steward reads,
clear private UI on sign-out, and verify desktop/mobile keyboard flows. Delivery
uncertainty must remain visible without an automatic duplicate Telegram send.
Hosted migration, deployment and real delivery remain separate release steps.

**Evidence:** website check, 88 tests and HTTP smoke pass. All migrations and
nine SQL suites pass in disposable PostgreSQL 17. Rendered in-app Chromium
fixtures cover desktop/mobile organization rows, contact submission and retry,
and private inbox/detail. See [contract and verification](contact-messages.md).
The companion agent adds accurate dashboard labels and contact alerts, fixes
two installed-SDK failures, and records a review and Weave recommendations in
its `docs/agent-review.md`. Hosted migration, publication and real Telegram
delivery remain pending; local checks do not establish those outcomes.

**Authorized production release:** the contact migration is applied to Platform,
and both the agent and website are production READY. A real About-form test is
saved and visible in the authenticated council inbox; the agent acknowledged
Telegram delivery and the dashboard shows Sent. Anonymous access checks passed.
The clearly marked synthetic record is retained for user review. See the
[hosted release record](contact-messages.md#hosted-release--11-november-2026) for
commits, deployments, migration, evidence and rollback targets. Releases use the
published task branches; neither main branch has been merged.

## Council sign-in and filtering polish — live, 11 November 2026

Keep the sign-in card steady across email, code, loading and ordinary error
states by reserving the forms’ natural height and feedback space. Retain native
dropdowns with an inset, theme-aware arrow. Membership type/state changes apply
immediately; search applies after a brief typing pause or Enter, without moving
focus away from the control. Preserve stale-request guards and reset pagination
when filters change. Verification covers desktop/mobile card geometry, keyboard
filtering, empty/error/retry states and the required repository checks.

**Evidence:** check, all 88 tests and HTTP smoke pass. Rendered in-app Chromium
fixtures at 1280px and 390px confirm equal sign-in card height across email, code
and invalid-code states, automatic type/state filtering, search after a typing
pause and Enter, focus retention, filtered-empty feedback, and failed-read retry.
Both themes show inset dropdown arrows without horizontal overflow. See the
[council usability record](steward-verification.md#council-usability--11-november-2026).

**Released:** website `5dd6b20` is production READY. Live asset bytes match the
verified source, and the authenticated dashboard confirmed automatic search,
focus retention, the removed button, padded arrows and recovery to the full
queue after clearing the verification search. The existing session was retained.
See the [hosted usability release](steward-verification.md#hosted-usability-release).


## Contact form visual consistency — 11 November 2026

Use the membership form’s existing card, field spacing, display labels, serif
inputs, textarea and organic button on About. Move the card rules into the shared
stylesheet so both forms use one definition, including mobile padding. Preserve
contact validation, private submission and retry behavior.

**Evidence:** check, all 88 tests and HTTP smoke pass. Rendered in-app Chromium
fixtures at 1280px and 390px confirm the shared styles, both themes, no horizontal
overflow, 16px input text, keyboard focus and required-field validation. A failed
synthetic save retained the draft and succeeded on retry. Membership card padding
and responsive layout are preserved. Local guidance retrieval remains unavailable;
this change follows the existing native controls and repository styles without
refreshing the online guidance package.

**Released:** website `62dab2226af5fc31ce821bc21827f09680f12bea` is production
READY as `dpl_HpzZQDJB1D6zBbQfuLK45xL6GLDN`, aliased to `regencommons.com`.
Live About, membership HTML and shared CSS bytes match the tested source. Live
in-app Chromium checks confirm the shared card and fields at desktop/mobile
widths, with no horizontal overflow or console errors. The release’s runtime
error/fatal scan was empty. No new live contact message was submitted; the
previous contact delivery verification remains the integration evidence.
Rollback target: `dpl_M7scijv6VWicdTpBhTToAtfz4ehj`. The published task branch
remains separate from main; no PR or CI run exists for this revision.


## Public form consistency and centered contact — 11 November 2026

- Feedback uses the membership card, display labels, checkbox grid, textarea,
  hints and organic button, while keeping category selection and page context.
- Both seed entry points use the membership textarea and organic button. Keep
  their existing card colors/layouts and inherit control text from each card.
- Center the About contact card, heading and introduction; keep field text left
  aligned. Respect reduced motion for organic buttons and seed card pulsing.
- Verify desktop/mobile, both themes, keyboard validation, error/retry and save
  feedback with synthetic fixtures. Run check, tests and smoke before releasing.
- Deploy the verified website revision, compare live assets and inspect the
  rendered public forms. Live submissions are unnecessary for this visual change.

**Rendered fixture evidence:** in-app Chromium at 1280px and 390px covers all
four affected pages in both themes, shared 16px textarea controls, organic
buttons, card palettes, no horizontal overflow, keyboard checkbox selection,
required-field focus, and contact-card centering (zero-pixel center offset).
Feedback and Seeds retain drafts through a forced failed save and succeed on
retry. Mobile Learn saves by keyboard and hands off to the planted-seed screen.
Console checks are clean. The browser reports no reduced-motion preference;
CSSOM inspection confirms animation removal for buttons and seed cards under
that media query, rather than claiming a rendered reduced-motion check.

Local guidance tooling still cannot resolve its dev-surfaces module; this uses
repository styles and native controls without refreshing the online package.
Final check, all 88 tests and HTTP smoke pass.

**Released:** website `d29d7e1927a140f36aaea3237e16f3fb49cb4fa2` is production
READY as `dpl_7kMCaa2itHbKwKzKGtPkEW3Kcn2x`, aliased to `regencommons.com`.
All seven changed HTML/JS/CSS assets match the tested source byte for byte.
Live in-app Chromium confirms Feedback’s shared controls, both seed cards with
organic buttons, and the centered contact card at desktop/mobile widths with
zero center offset and no horizontal overflow. Live console and runtime
error/fatal scans are empty. No live submissions were made for this visual
release; save/retry checks used isolated synthetic fixtures.

Rollback target: `dpl_HpzZQDJB1D6zBbQfuLK45xL6GLDN`. This release remains on
`codex/about-contact`; main is unchanged. No PR or CI run exists for this revision.

## Contact composition and membership navigation — 11 November 2026

Move Get in touch and its introduction inside the centered contact card. Keep
field text left aligned and place Send message at the right edge of the card’s
content. Move Become a member into the Members governance card as a text link.
Remove the separate membership button below Contact.

Fix the membership navigation’s vertical alignment. Before the fix, the shared
button’s 2.2rem top margin placed Continue’s center 19.8px below Back even though
the row used align-items: center. Override that margin within navigation rows;
verify Back/Continue and Back/Submit centers at desktop/mobile widths.

Acceptance: heading/card association, one membership CTA in the intended card,
right-aligned contact action, centered membership navigation, both themes,
keyboard navigation and validation, no horizontal overflow, required checks,
and verified production publication.

**Rendered fixture evidence:** in-app Chromium at 1280px and 390px confirms
heading/introduction inside the contact card, zero center offset for that card,
and zero offset between Send message’s right edge and the textarea’s right edge.
There is one Become a member link, inside Members; it opens `/join`. The separate
CTA below Contact is gone. Both themes, keyboard focus, required-field rejection
and horizontal overflow checks pass; console checks are clean.

Membership Back/Continue and Back/Submit now have zero vertical center offset
at desktop/mobile widths. Back remains on one line; mobile navigation uses
smaller side padding and tracking so Submit application fits beside it at 390px.
Synthetic navigation through all six steps and back/forward recovery pass.
Local guidance retrieval remains unavailable because the dev-surfaces module is
missing; no online guidance package was refreshed. The 320px navigation check
also has zero center offset and no horizontal overflow. Final check, all 88 tests
and HTTP smoke pass.

**Released:** website `7aed67197544f15e505a78fc7a924aee97037784` is production
READY as `dpl_EsLh55P3iBxeitAMqHnY5MuYTsiq`, aliased to `regencommons.com`.
Hosted About, shared CSS and membership HTML match the tested source byte for
byte. Live desktop/mobile checks confirm the contact heading inside the card,
zero card-center/right-action offsets, one membership link in Members and no
membership link in Contact. That link opens the live application, whose visible
Continue button has zero top margin. Six-step navigation/alignment proof uses
synthetic fixtures. Console and runtime error/fatal scans are empty. No live
submissions were made for this layout release.

Rollback target: `dpl_7kMCaa2itHbKwKzKGtPkEW3Kcn2x`. The release remains on
`codex/about-contact`; main is unchanged. No PR or CI run exists for this revision.

## About origins — 11 November 2026

Add a short origins section immediately before the steward council. Describe the
2025 shared-identity invitation, July–September participatory design process,
and connection to the present foundation period. Use the existing prose-section
layout. Avoid a precise founding day or turning proposed legal/funding structures
into completed events; use organizational credits rather than private reflections
or individual attribution.

Source basis checked through connected Drive and public primary material:

- [Early ETHDenver invitation](https://docs.google.com/document/d/1sPE3LtLtSPrSODFFQUaPHeoP8bGXvlACLyZC4Vi1bEg/edit):
  documents the 2025 invitation and shared identity/IP commons purpose; its
  prospective partnerships, legal structures and funding asks are not outcomes.
- [Governance Activation Public Summary](https://drive.google.com/file/d/1fSNrk_kckPUnTCOpgly8Ot4puYH7slnR/view):
  labeled Public; records July–September 2025, OpenCivics Labs/Greater Than
  facilitation, workshops/feedback and constitutional work. The archive’s 2026
  import/edit metadata does not date these events. Its legal-status and funding
  assertions are not used.
- [OpenCivics June 2025 report](https://broadcast.opencivics.co/p/opencivics-monthly-report-june-2025):
  public contemporary corroboration that OpenCivics Labs and Greater Than were
  preparing to co-lead the process. It does not establish later outcomes alone.

The current foundation-period language matches the existing About page. Private
coordination notes and raw retrieved files are not copied into this repository.
**Verification:** source-to-copy review confirms the invitation/design chronology
and organizational credits; the exact founding day remains unspecified. In-app
Chromium at 1280px and 390px confirms readable prose in both themes, no horizontal
overflow, and the heading order Intro → Our origins → The steward council →
Governance → Contact. Origins immediately precedes the council in the document
and accessibility tree. Console checks are clean. Check, all 88 tests and HTTP
smoke pass. No new interactions, provider operations or dependencies were added.
**Released:** website `03e80134ed3a60e5fa924c67497138531a554028` is production
READY as `dpl_HPCcJDbCBqssFqTRwEVWz1Nsu6eS`, aliased to `regencommons.com`.
The hosted About page matches the tested source byte for byte. Live in-app
Chromium at 1280px and 390px confirms the three paragraphs and placement before
the council, with no horizontal overflow or console errors. Runtime error/fatal
scan is empty. No provider writes or live submissions were needed.

Rollback target: `dpl_EsLh55P3iBxeitAMqHnY5MuYTsiq`. The task branch remains
`codex/about-contact`; main is unchanged. No PR or CI run exists for this revision.

## About origins links — 11 November 2026

Link OpenCivics Labs to its official homepage (`www.opencivics.co`), which lists
Labs, and Greater Than to `greaterthan.works`, which redirects to the collective’s
legacy site. Both destinations return HTTP 200 after redirects. Link the three
prose mentions of the constitution on About to the existing `/constitution`
route (also HTTP 200). Reuse About’s theme-aware inline link treatment and native
keyboard focus. Desktop (1280px) and mobile (390px) rendering are verified in
light/dark themes, with no horizontal overflow or browser warnings/errors.
Keyboard focus moves through the partner links to the constitution, which opens
the correct page. `npm run check`, all 88 tests, and `npm run smoke` pass.
Production delivery is complete: runtime commit
`ee4727928f9759ed239602cb3a35dd282bd47bc3` is READY on Vercel deployment
`dpl_E6TmrMZXZ9htQyVik9Gjnm6igsQh`, aliased to `regencommons.com`.
The live About HTML matches the committed file byte-for-byte. Live desktop and
390px mobile checks confirm the partner links are underlined and there is no
horizontal overflow; all four constitution links (three prose and one card) are
present. The origins constitution link opens the live constitution page. Browser
warnings/errors are empty. No live submissions or provider data writes were needed.

Rollback target: `dpl_HPCcJDbCBqssFqTRwEVWz1Nsu6eS`. The task branch remains
`codex/about-contact`; main is unchanged. No CI run exists for this revision.

## About organization links in new tabs — 11 November 2026

OpenCivics Labs and Greater Than in Origins should open in new tabs. Inspection
also found that council organization links still used the same tab, unlike the
LinkedIn links. Apply native `target="_blank"`, `rel="noopener"` and an accessible
new-tab label to both sets (13 links total), keeping constitution links internal.
Rendered fixture proof confirms OpenCivics opens a separate tab with Enter and
Greater Than opens a separate tab on click, with About preserved. Both destinations
load successfully. All 13 links expose new-tab labels and `noopener`; all four
constitution links retain same-tab navigation. Desktop (1280px) and mobile (390px)
render correctly, with no mobile overflow or browser warnings/errors. Required
`npm run check`, all 88 tests, and `npm run smoke` pass. Local modern-web guidance
retrieval remains unavailable due to the missing dev-surfaces entrypoint; this
uses existing native anchor conventions.

Production is READY at `regencommons.com`, deployment
`dpl_2LwvsV6oBGELeL65SmLbv81J1AfH`, runtime commit
`59b561a33a3b2dcec548307b2441cefa8ef9f5fd`. Live keyboard/click activation
opens OpenCivics and Greater Than in separate tabs with correct destination titles,
while the original About tab remains open. The live HTML matches the released file
byte-for-byte. Browser warnings/errors and deployment error/fatal logs are empty.
Rollback target: `dpl_E6TmrMZXZ9htQyVik9Gjnm6igsQh`. No CI run exists for this
revision; local required checks passed. Branch is `codex/about-contact`; main is
unchanged.

## Contact forum link in a new tab — 11 November 2026

Make the Regen Commons forum link inside Get in touch open in a new tab using
native `target="_blank"`, `rel="noopener"` and an accessible new-tab label,
matching the other external About links. Verify keyboard activation, the loaded
forum destination and preservation of the About page, rendered desktop/mobile
layout, required checks and production delivery.

Rendered fixture checks at 1280px and 390px confirm correct contact text wrapping
and no mobile overflow. Enter opens a separate tab with the correct forum category
and About preserved. The link has `noopener` and the accessible new-tab label.
Browser warnings/errors are empty. `npm run check`, all 88 tests and
`npm run smoke` pass. Production delivery is pending.
