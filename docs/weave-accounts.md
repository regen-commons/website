# Private Weave account saving

Status: prepared for review, not applied to the hosted project. The website owns
Supabase migrations for both applications. The companion app is in
[Funding Commons](https://github.com/regen-commons/funding-commons).

## Database contract

`20261105082413_weave_private_accounts.sql` adds `weave.accounts`,
`weave.initiatives`, `weave.needs` and `weave.offers`. A save contains the person's
checked card, kept needs and offers, and kept funding details. Source conversations,
files, open editors and AI records stay in the browser. Every initiative is private;
this migration permits no visibility transition, publication, membership change,
subscription or email dispatch.

An account references `auth.users`; it creates no `members` row. Authenticated people
can select their own rows through RLS. Anonymous users, other accounts and stewards
cannot read private records. Writes require `weave.save_initiative`, an invoker
wrapper around a narrow private command that verifies a confirmed email, the actor and an active
`auth.sessions` entry. User-editable metadata grants no access. All exposed functions
are invokers, with empty search paths and explicit execution grants.

The version 1 document accepts all eight kinds of support and at most five needs
and five offers. Unknown fields, browser owner/visibility claims and source data
are rejected. Saving card and ask rows is one transaction. An expected revision
prevents overwriting another device's changes. A request UUID is scoped to the
verified actor; retrying the same payload returns its earlier receipt, while reusing
it for a changed payload fails. Receipts retain historical checked documents in a
private journal for retry safety. Database administrators can technically access
private data. Auth-user deletion cascades through these rows and receipts.

New acknowledged saves are limited to 30 per account per clock hour. Retries do not
consume quota, and failed commands roll back their quota increment. Expired quota
windows are removed on the next successful save. No website intake quota or
membership policy is changed.

## Review and release order

1. Review this migration and the companion app PR together. Auth and RLS require an
   independent second review before merge. Reconfirm project `ztygpuzldujfsqrubxic`
   (Website, us-east-1) and that the six previously applied migrations still match.
2. Obtain approval before applying this migration to a shared environment. Take the
   appropriate private backup and apply through this repository's migration lane.
   Do not run it from Funding Commons or rewrite an already applied migration.
3. After approval, add `weave` to the project's Data API exposed schemas. Preserve
   the existing entries and grants; never expose `private`. The SQL file alone does
   not change the hosted Data API configuration.
4. Review the generic code wording in `supabase/templates/` and, after approval,
   update the shared Supabase sign-in template. Preserve `{{ .Token }}`, the current
   eight-digit code length and one-hour expiry. Check email sign-up availability,
   SMTP delivery and project-wide limits with the Auth owner. This proposal does
   not install an email hook or change those settings.
5. Configure the Weave Vercel project's server-only variables as described in its
   [account specification](https://github.com/regen-commons/funding-commons/blob/main/docs/platform/08-accounts-and-saving.md#private-account-connection).
   Use a publishable key and the person's JWT, never a service-role key. The app
   remains disabled until explicitly enabled; the website's environment is separate.
6. With separately authorized synthetic accounts and destinations, verify real code
   delivery, invalid/expired codes, private save, reload from a second browser,
   cross-account denial, stale revisions and revoked-session denial. Recheck the
   existing steward sign-in flow. Record this as hosted proof, separate from fixtures.
7. Approve any production deployment separately. To stop account access, disable the
   Weave app flag and remove `weave` from exposed Data API schemas after approval.
   Keep saved rows intact; do not drop the schema as a rollback shortcut.

## Verification

CI applies all migrations to disposable PostgreSQL 17 using the synthetic Auth
stub in `supabase/tests/local-auth.sql`, then runs every SQL access suite, including
`weave-private-access.sql`. This proves SQL ownership, transactions, idempotency,
quotas and session checks. It does not prove hosted Supabase Auth, PostgREST schema
exposure, email delivery, or a Vercel deployment.

The local website checks remain `npm run check`, `npm test`, and `npm run smoke`.
On the maintainer's Mac these run inside the isolated dev machine. No hosted DDL,
Auth setting, email or deployment is part of preparing these PRs.
