# Architecture and integration contracts

The [content management guide](content-management.md) owns the Supabase runtime
contract on this feature branch. Public routes no longer import the Notion
provider. The Notion details below are retained as a **legacy export mapping**;
hosted data migration/cutover is still pending. Use them to inspect source
exports, not to infer current production or branch deployment status.

## Legacy Notion contract and export mapping

Before this migration, the public browser called four Vercel handlers backed by
Notion, Resend, and the separate Telegram agent. The separate `/admin` browser
calls `/api/admin`, whose Supabase client carries the authenticated user's token
and remains subject to row policies. There is no frontend framework or bundler.
The [steward contract](steward-dashboard.md) owns dashboard schema, access,
configuration, and verification. The historical response fields below guide compatibility and export mapping.

| Route | Legacy behavior | Route implementation |
|---|---|---|
| `GET /api/members` | Paginated Members query, `Status = Active`, public projection | [members.js](../api/members.js) |
| `GET /api/contributions` | Paginated active contributions plus related member names | [contributions.js](../api/contributions.js) |
| `GET /api/seeds` | Active seed text/author/tags; empty list if DB ID is missing | [seeds.js](../api/seeds.js) |
| `POST /api/seeds` | 3–240 characters, honeypot, process-local quota, creates an Active seed, optional Telegram notice | [seeds.js](../api/seeds.js) |
| `POST /api/apply` | Name/email checks, honeypot, process-local quota, creates a Pending member, optional emails and Telegram notice | [apply.js](../api/apply.js) |

Production successful reads use `s-maxage=300, stale-while-revalidate=600`.
Updates are not guaranteed visible within exactly five minutes. Local fixture
responses use `no-store`. Adding a query string is not a verified cache purge.

## Browser feedback contract

Both seed forms use `seed-form.js` and `data-state.js`. Draft text is held in
`regen_seed_draft` in browser storage when available. It becomes a confirmed
`regen_vision` only after a successful HTTP response containing `{ ok: true }`.
The browser waits up to 15 seconds, retains text on rejection or uncertain
transport failure, and never automatically retries a seed write. Pending and
acknowledged submissions stay disabled. Learn passes a one-use session receipt
to the seed confirmation page; that page does not submit the seed again.

This prevents false success and duplicate clicks, not all duplicate records. If
the provider saves but the acknowledgement is lost, a later manual retry may
create another seed. Durable idempotency requires a separate API/storage change.
Browser storage can be unavailable; a successful Learn save then keeps its
confirmation and an Explore the commons link on the same page.

The map loads members and contributions independently. A successful empty list
is different from a failed or malformed response. Each failed section exposes
its own retry; a filter with no matching contributions has its own message.

## Notion schema

Exact names and types in the handlers are authoritative. The inherited README
and original `HANDOFF.md` used an older schema. The September archive is closer,
but is not an exact schema specification either.

Members public reads use `Org/Individual Name` (title), `Membership Type`
(select), `Status` (select), `Based In` (rich text), `Focus areas` and
`Contribution to Commons' Work` (multi-select), `Relationship to Regenerative work`
(rich text), `Website/Portfolio` (URL), `Avatar` (files), `Affiliations`
(relation), and `Date Applied` (date). Only **Active** is published; **Steward**
is not included by the current filter.

Application writes map form fields in `buildProperties()` in `api/apply.js`.
Review that entire mapping before configuring a database. For example,
`Org mission, Size and activities` includes a comma. Contact details and private
review answers are not returned by `/api/members`. Related contributor names
are retrieved separately without checking the member's publication status;
the desired privacy rule needs review.

Contributions use `Title`, `Type`, `Stage`, `Status`, `Description`, `Capital form`,
`Tier`, `Terms`, `Contributor`, `License`, `Tags`, and `Date contributed`.
`Capital form` is multi-select; `Tier` is select. The publication filter is
**Active**, not “anything except Archived.”

Seeds reads use `Text` (title), `Author` (rich text), `Status` (select), and `Tags`
(multi-select). Current POST writes only `Text` and `Status`: an incoming author
is parsed but not saved. Whether anonymous immediate publication remains the
desired behavior is a stewardship decision.

## Configuration

Use [`.env.example`](../.env.example) as the variable inventory. The fixture
environment needs none of them.

| Variables | Live purpose |
|---|---|
| `NOTION_TOKEN`, `NOTION_MEMBERS_DB_ID`, `NOTION_CONTRIBUTIONS_DB_ID`, `NOTION_SEEDS_DB_ID` | Integration access and three database targets |
| `RESEND_API_KEY`, `RESEND_FROM_EMAIL` | Optional application confirmation mail |
| `STEWARD_NOTIFY_EMAILS` | Optional steward recipients, comma-separated |
| `NOTIFY_URL`, `NOTIFY_WEBHOOK_SECRET` | Optional authenticated call to the separate agent's `/api/notify` |

`SITE_URL` was previously documented but is not read by current code. It is not
a required setup value. Telegram/Anthropic/Redis secrets belong to the separate
agent project, not this website.

## Failure and administration limits

Applications retry a Notion create once for HTTP 429/5xx, then attempt email and
Telegram capture of the raw answers before returning an error. This is best
effort: disabled/failed channels can lose the submission. Resend can return an
`error` in a fulfilled result, but the handler currently checks only rejected
promises. Telegram calls have no explicit timeout. See the
[work plan](work-plan.md) before expanding this flow.

The database sync scripts default to inspection and require `--apply` for writes.
`create-contributions-and-seeds-dbs.js` writes immediately and contains a legacy
default Members database ID. Do not use it as a routine bootstrap command.
Inspect its exact inputs and prepare a reviewed migration plan for an explicitly
authorized workspace before any live schema operation.

The archive reports that Members was adapted from an OpenCivics application
database. Ownership, consent/publication expectations, account access, email
configuration, custom-domain status, Vercel linkage, and branch protection need
current confirmation. They were not established by reading the supplied archive.
