# Repository adapter: Regen Commons site

The kit skills (review, debug, plan, ship, research) read their own section here plus `## checks`. Field names follow the kit's `adapters/TEMPLATE.md`. Where a field points to a repository file, that file owns the rule: follow it when it and this summary differ.

## checks

### Guide
`AGENTS.md` § Workflow and § Rules and their enforcers, then the scoped guide for the surface: `admin/AGENTS.md`, `api/AGENTS.md`, `supabase/AGENTS.md`. `docs/development.md` owns the commands, the fixture server and the dev machine.

### Base
The live PR base when one exists, otherwise `origin/main`. Fetch it before computing the change set. `main` is both the integration branch and production: every merge into it deploys the site and its API through Vercel. `develop` is stale since 30 October; never use it as a base.

### Command rules
- Run everything from the repository root with npm scripts (`npm run check`, `npm test`, `npm run smoke`, `npm run dev`). Use npm and `package-lock.json` for dependencies; `bun run dev` is only an alternative launcher.
- On the maintainer's Mac, `node`, `npm` and `npx` run inside the `regen-commons-site` dev machine (`docs/development.md` § The dev machine). Do not override `PATH` or call a runtime by its full path. The machine drops a `PORT=` prefix, so choose another fixture port in-process when 3501 is taken.
- The dev machine shares one 8 GB VM with other repositories. The SQL suites and browser runs belong in CI; locally run one heavy step at a time, check `uptime` first, and wait while the one-minute load is above 12.
- Never run `vercel deploy`, `supabase db push` or `supabase migration repair`: those are afo's (`.agents/policy.json`). Never send a request to the live site or its data; prove behavior against fixtures.

### Selector
none. Choose tiers by hand from **Tiers**, then add every row of **Conditional checks** whose surface the change touches.

### Tiers
| Tier | Use | Command |
|---|---|---|
| targeted | the smallest proof of one changed behavior | `node --test tests/<name>.test.js` |
| style | non-mutating static checks: JavaScript and inline scripts parse, local links and share images resolve, JSON parses (no formatter or linter yet) | `npm run check` |
| checkpoint | a coherent cross-surface batch or shared-contract change | `npm run check && npm test` |
| push | ready-for-CI gate on the committed tree before a push | `npm run check && npm test && npm run smoke` |
| readiness | explicit production-readiness review; non-mutating full local gate | the push tier, plus CI's `database` job green at the head SHA, plus rendered proof for UI changes |
| full | explicit full local gate | the readiness tier |
| release | release gate | none: a merge into `main` is the production release. Critical changes wait for afo's go before merging (**Criticality**) |

### Conditional checks
- Handler, provider adapter or fixture → `node --test tests/<surface>.test.js` for the owning suite, and `npm run smoke`.
- `supabase/migrations/**` or `supabase/tests/**` → CI `database` (applies every migration to a disposable Postgres and runs the SQL suites). It cannot run on the dev machine, which has no Postgres.
- Page, `script.js`, `style.css` or `admin/**` → rendered proof per **Rendered proof**.
- Agent guidance, skills or `.agents/**` → `dev agents doctor regen-commons-site` (reads `origin/main`) or `node ~/Code/dev-surfaces/agents/kit/doctor/agents-doctor.mjs <worktree>`, plus CI `agents-doctor / Agents doctor`.
- A production claim → afo's deployed evidence; never inferred from fixture tests.

### Criticality
`.agents/merge-policy.json` owns the tiers and their paths.
- Critical: the API handlers, intake and steward data modules and the root contracts, `supabase/migrations/**`, `supabase/tests/**`, `vercel.json`, `package.json`, `package-lock.json`, `.nvmrc`, `.github/workflows/**`, `.agents/merge-policy.json`, `.github/CODEOWNERS`. Merge on the full gate plus a fresh agent's adversarial review naming the head SHA, then wait for afo's go, because the merge is the production release.
- Sensitive: `admin/**`, `council.html`, the intake pages and form scripts, the notification modules, email templates, the fixture server and providers, `tests/**`, `scripts/check.js`, `scripts/smoke.js`, the Notion import scripts, and agent guidance (`AGENTS.md`, `*/AGENTS.md`, `.agents/adapter.md`, `.agents/policy.json`, `.agents/skills/**`). Merge on the required checks plus that review.
- Routine: everything else. Merge on the required checks and a targeted check.

### CI
GitHub Actions, `.github/workflows/ci.yml`. Required at the PR's current head SHA: `.agents/merge-policy.json` `requiredChecks`. CI owns the SQL suites, the Notion import replay and the doctor; a local run never stands in for pending CI.

