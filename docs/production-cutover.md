# Supabase production cutover

The user authorized review, fixes, runtime configuration, final reconciliation,
merge, deployment, and live verification on 29 October 2026. This release remains
separate from public-site polish.

## Final source reconciliation

Live Notion access required sign-in. The user confirmed that the supplied exports
are final, there were no later changes, and source edits are paused. This is an
operator confirmation, not a claim that live Notion was independently queried.
The supplied files were re-read and produced the same source and import digests
as the [hosted import receipt](notion-import.md#hosted-reconciliation): all 60
source records, 68 files, relationships, and four recovered submissions match.
No additional Notion data import was required.

## Review fixes

- Membership requests now sort dated submissions before unknown legacy dates.
  The actual Supabase SDK query is covered by a regression check, so imported
  requests cannot push new submissions to later pages.
- The floating Feedback link still opened a separate public Notion form. The
  user selected a Supabase replacement. `/feedback` retains its seven categories,
  saves private messages/context in `public.feedback`, and sends no notifications.
  Anonymous and non-steward reads are denied; current active stewards can read
  through the database API. This release adds no feedback-management dashboard.

Feedback uses the existing bounded server intake capability, independent quotas,
retained retry identities, and one transaction per save. A changed payload with
the same identity is rejected. Only a confirmed save clears the pending state;
failed/uncertain saves retain the text. Client and database validation bound
message length, categories, and page context. No browser credential is added.

## Runtime and verification

Production-only Vercel configuration now includes `SUPABASE_URL`,
`SUPABASE_PUBLISHABLE_KEY`, the encrypted `SUPABASE_INTAKE_SECRET`, and
`ADMIN_ORIGIN=https://regencommons.com`. Only the capability's digest is stored in
`private.intake_settings`. The credential is absent from Git and browser assets.
Production credentials are not added to PR previews or local fixtures.

The existing Telegram destination is preserved. The user approved two clearly
labeled test alerts, for a temporary Seed and membership request. Auth testing
uses the previously named steward account. Application receipt email is optional
and remains unconfigured in Vercel; Supabase Auth SMTP is a separate configured
service. No other applicants should receive test mail.

Pre-release verification passes `npm run check`, all 53 tests, and `npm run smoke`
(seven pages). Disposable PostgreSQL 17 verifies all migrations, the steward and
public-data suites, and feedback privacy/idempotency. Rendered feedback checks
cover native required-field validation, a confirmed synthetic save, seven
categories, light/dark themes, and no horizontal overflow at 390px. No console
warnings/errors were observed.

## Release status

The runtime and feedback migration are applied. Hosted feedback has RLS enabled,
anonymous reads denied, and active-steward read access. The migration file matches
hosted version `20261030044355`. Final current-head CI, merge,
deployment, live form/Auth/moderation checks, and Notion environment retirement
are pending. Update this record with the released commit and live evidence.

## Recovery

Preserve all post-cutover Supabase writes. Do not restore a Notion-writing API
deployment as an automatic rollback: it would split the source of truth. Repair
or roll forward the Supabase API; an isolated static/UI rollback must retain that
API. The original exports and Notion source remain recovery evidence. Retiring
the website's Notion configuration does not delete the source workspace.
