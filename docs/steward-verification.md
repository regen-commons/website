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
| Motion | The shared logo renderer uses still mode in the dashboard; it requests no animation frames and redraws on theme changes |
| Browser console | No warnings or errors in the final rendered desktop session |

Screenshots are local, ignored artifacts under `artifacts/steward-dashboard/`.
They contain synthetic records only. Failure scenarios are reset to `normal`
after verification. This is rendered fixture evidence, not hosted Auth evidence.

## Design alignment follow-up

On `codex/steward-smtp-design`, the public site and steward desk share their
existing color and typography tokens in `design-tokens.css`. The dashboard uses
self-hosted Latin subsets of Fraunces, Source Serif 4, and Space Grotesk under its
existing same-origin content security policy. Public-page font loading is
unchanged. Its theme toggle stores only the shared `rc-theme` preference.

`npm run check`, all 29 tests, and `npm run smoke` pass on Node 22.22.1. The added
HTTP regression compares the served WOFF2 bytes with the source font so the local
server cannot silently corrupt binary assets through UTF-8 decoding.

Brave rendered the light and dark login/queue views, original-answer detail,
and the 390px queue/detail layout. Light-theme paper and display-font tokens
match the public page. Document width equals the 390px viewport, and keyboard
Space activates the theme toggle. Screenshots under `artifacts/steward-design/`
contain synthetic records or the approved live account's empty dashboard.
The logo uses the website's renderer and wordmark with a still-mode opt-in.
A focused renderer check confirms that the public animated default is preserved
and the dashboard requests no animation frames, including after a theme change.

## Hosted Auth verification

Resend has verified the authentication domain and its three sending records.
Custom SMTP is saved, and the Magic Link or OTP template now sends only the
one-time code with the subject `Your Regen Commons sign-in code`. It retains
the project's existing eight-digit length and one-hour expiry. The user created
the approved Auth account through the dashboard, and its active steward role
was granted only after checking the exact account and confirmed-email status.

A disposable probe at `http://localhost:3504/admin` serves the actual dashboard
and `createAdminHandler` with the real hosted Supabase provider. It binds only
loopback, restricts code requests to the approved recipient, retains Secure
HttpOnly cookies, and does not import fixture transport. Its health route names
the hosted project. Unauthorized reads return 401; other recipient requests
return 403 before contacting Auth. The ordinary development server is unchanged.

The real code request succeeded, and Resend's email list reports **Delivered**.
Local evidence is in `artifacts/steward-design/email-delivered.jpg`. The user
entered the code directly into the dashboard and completed sign-in. The real
hosted provider returned authorized, empty Applications and Members views.
Reloading preserved the session; a separate database read confirmed the account
had signed in with one session and an active steward role. No token, code, or
password was captured in the evidence.

The user reported missing email padding in Gmail desktop. Padding originally
depended on an HTML5 `main` element. The revised template uses presentation
tables, inline cell padding with `cellpadding` fallbacks, and an Outlook width
fallback. A synthetic 390px browser preview has 40px left content spacing and no
horizontal overflow. Supabase saved the revision, and Resend confirms a second
real email was delivered. The recipient confirmed that padding is now correct
in Gmail desktop.

Exact hosted origins/redirects remain a deployment prerequisite.

Vercel routing/security headers remain unverified in deployment because this
slice has not been deployed. The known Hobby/private-organization-repository
restriction is unchanged. Local checks do not establish a hosted preview or
production deployment.

Dependency installation retained lockfile version 1 and pinned the Supabase SDK.
`npm audit` reported five pre-existing findings in the Notion/Resend dependency
tree (one high in `form-data`, four low). The new Supabase dependency was not
named in those findings. Dependency remediation is separate from this slice;
the existing `punycode` deprecation warning also remains.
