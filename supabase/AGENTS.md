# Steward data and database policy

Use the [root guide](../AGENTS.md) for shared workflow and the
[API guide](../api/AGENTS.md) for callers. Inspect `supabase/migrations/`,
`supabase/tests/`, and the owning provider adapter before changing the schema.
A checkout with only this guidance does not contain an installed database;
record missing implementation or test prerequisites explicitly. Use the Supabase
skill when available for current tooling and platform guidance; repository
migrations own this project's data contract.

## Data boundaries

- Preserve the distinction between private applications, curated member
  profiles, affiliations, contributions, and review events. Keep source IDs and
  submitted revisions available for reconciliation; do not merge people or
  overwrite original answers merely because names or fields match.
- A linked profile is not acceptance, and acceptance is not publication. Review
  authority and allowed transitions must be established before implementing
  decisions. The existing read-only grants do not imply write authority.
- Application answers, contact details, and review history are private even
  when a table is in the `public` schema. Public member/map reads require an
  explicit field projection and publication contract.
- Steward roles are server-managed. Preserve the active-role and active-session
  checks; user-editable metadata must not influence authorization.

## Schema and access changes

Use versioned migrations for durable schema changes. Do not rewrite migrations
already applied to a shared environment. Verify the intended project and current
schema before any remote operation; follow the user's authorized scope.

Keep explicit least-privilege grants and row-level security on exposed tables.
Review policies, views, and function execution privileges together. Prefer
security-invoker functions. Keep necessary elevated lookups narrowly scoped in
the private schema with a fixed search path, caller identity checks, and explicit
execution grants; do not use elevation as a generic permission fix.

## Verification

For schema or policy changes, extend and run
`supabase/tests/steward-access.sql` when present against the intended test database,
with synthetic records and cleanup. If that test is absent, establish equivalent
behavioral SQL proof before claiming policy verification. Verify allowed reads and denied
anonymous, non-steward, spoofed-metadata, revoked-role, and revoked-session
access. Check mutation denial while access remains read-only. Inspect database
advisors for changed policies, views, or privileged functions.

Run the root checks when API or fixture contracts change. Report SQL results
separately from fixture tests, and distinguish a local migration file from an
applied migration. Keep credentials and real member exports out of test data,
logs, and committed artifacts.
