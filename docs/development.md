# Local development

Use the fixture environment for everyday coding. It runs the real API handlers
with synthetic Notion pages and in-memory writes. There are no external API
calls from this server, even when the shell contains live provider credentials.
The browser still requests Google Fonts; system font fallbacks work without them.

## First run

Install Node 22 (also selected by `.nvmrc`) and use the npm shipped with it:

```sh
node --version
npm ci
npm run dev
```

Open http://127.0.0.1:3501. The home, learn, map, seeds, and join pages are
available with both `.html` and extensionless paths. A bottom banner says
**Local demo**. `/__dev/health` reports fixture mode and no external writes.

No `.env` copy is needed. Local startup ignores env files and replaces inherited
Notion/notification settings in its own process before importing the handlers.
Nothing is written back to your environment files. The fixture adapter is loaded
only by local tooling; production handlers do not import it.

The map has two synthetic active members and a contribution. A pending fixture
member is excluded. A new application succeeds locally but stays off the public
map. A new seed appears in `/api/seeds`. All submitted data disappears on restart.
Use `example.test` addresses and invented content.

The `/admin` dashboard has a separate synthetic steward provider. Request a code
for `steward@example.test`, then enter `123456`; no mail is sent. Its applications
and curated profiles are independent of the public Notion fixtures. See
[steward setup](steward-dashboard.md) for access-denial examples, the actual
Supabase migration status, and the unverified live-email prerequisites.

Refresh for HTML/CSS/browser-JS edits. Restart for API or tooling changes. Ctrl-C
stops the process. `bun run dev` is an equivalent launcher; npm remains the
dependency manager so there is one lockfile.

## Checks

| Command | Evidence |
|---|---|
| `npm run check` | JS/inline-script syntax, local page link targets, JSON parsing |
| `npm test` | HTTP behavior, credential isolation, public data filtering, validation, body limits, rate limiting, seed/save and list state transitions |
| `npm run smoke` | Six pages/assets, public API reads/writes, pending application exclusion, steward sign-in and authorized queue |

The tests and smoke command create temporary loopback servers and close them.
They do not need the dev server or credentials. CI uses these same commands on
Node 22. No build step is needed for the static frontend; these commands do not
prove a Vercel deployment. The fixture store is process-local; keep HTTP tests in
one serial suite or launch a fresh process for independent scenarios.

For browser changes, inspect desktop and mobile layouts, the browser console,
keyboard navigation, and success/failure states. The initial browser record is
in the [assessment](assessment-2026-10-29.md). Full accessibility, visual
regression, and live-provider testing remain separate work. The seed/map
[verification record](local-flow-verification.md) includes the current browser
results and steps to reproduce failures.

## Reproduce loading and failure states

Open http://127.0.0.1:3501/__dev/scenarios while the local server is running.
Choose a scenario, then reload the map or submit an invented seed in another tab.
The selection affects all tabs using that server; return it to **normal** when
finished. Restarting also restores normal mode and clears in-memory submissions.

| Scenario | Local behavior |
|---|---|
| `normal` | Real handlers with the synthetic Notion adapter |
| `empty` | Empty members and contributions lists |
| `error-once` | First call to each API/method returns 503; retry uses the handler |
| `offline` | API connections close without a response until reset to normal |
| `rate-limit-once` | First seed POST returns 429; later calls use the handler |
| `slow` | API responses are delayed six seconds |

These controls are implemented only in local tooling. They neither call nor
reconfigure providers. A browser may retry a dropped connection internally, so
`offline` keeps dropping connections until explicitly reset. The real handler's
own rate limits still apply after a synthetic failure is cleared.

## Troubleshooting

- **Port occupied:** the server refuses to replace the occupant. Reuse the
  existing instance or run `PORT=3503 npm run dev`. Stop only your own process.
- **HTTP 429:** the actual handlers limit applications to three attempts/hour
  and seeds to six; invalid attempts also consume quota. Restart local dev to reset.
- **Dependency import fails:** run `npm ci` from the repository root. Preserve
  the lockfile. The inherited v1 lockfile may make npm fetch supplemental metadata.
- **`listen EPERM` inside an agent sandbox:** allow the bounded command to bind
  loopback using the harness permission flow. Do not alter repository/global
  sandbox policy.
- **Node routes into an unavailable VM:** on the machine assessed on 29 October
  2026, `node`, `npm`, and `bun` on PATH were dev-machine wrappers. For that
  machine, this session-local override uses an existing local runtime:

  ```sh
  export PATH=/Users/afo/.local/share/mise/installs/node/22.22.1/bin:/Users/afo/.bun/bin:$PATH
  node --version
  npm run dev
  ```

  Other contributors should select their own Node 22 installation. No global
  runtime or Codex configuration changes are needed.

## Live integration workflow

`npm run dev:live` reserves port 3502 for Vercel's emulator. It requires a
separately installed Vercel CLI, an authorized project link, and development
credentials. It is **not** covered by the credential-free quick start or verified
by fixture tests. The CLI is not yet pinned; making this lane reproducible is
tracked in [work plan](work-plan.md).

Before using it, confirm the intended Vercel project and Framework/Development
Command settings: it must serve the static pages and actual Vercel functions,
not start `npm run dev` and its fixture server. Use separate development Notion
databases and notification destinations. Pull only the authorized environment
into ignored `.env.local`; never overwrite an existing file without inspecting
whether it needs to be preserved. See [Vercel's dev documentation](https://vercel.com/docs/cli/dev).

Live form submissions can create real Notion pages, send email, and notify the
Telegram agent. Require the user's authorization for those destinations and test
data before submitting. Account setup and production deployment were not part of
this bootstrap.

The shared Dev Workbench was inspected as a reference. This repository is not
registered there yet, so use its native entrypoint. Port 3501 is outside the
existing 3001–3404 project blocks. Global registration can be added separately;
the repo must remain runnable without that workbench. The shared `dev check`
currently reports stale project paths and guidance expectations in other repos;
those need reconciliation before claiming workbench-wide readiness.
