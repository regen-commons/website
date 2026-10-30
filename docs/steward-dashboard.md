# Steward dashboard pilot

The first `/admin` slice supports email-code sign-in, explicitly authorized
steward reads, application search and filters, private application detail, a
curated profile preview, and a member view with affiliations and contributions.
It is read-only. It does not accept applications, publish profiles, grant roles,
or replace the public site's Notion readers and intake.

## Run the local demo

Use Node 22, `npm ci`, and `npm run dev`. Open
[the steward desk](http://127.0.0.1:3501/admin). If another session owns port 3501,
use `PORT=3503 npm run dev` and open the same path on port 3503. Do not replace
another session's server. The implementation session uses port 3503.

1. Enter `steward@example.test` and request a code.
2. Enter `123456`. This is a synthetic fixture code; no email is sent.
3. Search for River, filter by organization, open an application, and visit Members.
4. Sign out. `visitor@example.test` with the same requested code demonstrates
   authentication without steward authorization. An unknown address cannot sign in.

The local server explicitly injects its synthetic provider and removes inherited
Supabase settings. Production handlers never import that provider. Codes require
a request, expire after ten minutes, and are single-use. Fixture sessions expire
after an hour. All fixture data disappears when the server stops.

The existing join form still writes to its separate synthetic Notion fixture;
those submissions do not appear in the new Supabase review queue. A shared intake
cutover is a later migration, not a side effect of adding this dashboard.

## Verified hosted project

On 29 October 2026, the **Regen Commons** connection exposed the **Website**
project, `ztygpuzldujfsqrubxic`, in `us-east-1`, running PostgreSQL 17.11.
Initial inspection found no public tables, migrations, or Auth users.
The unrelated Greenpill/metrics project was not used.

The [steward migration](../supabase/migrations/20261029214914_steward_dashboard.sql)
was applied to this project. Its local filename matches the version recorded by
the migration tool. The project API URL and availability of a publishable key
were verified. No secret/service-role key was retrieved or used.

[Database authorization tests](../supabase/tests/steward-access.sql) execute in
one transaction with synthetic Auth users, sessions, roles, applications, and
relations, then roll everything back. They exercise actual PostgreSQL grants
and row policies, independently of the HTTP fixtures. After testing, the project
still contained zero Auth users, steward roles, applications, and members.

The security advisor found no warning or error. Its single informational finding,
[RLS enabled without a policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
is intentional for `private.steward_roles`: clients have no table grants and no
row policy, so they cannot read or modify roles. Do not add a permissive policy
to silence this notice.

## Access and data contract

The server checks the user's token with Supabase Auth, then calls
`steward_access()`. Every query uses that same user token and a publishable key;
there is no privileged data client. Row policies independently require an active
server-managed role and the matching unexpired `auth.sessions` row. Removing a
role or session takes effect on the next read, even with an existing JWT.
User-editable metadata does not participate in authorization.

The only elevated function is the internal role/session lookup in the private
schema. It uses a fixed search path, reads only the caller's identity, and takes
no caller-supplied user ID. The exposed boolean RPC runs as the caller.

| Record | Meaning in this slice |
| --- | --- |
| `applications` | Private contact details and original answers, schema version, revision, submission time, source/request identities, and descriptive review state |
| `members` | Separately curated profile fields with draft/published/hidden state; no application answers or contact details |
| `affiliations` | Member-to-organization links retained as IDs |
| `contributions`, `contribution_members` | Resources and member attribution, with independent publication state |
| `review_events` | Recorded events and the revision they concern; no invented approval history |
| `private.steward_roles` | Administrator-managed Auth user IDs with active access |

A linked profile may still be a draft while its application is pending. The
preview reads the linked profile, never an automatic projection of private
answers. Public access to these new tables is not enabled, even for rows marked
published. Public publication requires its own approved projection and cutover.
Authenticated stewards have SELECT only; decision and role mutations are denied.

`GET /api/admin` accepts `resource=session`, `applications`, `application&id=UUID`,
or `members`. Application lists select summary fields, search display names,
filter by applicant type/review state, and page in groups of 25. Detail reads
include private answers, a linked curated profile, and record history. Member
reads preserve relation IDs and paginate provider queries to avoid silent caps.
POST accepts only `request-code`, `verify-code`, and `sign-out`.

Hosted sessions use a Secure, HttpOnly, SameSite=Strict, host-only cookie. Tokens
and private data never enter localStorage or URLs. POST requests require JSON
and the exact configured Origin. Private responses are not cached by the browser
or CDN. The UI clears private data on sign-out, authorization failure, and page
exit; it ignores stale view responses and rechecks browser-history restoration.
This bounded pilot does not persist refresh tokens: sign in again when the access
token expires, no later than one hour. Sign-out revokes the current session;
failure keeps the operation retryable and does not report success.

## Configure real steward sign-in

The connector has no Auth-settings operation; the authenticated Supabase browser
is used for SMTP and templates. On 29 October 2026, Namecheap's authoritative DNS
returned the expected DKIM TXT and two sending CNAME records for
`auth.regencommons.com`. Resend reports the domain and all three records verified.
The intended sender is `Regen Commons <signin@auth.regencommons.com>`.

Custom SMTP is saved with `smtp.resend.com`, port `465`, and username `resend`.
The user created a sending key restricted to the authentication domain and
entered it directly into Supabase's Password field. No credential was entered
into chat or committed. No secret or service-role key is needed by the dashboard.

The Magic Link or OTP template now uses `{{ .Token }}` and subject
`Your Regen Commons sign-in code`; its [versioned body](../supabase/templates/magic-link.html)
uses the website's warm vellum palette. One approved account has been created
through Supabase's user interface and granted an active steward role. A real
code request from the actual dashboard handler succeeded, and Resend reports
delivery to the approved recipient. The recipient completed code entry, and
the browser loaded the authorized Applications and Members views. Reloading
preserved the hosted session. Both datasets are currently empty; no live
applications or profiles were imported for the test.

Gmail desktop displayed the original template without its intended padding.
The template now uses presentation tables, inline cell padding, and a fixed-width
Outlook fallback. A fresh code email was delivered after that update, and the
recipient confirmed correct padding in Gmail desktop. The dashboard also reuses
the public website's `logo-canvas.js` artwork in still mode, with the same circle
and wordmark.

The email provider currently uses eight-digit OTPs with a 3,600-second expiry.
Public signup is enabled at the project level; the dashboard's own requests use
`shouldCreateUser: false`, and database access independently requires an active
steward role and session. Project-wide signup-policy changes require a separate
decision. The published website currently returns 404 for `/admin`; a disposable,
loopback-only Auth probe can exercise the actual handler and hosted Supabase
without changing the default fixture server or deploying the site.

Before a separately authorized hosted pilot:

1. Configure Supabase Auth custom SMTP using an organization-owned sender, such
   as the existing Resend account once its ownership and domain are verified.
   Supabase owns authentication; Resend transports the mail. Use the
   [SMTP settings](https://supabase.com/dashboard/project/ztygpuzldujfsqrubxic/auth/smtp)
   and [official SMTP guide](https://supabase.com/docs/guides/auth/auth-smtp).
2. Set the Magic Link email template to display `{{ .Token }}` for email codes.
   Confirm the expiry, code length, and rate limits. The UI accepts 6–10 digits.
   See [passwordless email](https://supabase.com/docs/guides/auth/auth-email-passwordless).
3. Configure the exact HTTPS site/redirect URLs. Decide whether public signup
   should be disabled for this steward-only project. The application sends
   `shouldCreateUser: false`, but that client option alone is not a project-wide
   signup restriction.
4. Provision only the named, approved steward accounts and activate their rows
   in `private.steward_roles` through an administrator-controlled process. No
   additional users or roles are implied by this pilot. The single named test
   steward is provisioned. Establish the steward list before granting further
   access; do not send invitations as a test.
5. Set `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `ADMIN_ORIGIN` in the
   authorized deployment environment. The expected URL is
   `https://ztygpuzldujfsqrubxic.supabase.co`. `ADMIN_ORIGIN` is the exact HTTPS
   website origin without a path or trailing slash. No service-role key is needed.
6. Verify a code with an approved test recipient or local Supabase test mail,
   plus revocation, session expiry, and non-steward denial over the actual Data
   API. Browser fixtures and SQL role tests do not prove hosted Auth delivery.

No billing, repository visibility, deployment, live member migration, or real
notifications were changed. The known Vercel Hobby/private-organization-repository
deployment restriction remains outside this implementation.

## Completion evidence and remaining decisions

Run `npm run check`, `npm test`, and `npm run smoke`. The SQL file is a separate
database-owner test; default `npm test` does not contact Supabase. For an authorized
database with `psql`, execute the whole file with `ON_ERROR_STOP=1` so a failed
assertion closes the connection and rolls back. The connected SQL tool can also
execute the complete file as one request. Never run only its fixture inserts.

See [browser and test evidence](steward-verification.md). The pinned Supabase SDK
is 2.118.0, and the migration was created with CLI 2.122.0. Current Supabase
passwordless, SMTP, and row-policy documentation informed the implementation;
cached Modern Web Guidance supplied the form/accessibility guidance.

Before accepting/publishing or importing live records, agree who has each
authority, which fields may become public, source ownership/consent, repeated
application handling, and notification recipients. Seeds, intake idempotency,
transactional decision writes, import reconciliation, attachment transfer,
public cache invalidation, and export/restore rehearsal remain migration work.
