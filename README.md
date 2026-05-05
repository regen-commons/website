# Regen Commons — Site

Static HTML/CSS/JS site backed by three Notion databases (Members, Contributions, Seeds) and Resend for transactional email. Hosted on Vercel.

## What this site does

- **`/`** — landing page (static)
- **`/learn.html`** — narrative onboarding (static, with a horizontal scroll flow)
- **`/seeds.html`** — vision-planting threshold; pulls vision quotes from the **Seeds** Notion DB
- **`/map.html`** — ecosystem graph + commons library; pulls from **Members** and **Contributions** Notion DBs
- **`/join.html`** — membership application form; submissions create rows in the **Members** DB and trigger confirmation emails via Resend

## Architecture

```
[Browser] ──▶ /api/apply        ──▶ Notion (Members DB, Status=Pending) + Resend (2 emails)
[Browser] ──▶ /api/members      ──▶ Notion (Members DB, Status=Active|Steward)
[Browser] ──▶ /api/contributions ─▶ Notion (Contributions DB, Status≠Archived)
[Browser] ──▶ /api/seeds        ──▶ Notion (Seeds DB, Status=Active)
```

All Notion / Resend secrets live in Vercel env vars — never in the repo.

## Local development

```bash
npm install
npx vercel link        # first time only — links this directory to the Vercel project
npx vercel env pull    # pulls env vars from Vercel into .env.local
npm run dev            # starts vercel dev on http://localhost:3000
```

Without env vars set, the API routes will return errors but the site still renders — pages fall back to their built-in static content (e.g. the hardcoded ecosystem graph and commons cards).

## Environment variables

See [`.env.example`](.env.example). Set these in Vercel under **Settings → Environment Variables** for each environment (Production, Preview, Development):

| Variable | Purpose |
|---|---|
| `NOTION_TOKEN` | Internal-integration token from Notion → Integrations |
| `NOTION_MEMBERS_DB_ID` | 32-char hex ID of the Members database |
| `NOTION_CONTRIBUTIONS_DB_ID` | 32-char hex ID of the Contributions database |
| `NOTION_SEEDS_DB_ID` | 32-char hex ID of the Seeds database |
| `RESEND_API_KEY` | Resend API key (`re_…`) |
| `RESEND_FROM_EMAIL` | Verified sender address on your domain |
| `STEWARD_NOTIFY_EMAILS` | Comma-separated emails of stewards to notify on each new application |
| `SITE_URL` | The site's primary URL (used in email copy) |

## Notion database schemas

### Members

Public properties (returned by `/api/members`): **Name** (title), **Type** (select: Individual / Organization), **Status** (select: Pending / Active / Steward / Archived), **Location** (text), **Focus areas** (multi-select), **Contribution areas** (multi-select), **Vision** (text), **Website** (URL), **Avatar** (files), **Affiliation** (relation to self), **Date joined** (date).

Private review properties (kept on the page; never returned by the API): **Email**, **Telegram**, **Org rep**, **Org description**, **Nominator**, **Regen relationship**, **Values resonance**, **Meaningful participation**, **Capital contribution**, **Contribution other**, **Commitment**, **Constraints**, **Authorized**, **Other colleagues**, **Agreement reviewed**, **Governance consent**, **Closing notes**.

New applications land here with `Status = Pending`. To welcome someone in, change `Status` to `Active` (or `Steward`) — the change reflects on the public site within ~5 minutes.

### Contributions

**Title**, **Type** (Knowledge / Infrastructure / Brand & IP / Governance & Legal / Coordination), **Stage** (Seed / Sprout / Flowering / Tree), **Status** (Indexed / In progress / Curated / Archived), **Description**, **Capital form**, **Tier**, **Contributor** (relation → Members), **License**, **Tags**, **Date contributed**.

### Seeds

Vision quotes that appear in the seed-field on `/seeds.html`.

**Text** (title — the quote itself), **Author** (text — optional attribution), **Status** (Active / Archived), **Tags** (multi-select).

## Maintainer workflow

The repo uses PR-driven development so that no one merges directly to production:

1. Branch from `main` (`git checkout -b fix/typo-on-learn-page`).
2. Make changes (locally, or via GitHub's web editor).
3. Open a PR. Vercel posts a preview URL in the PR conversation within ~30 seconds.
4. Another steward reviews + approves.
5. Merge. Vercel auto-deploys to production within ~1 minute.

`main` is protected: pushes are blocked, PRs require 1 approval.

For pure content edits (typos, copy tweaks), GitHub's web editor (press `.` in any file view) is sufficient — no local environment needed.

## Adding members or contributions without an application

Add the row directly in Notion (Members DB, set `Status = Active`). It appears on the map within ~5 minutes.

## Removing a member

Set `Status = Archived` in Notion. They drop off the public site within ~5 minutes.

## Rotating credentials

If a Notion token, Resend key, or Vercel secret needs to be rotated:

1. Generate the new value in the source service.
2. Update it in Vercel → Settings → Environment Variables.
3. Trigger a redeploy (Deployments → … → Redeploy) so functions pick up the new value.

## Troubleshooting

- **Map shows the fallback ecosystem (the original hardcoded list):** `/api/members` errored or returned nothing. Check the function logs in Vercel → Deployments → … → Functions, then verify `NOTION_TOKEN` and that the Members DB is shared with the integration.
- **Form submits but no email arrives:** check Resend → Emails for delivery status. Common issues: domain not verified, `RESEND_FROM_EMAIL` not on the verified domain.
- **Application created in Notion but `/api/members` doesn't return it:** check `Status` on the row — it must be `Active` or `Steward` to appear publicly.
