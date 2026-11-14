# Contact messages

The About form and the [Podcast page's Take part form](#podcast-messages) save
private correspondence in `public.contact_messages`. Active
stewards review it in `/council#messages`, open a message to see the sender’s
email and full text, and use Reply by email in their own email app. The dashboard
does not send a reply or track a response as completed.

## Contract and access

`POST /api/contact` accepts JSON with `name` (1–200 characters), `email` (valid
address, at most 254), `subject` (1–200) and `message` (3–5,000). Lengths count
UTF-16 units, as browser controls do. Required strings are trimmed; the email is
lowercased. A filled `website_confirm` honeypot is ignored. Bodies are bounded
to 32 KiB. Valid new saves are limited to three per connection per clock hour by
the existing hashed-actor intake mechanism. No raw network address is stored.

The browser sends a UUID in `Idempotency-Key` and reuses it when unchanged text
is retried. Supabase serializes that identity before quota and insert; replay
returns the existing record, and different content under that identity gets 409.
The form keeps its draft in page memory through errors. Reloading clears it and
its retry identity, so this is not deduplication across a reload. Success means
the message is saved, independently of notification delivery.

There is no public listing. Anonymous reads and client writes are denied. Active
steward reads use the existing user token, session checks and row policy; they
never use a service-role key. Inbox summaries omit email and message bodies.
The UI renders submitted text as text, clears it on sign-out or access loss, and
ignores stale requests after navigation. The contact schema is separate from
applications, curated member profiles and website feedback.

## Podcast messages

`/podcast` has a second form that saves through the same endpoint. It adds no
table, RPC, environment variable or notification type, so it needs no migration
and no agent release.

The form asks for a name, an email, any of six interests and an optional note.
`podcastMessage()` in `podcast-contract.js` turns that into an ordinary contact
payload before the browser posts it:

| Contact field | Podcast content |
| --- | --- |
| `subject` | `Podcast: ` and the short form of each chosen interest in listed order, or `Podcast: note` when none is chosen |
| `message` | `Ways to take part: ` and the chosen labels, then the note |

A message with no interest and a note under three characters is rejected in the
browser. The note is capped at 4,500 characters so every label still fits the
5,000-character contact message. The server applies only the contact contract.
It cannot tell that a message came from the podcast page, so the subject prefix
is a convention for stewards and not something the database enforces.

Podcast and About messages share the inbox, the Telegram alert text and the
quota of three saves per connection per clock hour. Stewards cannot filter or
count by interest. Add a structured column or table if the council comes to
need that.

`contact-submit.js` holds the submit, retry-identity and saved-state behavior
for both forms.

## Telegram delivery

The saved row itself is the notification queue. `drainContact()` claims at most
five pending rows under a lease, sends `type: "contact"` through the existing
agent and records `sent` only after `{ ok: true }`. The alert contains a short
notice and `/council#messages/<id>`; it omits the sender’s name, email, subject and
message. No contact text is sent to the model.

The inbox displays these delivery states:

| State | Meaning |
| --- | --- |
| Pending | Saved and waiting for a configured worker |
| Sending | A worker holds the delivery lease |
| Sent | The agent confirmed Telegram accepted the alert; this does not mean a steward read it |
| Needs review | Delivery was rejected or uncertain, or a lease expired |

Missing notification settings leave the row pending. The ordinary save attempts
delivery immediately; `scripts/process-notifications.js` also processes pending
contacts when an authorized operator runs it. There is no new scheduled worker.
If a process stops after saving and before claiming, run that worker. An expired
Sending lease becomes Needs review when the worker next checks the queue.

Needs review is intentionally not automatically retried: Telegram may have
accepted a message before the response was lost. An operator checks the topic
first. If the alert is absent, an authorized operator can reset only that row to
Pending and rerun the worker; this administrative recovery is not exposed as a
council button in this version. The saved correspondence remains reviewable
regardless of delivery state.

## Release order

This implementation adds no environment variables. It reuses `SUPABASE_URL`,
`SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_INTAKE_SECRET`, `ADMIN_ORIGIN`, `NOTIFY_URL`
and `NOTIFY_WEBHOOK_SECRET`. `ADMIN_ORIGIN` must be the exact HTTPS website
origin. The configured intake secret’s hash must already exist in
`private.intake_settings`.

1. Deploy the companion agent’s contact event and corrected dashboard labels.
2. Apply `20261112013204_contact_messages.sql` to the confirmed website project
   through the normal reviewed migration process. It does not alter existing
   intake RPCs, membership tables or their notification jobs.
3. Deploy the website change.
4. With authorization for the hosted test destinations, submit one synthetic
   contact, inspect its dashboard detail and Telegram link, then clean up the
   synthetic correspondence. Confirm a second browser session cannot read it
   without steward access.

The hosted migration, both deployments and real Telegram delivery were completed
in the authorized release recorded below.

## Verification — 11 November 2026

The website’s `check`, 88 behavioral tests and smoke pass. A fresh disposable
PostgreSQL 17 applied all migrations, then passed the contact suite and all eight
existing SQL suites. Contact SQL proves idempotent saving, validation, restricted
reads/writes, active/revoked roles and sessions, notification leases, and no
automatic retry of uncertain delivery. This is local PostgreSQL evidence, not a
hosted Supabase migration or advisors result.

Rendered local fixtures in the Codex in-app Chromium browser show the contact
save, private council inbox/detail, keyboard submission, retained text on an
injected 503, successful retry, inbox failure/retry, and 390px layouts without
horizontal overflow. Organization links each occupy their own row at desktop
and mobile widths. Fixture mode sends no email or Telegram messages. The new UI
adds no motion. Cached Modern Web Guidance could not be loaded because the
shared tooling entrypoint is unavailable inside the dev machine; repository
standards and rendered checks were used.

The companion agent review is in its `docs/agent-review.md`, including remaining
webhook/processing risks and proposed public Weave discovery tools. No private
Weave integration or matching change is part of this contact feature.

## Hosted release — 11 November 2026

The user authorized the production migration, both deployments and a synthetic
contact/Telegram test. The release used the Regen Commons account and the
existing production projects and settings; no credentials or private roster were
exported or committed.

| Component | Verified release |
| --- | --- |
| Agent | Commit `d6f201a1be1c286f94ee1ac4f80fe28a6a67d0d2`, branch `codex/contact-notifications`, production `dpl_C1C4p6xM6bwXse12YbMsHCyB8NS1`, READY |
| Database | Platform `ztygpuzldujfsqrubxic`, migration `20261112013204_contact_messages.sql`, applied and read back |
| Website | Commit `e1d25f429b55a4dac1bfda02492ae14c489d3e1b`, branch `codex/about-contact`, production `dpl_C1bw9dXR752zi2F7tYpX8DyDvj5F`, READY |

The agent’s existing `regen-commons-agent.vercel.app` alias and the website’s
`regencommons.com` alias resolve to these releases. Each deployment used a
release-scoped ignored-build-command override so the task branch could build;
the projects’ shared branch settings were not changed. The local migration
filename was aligned with the version assigned by the hosted migration tool.
Neither repository’s `main` was merged or changed. Future main-based releases
need to incorporate these release branches.

At 5:34 p.m. PST, the actual live About form submitted one record named
`TEST: contact launch 2026-11-11`, using an invented name and an `example.test`
address. Supabase saved record `35fd97d9-8189-4da9-9c29-a54ca5c10406` at
01:34:23 UTC on 12 November. Its notification became `sent` at 01:34:25 UTC.
The production agent requires Telegram’s `{ ok: true }` acknowledgement before
reporting success, so this proves API-acknowledged Telegram delivery. The
Telegram group UI was not separately inspected.

The user signed in directly to the live council browser. After reloading the
new release, the inbox showed the single test record and `Telegram: Sent`. Its
detail displayed the full synthetic message and Reply by email. No live sign-in
code or session token was captured. The test is retained for the user’s review:
[open the test message](https://regencommons.com/council#messages/35fd97d9-8189-4da9-9c29-a54ca5c10406).
The screenshot is a local, uncommitted synthetic-data artifact.

Hosted readback confirmed RLS is enabled, anonymous SELECT is denied, clients
cannot INSERT, and the worker lease is excluded from authenticated column
grants. The active-steward policy uses the existing role/session check. Live
anonymous HTTP returned 401 with private/no-store caching for the inbox, 405 for
a contact listing, and 401 for an unauthenticated agent notification. The
rendered council browser had no warnings/errors. Deployment-scoped error/fatal
log counts were empty during the immediate verification window.

Supabase advisors reported no contact-table finding. They also reported internal
tables with RLS and no client policies, plus the project’s
[disabled leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
Those are outside this contact migration; no Auth settings were changed.

If an application rollback is needed, the prior website deployment is
`dpl_ELNk2mmzUvBGF4VFsx5uxtWhkPqc` and prior agent deployment is
`dpl_79m6J3G2J9wKGaqMoE8LJS2TWAfr`. Retain the contact table and saved
correspondence rather than dropping data to roll back an application release.

## Podcast form verification — 13 November 2026

Not deployed. No hosted schema, environment or agent change is involved, and no
live submission was made.

`npm run check`, all 93 tests and `npm run smoke` pass. The five podcast tests
cover the composed subject and message, the rejected cases, the length budget,
a save through the actual contact handler into the fixture council inbox, and
the page's scripts and navigation links.

Rendered local fixtures in the Claude desktop app's built-in Chromium browser
show the page at 1280px in both themes and at 390px in the dark theme. Measured
at 390px and 320px, nothing overflows horizontally. An empty submit moves focus to the first interest with a message, a
missing name moves it to the name field, and Enter submits. An injected 503
keeps the draft and a second submit saves it. The fixture council inbox lists
`Podcast: guest, question` and its detail shows the interests, the note and
Reply by email. The About form saves and re-enables after an edit as before.
Space toggles an interest and Tab reaches every control in order. The page adds
no motion of its own; it uses the shared background canvas and button styles.
Fixture mode sends no email or Telegram messages.