### Rendered proof
Use the fixture server (`npm run dev`, synthetic data, a **Local demo** banner). Label each capture with browser, viewport (375 and 1280 wide) and color scheme, and as rendered local fixtures. `/council` signs in as `steward@example.test` with code `123456`. Fixtures do not prove Vercel routing, email delivery, Telegram delivery or hosted auth; record those as pending.

## review

### Scopes
`pages` → `*.html`, `script.js`, `style.css`, `*.css`, `canvas.js`, `logo-canvas.js`, `*-form.js`; `admin` → `admin/**`, `council.html`; `api` → `api/**`, `*-contract.js`; `database` → `supabase/**`; `tooling` → `scripts/**`, `tests/**`, `.github/**`; `docs` → `docs/**`, `README.md`; `guidance` → `AGENTS.md`, `CLAUDE.md`, `*/AGENTS.md`, `.agents/**`, `.claude/**`.

### Special scopes
none beyond the skill's `--scope cross-package`, which here checks the browser caller, handler, provider adapter, fixture and SQL policy of one contract together.

### Dependency order
`supabase/migrations` → `api/_lib` and root contracts → `api/*.js` handlers → pages and `admin/`.

### Requirement sources
- The PR description and any issue it links.
- `docs/work-plan.md` for open tasks and acceptance criteria.
- The owning doc in `docs/` (`content-management.md`, `integrations.md`, `steward-dashboard.md`, `membership-management.md`, `weave-accounts.md`).

### Invariants
`AGENTS.md` and the scoped guides keep the durable list. Check every diff for:
- provider SDKs and credentials stay on the server; local fixtures never fall through to a live provider;
- steward reads verify the user and current steward role on every request, scoped to the user's token so row-level security applies; never a service-role client;
- a linked profile is not acceptance, and acceptance is not publication;
- application answers, contact details and review history stay private; public reads use explicit projections;
- applied migrations are never edited; exposed tables keep row-level security and least-privilege grants;
- submitted text renders as text; provider calls have a timeout; logs carry no raw provider bodies or personal data.

### Quality bar
`AGENTS.md` and the shared pragmatic-programming rules in `~/.agents/AGENTS.md` where present.

### Architecture guide
none.

### State lens
Triggers: membership review and decisions, profile publication, intake idempotency and quotas, notification leases and delivery outcomes, steward sessions. Matrix: none; build it from the migration and its SQL suite in `supabase/tests/`.

### Critical lenses
- Migrations and SQL suites → schema and authorization lens: forward-only, row-level security on exposed tables, grants and function privileges reviewed together, a SQL suite that proves denial.
- Intake handlers and contracts → abuse lens: body limits, validation, idempotency, rate limits, no private data in responses or logs.
- Steward auth and data → authorization lens: token-scoped calls, role and session checks, same-origin POST, no-store caching.
- `vercel.json`, `package.json`, the lockfile, workflows → deploy and supply-chain lens: what production serves, pinned actions, stable required check names.

### Judgment routing
Separate findings into Agent-Fix-Now (mechanical or local with an obvious safe fix) and Human-Judge (dependencies, auth, row-level security, migrations, destructive operations, deploy behavior, publication rules). Human-Judge items go under Human Call-Outs and are never auto-resolved.

### Test budget
none.

### Deep pass
The harness's built-in `/code-review`; say so and use it rather than hand-rolling depth.

### Gap shapes
- A handler change without its fixture provider and test update.
- A new table or column in an exposed schema without its SQL suite assertions.
- A touched page missing a state: loading, empty, error, retry, rate-limited, reduced motion, keyboard, mobile.
- A command, path or provider renamed without updating `AGENTS.md`, `README.md`, `docs/development.md` or the skills.

### Not findings
Fixture-only proof labeled as fixture proof is expected; only presenting it as live delivery is a finding.

### Immutable records
`supabase/migrations/**` once applied.

### Tracker
GitHub issues on `regen-commons/website`; ask before creating anything.

## debug

### Context
`AGENTS.md`, `admin/AGENTS.md`, `api/AGENTS.md`, `supabase/AGENTS.md`, `docs/development.md`, `docs/integrations.md`.

### Reporters
Stewards using `/council`, applicants and site visitors, Weave operators.

### Safety
Never reproduce against the live site, its Supabase project or its providers. Never run `vercel deploy`, `supabase db push` or `supabase migration repair`. Reproduce on the fixture server and `/__dev/scenarios`.

### Real surface
The fixture server at `http://127.0.0.1:3501` with synthetic data; `/council` as `steward@example.test`, code `123456`.

