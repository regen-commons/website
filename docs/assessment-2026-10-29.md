# Website assessment — 29 October 2026

The website has a manageable foundation for incremental development: five static
pages, shared JavaScript/CSS, and four small Vercel handlers. Keep this architecture.
The immediate need is a reliable development and review workflow, followed by
clear persistence/error feedback and verified ownership of the live integrations.

## Evidence and scope

Reviewed the clean checkout at `1bceed1`, all API handlers/provider helpers,
browser call sites, package configuration, administrative script entrypoints, and the supplied
`Archive/Regen Commons Handover.html` (dated 24 September 2026). Compared local
Green Goods `AGENTS.md`, README, package scripts, skill layout, and dev-surface
manifest, plus the shared Dev Workbench documentation. Read the locally installed
Modern Web Guidance forms guide for browser review.

The archive was treated as historical evidence. Its migration checklist did not
authorize migrations or service changes. No live account dashboard, Notion data,
production form, or Telegram agent was accessed. Claims about domain/account
ownership and branch protection remain unverified. No credentials were copied
from the archive or pulled from Vercel.

## Findings

| Priority | Finding and consequence | Evidence / next action |
|---|---|---|
| P1, addressed locally | Initial `dev` relied on an unpinned Vercel CLI absent from the dependency manifest and live credentials. There were no checks, tests, or CI. | Added a repo-native fixture server, Node 22 selection, seven behavior tests, smoke, and CI. Live CLI setup remains separate. |
| P1 | Seed planting can appear successful after a failed save. The client only catches rejected fetches, ignores HTTP errors, and accepts 1–2 characters that the API rejects. | `script.js` seed click handler; `api/seeds.js` minimum length. First product fix in the work plan. |
| P1 | Application recovery is best effort, not guaranteed capture. Optional channels may all be disabled; fulfilled Resend results containing `error` are not detected. | `api/apply.js` capture and notification paths; installed Resend SDK returns `{ data, error }`. Add delivery/failure tests before relying on recovery. |
| P1 | Live schema/account ownership is not established. The archive says Members was adapted from OpenCivics. Existing administration scripts can alter that database. | Confirm ownership and establish dedicated development targets before live setup or migration. |
| P2, docs corrected | README/HANDOFF schemas and publication filters were stale, webhook variables were missing, and an unused `SITE_URL` was documented as required. | Current handlers use `Org/Individual Name`, exact `Active` filters, and notification env variables. See integration notes. |
| P2 | Map/API failures leave the graph/library empty without explaining whether there is no data or a failed request. The documented demo fallback is absent. | `map.html` starts with empty node data and clears library content on failure. Add loading/empty/error states. |
| P2 | Contributor names bypass the Members publication filter. A contribution can reference a pending/archived member and still expose their name. | `api/contributions.js` retrieves related pages without checking status. Confirm the intended publication rule. |
| P2 | Rate limits live in process memory, and Telegram requests have no explicit timeout. They are not durable across serverless instances/deployments. | Both write handlers and `api/_lib/notify.js`. Add bounded provider calls and decide whether abuse volume warrants a shared limiter. |
| P2 | Browser accessibility and motion need focused work. The graph is canvas/hover based; no `prefers-reduced-motion` handling was found in the shared CSS/animation code. | Verify keyboard/screen-reader equivalents, form grouping/error focus, and reduced motion before a visual refactor. |

There are useful existing protections: public member projection omits contact
fields, read handlers paginate, requests have method checks, write handlers have
honeypots, applications begin Pending, and rendered contribution text is escaped.
This is a focused engineering assessment, not a complete security or accessibility audit.

## What to borrow from Green Goods

| Useful pattern | Proportionate application here |
|---|---|
| Root agent guide with conditional routing | One concise `AGENTS.md`, a `CLAUDE.md` import, and one linked site-development skill |
| Repo owns local runtime | One foreground entrypoint, explicit port, credential-free fixtures, clear cleanup |
| Separate onboarding, contracts, and work plans | Development guide, integration reference, and ordered tasks with acceptance criteria |
| Proof names the environment | Distinguish fixture HTTP, rendered local browser, and live-provider checks |
| Checks run locally and in CI | Syntax/link checks, behavior tests, and smoke using the same commands |

Green Goods' monorepo, wallet/chain infrastructure, broad validation selector,
and numerous skills are not needed here. Its installed repository guidance also
differs from older shared workbench descriptions in places; copy the ownership
principles rather than importing those commands or historical assumptions.

## Bootstrap delivered

- Kept production page/API implementation unchanged; added local tooling under
  `scripts/` that replaces provider transport before importing actual handlers.
- Preserved npm and the existing locked dependency versions. Selected Node 22 in
  `.nvmrc` and `package.json`; this also pins the major for a future Vercel deploy.
  Node 22 is listed in [Vercel's supported runtimes](https://vercel.com/docs/functions/runtimes/node-js/node-js-versions).
- Added fixture isolation, explicit public-file serving, local mode labeling,
  bounded JSON bodies, method handling, and port conflict reporting.
- Added agent guidance, one repository skill, maintained setup/integration docs,
  CI, a validation-focused PR template, and a broader env-file ignore rule.
- Replaced the misleading historical handoff with pointers to maintained docs;
  the old document remains in Git history.

## Verification record

- `npm ci` succeeded on local Node 22.22.1; 46 packages installed from the existing lockfile.
- `npm run check` passed: 35 JavaScript files/inline scripts, local page links,
  and JSON configuration. This is a syntax/link check, not a full linter.
- `npm test` passed: seven behavior tests covering fixture isolation, port conflicts, public/private
  routing, publication/privacy projection, malformed/oversized requests, seed
  readback, application validation, and rate limiting.
- `npm run smoke` passed: all five pages and assets, three API reads, a seed
  write/readback, and exclusion of a new pending application from public members.
- `bun run dev` started the same native server on `127.0.0.1:3501`.
- Rendered proof: Codex in-app browser, local fixtures. Home and map rendered;
  the synthetic library card and contributor appeared. Completed all six join
  steps at 390 × 844 and reached “Thank you for submitting.” No warning/error
  console entries were returned during those checks. A local screenshot is saved
  under ignored `artifacts/local-join-mobile.png`. Learn and Seeds also rendered;
  a synthetic seed reached the planted state and was confirmed through the local API.
- The site-development skill passed the bundled skill validator.
- Relative Markdown links and `git diff --check` passed. The shared `dev check`
  failed on pre-existing global registry drift (including old Coop/TAS-Hub paths)
  and checks expecting guidance/scripts absent from other projects. Regen Commons
  is not registered there; its native checks pass. The global registry was not changed.

Machine limitations encountered: the default Node/npm/Bun shims attempted to
enter an unavailable VM. An existing local Node installation resolved this without
changing global settings. Package downloads and loopback listeners required the
agent harness's bounded permission mechanism; no permission policy was weakened.
The installed dependency tree emits a `punycode` deprecation warning under Node 22.

Not established: live Notion schema compatibility, email/Telegram delivery,
Vercel emulator/deployment parity, custom-domain status, GitHub protection/CI
execution, complete mobile/keyboard/accessibility coverage, or performance budgets.
The default local loop works; these limits prevent a claim of production readiness.
