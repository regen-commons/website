# Contact messages

The About form saves private correspondence in `public.contact_messages`. Active
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

The hosted migration, both deployments and real Telegram delivery have not been
performed in this work. The prior website and agent can continue operating while
the new code is reviewed.

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