### Layers
Triage: page script → `/api` handler → `api/_lib` provider → Supabase policies and functions. Data: fixture store (`scripts/lib/`), migrations, SQL suites. Extra evidence: the fixture scenario in force, the handler's stable error code.

### Data path
Page form → `*-contract.js` validation → `api/<handler>.js` → `api/_lib/public-data.js` or `steward-data.js` → Supabase tables and policies → notifications (`intake-notifications.js`, `contact-notifications.js`).

### Environment truth
Which provider produced a result (fixture or hosted), whether a migration is only a local file or applied, and the fixture scenario selected at `/__dev/scenarios`.

### Boundary probes
Handlers: `curl http://127.0.0.1:3501/api/<handler>` against the fixture server. Database: the SQL suites in `supabase/tests/` through CI's `database` job.

### Known errors
`listen EPERM` in an agent sandbox and `[dev-machine] not run` → `docs/development.md` § Troubleshooting.

### UI gotchas
Browser scripts are classic scripts, including inline blocks; map logic lives inline in `map.html`. A UI action often spans the page's inline script and `script.js`.

### Known symptoms
| Symptom | Likely cause | Diagnostic |
|---|---|---|
| HTTP 429 locally | the real handler's rate limit | restart the fixture server |
| Map empty locally | `empty` or `offline` scenario left on | `/__dev/scenarios`, set to `normal` |

### Evidence map
Handlers → `api/`; providers → `api/_lib/`; fixtures → `scripts/lib/`; schema → `supabase/migrations/`; SQL proofs → `supabase/tests/`; local server → `scripts/dev.js`.

### Telemetry
none available to agents.

### Known-failure notes
`docs/development.md` § Troubleshooting.

### Slices
none.

### Tracker
GitHub issues stay read-only during debugging unless the user asks to file or update.

## plan

### Context
`AGENTS.md`, `README.md`, `docs/development.md`, `docs/work-plan.md`.

### Quality bar
`AGENTS.md`.

### Priorities
privacy and authorization → applicants' and stewards' data integrity → public site usability → speed of change.

### Design sections
Privacy: which fields leave the server and through which projection.

### Architecture guide
none.

### Seam registry
none.

### Plan location
`docs/work-plan.md` holds open tasks; no plan hubs.

### Plan files
none beyond `docs/work-plan.md`.

### Lanes and proof
none.

### Dependency order
migration → `api/_lib` provider and fixture → handler → page or `admin/`.

### Always-separate
A Platform migration copy from Weave and website code ship in separate pull requests.

### Plan triggers
A migration, a row-level security or grant change, a new public field, or a change to intake or steward auth.

### Start gate
none.

### Tracker mirror
none.

### Closeout
Update or remove the task in `docs/work-plan.md`.

### Lifecycle
none.

### Templates
none.

### Teams
none.

## ship

### Branch check
none; branches are short names or `<agent>/<slug>`, cut from `origin/main` after a fetch.

### Protected branches
`main` and `develop` (ruleset "Protect main and develop": pull requests only, required checks, resolved review threads).

### PR issue line
none.

### Hooks
none.

### Commit format
Conventional subject (`feat(site): ...`, `fix(api): ...`, `chore(ci): ...`). Signed commits; end with the co-author trailer and the `Agent-Model:` line from `~/.agents/evals/bin/agent-model` when it prints one.

### Push gate
none locally; CI is the gate.

### PR
`.github/pull_request_template.md` (Why, Measured, Verification, Not verified). Verification names the merge tier from `.agents/merge-policy.json` and the proof that tier needs. The repository is public: no real applicant data, contact details or private captures in a PR.

### Merge
`.agents/merge-policy.json`: merge commits only, auto-merge off. An agent merges routine and sensitive changes itself once their proof holds (afo's standing decision of 21 November 2026, which is the authorization the ship skill asks for); a critical change waits for afo's go in the session. Merge by hand on the reviewed head with `gh pr merge <n> --repo regen-commons/website --merge --match-head-commit <sha>`, never squash or rebase, even where GitHub still allows them.

### After merge
Vercel deploys `main` to production. afo checks the deployment; agents send no request to the live site.

### Report line
The PR URL with its state read from GitHub.

### Unattended
Draft PRs only, routine paths only, at most ten files.

## research

### Plan entry point
`docs/work-plan.md`.

### Neighbor skills
Page and handler implementation → `site-development`.

### Durable evidence
Under `docs/` in the owning guide; never a new report file at the repository root.

### Mapping workflow
none.

### Tracker
GitHub issues; no writes without a separate request.
