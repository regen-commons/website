# API and data access

Use the [root guide](../AGENTS.md) for shared workflow. Inspect the browser caller,
handler, provider adapter, and fixture together before changing a contract.
Read [integration contracts](../docs/integrations.md) for public Notion handlers,
the [admin guide](../admin/AGENTS.md) for dashboard flows, and the
[database guide](../supabase/AGENTS.md) for schema or authorization changes.

## Boundaries

- Keep provider SDKs and credentials on the server. Public intake and map/member
  reads retain their existing provider until an explicit migration changes
  them. A new Supabase table or dashboard route does not authorize a cutover.
- For steward reads, verify the user and current steward authorization on every
  request. Keep database calls scoped to the user's token so row-level security
  remains effective. Email possession, client state, and user-editable metadata
  do not grant steward access; do not substitute a service-role client.
- Keep sessions in secure, HttpOnly cookies in hosted environments. Preserve
  same-origin checks for POST requests and private, no-store response caching.
  Plain-HTTP fixture cookie settings belong only to local development.
- Bound and validate methods, bodies, identifiers, filters, and pagination at
  the handler boundary. Give provider calls a timeout and return stable error
  codes without raw provider responses or personal data in logs.
- Select response fields for the consumer. Private answers and contact details
  belong to authorized detail reads, not public member/map projections. Keep
  original submissions, curated profiles, and review decisions distinct.
- Inject synthetic providers for local checks. Extend fixtures alongside new
  operations; local fixture requests must never fall through to live providers.

## Verification

Run the root implementation checks. Add behavioral regression coverage at the
changed boundary, including validation failures and provider unavailability.
For steward/session changes, cover anonymous and non-steward denial, valid
steward access, expired or revoked sessions, revoked roles, origin rejection,
and private caching as relevant. Check that failed requests return no records.

When the dashboard implementation is present, `tests/steward.test.js` owns the
handler/fixture contract. If it is absent from this checkout, record the missing
proof rather than claiming the steward flow is verified. Changes to database
authorization also need the database guide's SQL checks; mocked authorization
cannot prove row-level security. Record which provider and environment produced
each result.
