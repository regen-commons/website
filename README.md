# Regen Commons website

Five public HTML pages and a separate `/admin` steward dashboard, with Vercel
functions for data access. Public intake, the commons library, and shared visions
still use Notion. The read-only steward pilot uses Supabase PostgreSQL and Auth.
Optional public-intake notifications use Resend and the separate Telegram agent.

## Start locally

Use Node 22 and npm, from this directory:

```sh
npm ci
npm run dev
```

Open **http://127.0.0.1:3501**. No credentials, Vercel login, database, or Docker
are needed. The pages use synthetic members, contributions, and seeds. Submitted
seeds and applications stay in memory until you restart; they never send email
or Telegram notifications. A banner identifies this local demo.

`bun run dev` also runs the same entrypoint when Node 22 is on your PATH. Keep
`package-lock.json` as the dependency authority and use npm for dependency changes.
Refresh the browser after frontend edits; restart after API or tooling edits.
Ctrl-C stops the server. See [local development](docs/development.md) for port
conflicts, the machine-specific Node workaround, and the separate live workflow.

## Verify a change

```sh
npm run check
npm test
npm run smoke
```

These check JavaScript (including inline page scripts), local page links, and
actual API handlers over local HTTP with a fixture Notion transport. Smoke
starts and stops its own temporary server. There is no frontend compilation step.
CI runs the same commands without secrets. Browser behavior still needs rendered
checks; provider delivery needs a separately configured integration environment.

## Find your way

| Area | Source |
|---|---|
| Landing page | `index.html` |
| Narrative onboarding and seed entry | `learn.html` |
| Member graph and contributions library | `map.html` |
| Seed planting experience | `seeds.html` |
| Six-step membership application | `join.html` |
| Steward login, applications, and member review | `admin.html`, `admin/`, `api/admin.js` |
| Shared interactions and styling | `script.js`, `style.css` |
| Canvas animations | `canvas.js`, `logo-canvas.js` |
| Server handlers and provider helpers | `api/`, `api/_lib/` |
| Local fixture transport and server | `scripts/lib/`, `scripts/dev.js` |
| Notion administration scripts | `scripts/*db*.js` (live operations; see integration guide) |

Start an AI coding session with:

```text
Read AGENTS.md and docs/development.md. Inspect git status and the relevant
implementation. Use the fixture environment for this task, make a bounded
change, and report check/test/smoke results plus any browser or live-service gaps.
```

- [Agent guide](AGENTS.md) and [site-development skill](skills/site-development/SKILL.md)
- [Architecture and integration contracts](docs/integrations.md)
- [Initial assessment](docs/assessment-2026-10-29.md)
- [Prioritized initial work](docs/work-plan.md)
- [Steward dashboard setup and verified Supabase state](docs/steward-dashboard.md)

## Deployment and stewardship

The intended workflow is a branch, pull request, Vercel preview, human review,
then merge. Confirm branch protection, deployment linkage, account ownership,
and environment separation in the actual services before relying on them. The
handover describes these settings; they have not been verified in this bootstrap.

Production readers publish only rows whose `Status` is exactly `Active`.
Applications start `Pending`; new seeds start `Active`. Public members exclude
contact and private review fields. The implementation owns exact Notion property
names; [integration notes](docs/integrations.md) explain the known discrepancies
in the inherited handover. Keep credentials and real application data out of Git.
