# Steward dashboard verification

Evidence collected on 29 October 2026 on `codex/steward-dashboard`, above
foundation commit `b552d9a`. Dashboard implementation is scoped separately from
the foundation PRs. The PR records CI results for the published commit; the
results below distinguish local checks from hosted PostgreSQL verification.

## Local HTTP and automated behavior

`npm run check`, all 28 tests in `npm test`, and `npm run smoke` pass using
Node 22.22.1. The tests cover the original 14 foundation behaviors plus steward access,
code expiry/reuse, unknown and non-steward users, revoked roles, expired sessions,
private caching, input validation, origin checks, public/private projections,
relationships, Supabase SDK request contracts, provider failure, and sign-out
retry. Smoke covers six pages and their assets, public read/write behavior,
the publication gate, and local steward sign-in plus an authorized queue read.

PR review reproduced and fixed Auth outages being reported as invalid codes,
Auth throttling invalidating the session, database throttling losing its 429
status, and logout rejecting already-expired/deleted sessions. Regression tests
use the pinned Supabase SDK with synthetic HTTP responses. Service failures
remain retryable and do not masquerade as invalid credentials or successful logout.

The default server and these tests use synthetic providers. No test mail is
delivered by them, and the public join fixture is not wired into the new queue.

## Hosted PostgreSQL

The intended project is Regen Commons / Website, `ztygpuzldujfsqrubxic`.
Migration `20261029214914_steward_dashboard` is applied. The complete
[SQL suite](../supabase/tests/steward-access.sql) passed against PostgreSQL:

- Anonymous callers cannot select applications or members or call the access RPC.
- Authenticated visitors see no rows in any of the six exposed tables.
- User metadata claiming an admin/steward role grants no access.
- An active steward with an active session can read original answers and the
  related affiliations, contribution attribution, and history.
- Stewards cannot accept applications, publish members, or grant roles.
- Role revocation, expired sessions, and deleted sessions deny subsequent reads.

The transaction rolled back all synthetic users and records. Subsequent counts
confirmed zero Auth users, roles, applications, and members. Security advisors
reported one intentional informational notice for the private role table's lack
of a client policy, explained in the [setup guide](steward-dashboard.md).

## Rendered local browser

Used the Codex in-app browser at `http://127.0.0.1:3503/admin`, with
1280 × 900 desktop and 390 × 844 mobile viewports. The original fixture server
on port 3501 was preserved.

| Flow | Observed result |
| --- | --- |
| Valid and invalid codes | Invalid code shows a recoverable error; a requested valid code opens the desk |
| Non-steward account | Valid authentication still shows denied steward access and no records |
| Search and filters | Name search, organization filter, and no-match state work |
| Application detail | Original answers remain distinct from the curated draft; pending application is not accepted by previewing |
| Member view | Draft/published labels, affiliations, and contribution attribution render |
| API failure | An injected 503 shows an error rather than an empty queue; keyboard retry restores records |
| Sign-out failure | Private UI clears; a direct retry confirms sign-out once the failure is removed |
| Private DOM cleanup | Applicant names and private answers are absent after sign-out |
| Keyboard | Email-code submit, application-link activation, retry, and search focus work; visible focus is retained |
| Mobile | Queue, detail, and members reflow; document width equals the 390px viewport |
| Motion | The admin shell loads no public animation scripts and defines no animation or transition effects |
| Browser console | No warnings or errors in the final rendered desktop session |

Screenshots are local, ignored artifacts under `artifacts/steward-dashboard/`.
They contain synthetic records only. Failure scenarios are reset to `normal`
after verification. This is rendered fixture evidence, not hosted Auth evidence.

## Remaining limits

SMTP, the Magic Link code template, exact hosted origin/redirects, public-signup
settings, steward provisioning, and real email delivery are not verified. No
approved steward accounts or roles exist yet. The browser and HTTP flows have
not been exercised with a real hosted Auth session through the Data API.

Vercel routing/security headers remain unverified in deployment because this
slice has not been deployed. The known Hobby/private-organization-repository
restriction is unchanged. Local checks do not establish a hosted preview or
production deployment.

Dependency installation retained lockfile version 1 and pinned the Supabase SDK.
`npm audit` reported five pre-existing findings in the Notion/Resend dependency
tree (one high in `form-data`, four low). The new Supabase dependency was not
named in those findings. Dependency remediation is separate from this slice;
the existing `punycode` deprecation warning also remains.
