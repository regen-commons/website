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
is implemented on `codex/steward-dashboard`. Its schema and PostgreSQL access
tests ran against Regen Commons / Website. Local auth and review flows use
synthetic fixtures. Live Auth SMTP/code templates, named steward provisioning,
and delivery remain unverified; no public provider cutover has occurred.

**Next boundary:** establish real steward login in an authorized test environment,
then agree acceptance/publication authority and migration scope. The remaining
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

## 3. Make application and notification failures observable

**Scope:** `api/apply.js`, `api/seeds.js`, `api/_lib/notify.js`, provider-boundary tests.

**Done when:** handle Resend's fulfilled `{ error }` results; bound notification
timeouts; distinguish a saved application with failed notifications from a failed
save; remove claims that fallback capture cannot lose data. Verify 429/5xx retry,
schema rejection, all capture channels unavailable, and duplicate/repeated submits.
Choose a recoverable capture/idempotency strategy with clear data retention.

**Decision:** who may receive raw application answers on recovery, and whether
Telegram is an appropriate destination for those private fields. Do not expand
recipients or data sharing as an incidental implementation detail.

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
