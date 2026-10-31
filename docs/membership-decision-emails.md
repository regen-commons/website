# Membership decision emails

This draft adds applicant emails for approved, declined, and changes_requested
application decisions. It is separate from public-site polish. The new migration
is tested locally and has not been applied to production.

## Steward workflow

Choose a decision in the application detail. The form shows the applicant's
email address and a separate message field. That message is required when
requesting changes and optional for approval or decline. The private review
reason remains required and is never included in the email. The submit button
states that it records the decision and emails the applicant. Reopening sends no
email. Applicants reply to the configured Reply-To address; this release does not
add a member account, an application editing link, or automated reply ingestion.

Approval, membership standing, and profile visibility remain independent. Email
copy reports the application outcome and does not claim that membership is active
or a profile has been published. No prior application or review event is emailed
automatically, including imported applications. A new explicit decision can queue
mail for an imported application.

## Persistence and delivery

The review command saves the decision, its audit event, the applicant-facing
message, and one private notification job in the same transaction. A repeated
command returns the same job. A changed command with the same identity is
rejected. Existing receipt/steward/Telegram identities remain unique per
application; decision jobs are unique per review event.

The job snapshots the recipient, applicant name, decision, public message, and
template version. A retry uses that snapshot rather than current application
fields. Version 1 copy stays stable for queued jobs; future copy changes require
a new version without removing the old renderer while retries remain possible.
Private reasons and original application answers never enter the message.

After committing, the server attempts the new job under the initiating steward's
current authorization. Failure to dispatch does not reverse a saved decision.
The dashboard displays each decision's revision, status, Resend ID, safe failure
reason, and send/retry action alongside intake email records. It uses the existing
server-held completion capability to record provider outcomes after session
expiry. Clients cannot supply delivery results, recipients, or email content to
the retry action.

Decision jobs use the existing three-attempt limit and 24-hour Resend idempotency
window, with a one-minute safety margin. An uncertain send is retried with the
same job identity. A newer review decision or reopening supersedes older unsent
jobs. Profile linking does not supersede a decision. Claims lock the application
before the job so decisions and claims have a consistent order. A provider call
already in flight cannot be recalled; its outcome remains recordable.

This release attempts delivery in the decision request and exposes manual
recovery. It does not add a scheduled dispatcher. Anonymous intake draining
cannot claim decision emails. A pending job after an interrupted request can be
recovered by replaying the original command or by an active steward's send action.
Resend acceptance confirms a send request; inbox delivery and bounces remain
outside the dashboard's tracking contract.

## Design and verification

Receipts and decision emails share one HTML shell using the website's light
parchment/forest palette, serif headings, text wordmark, inline styles, table-cell
padding, and a plain-text alternative. All names and public messages are escaped
for HTML. Replies use RESEND_REPLY_TO_EMAIL with the existing fallback. Sender
configuration is unchanged; no new domain or DNS records are needed.

Run npm run check, npm test, npm run smoke, and the six disposable SQL suites.
The decision-email-access.sql suite verifies atomic queueing, no backfill,
authorization, replay, private/public message separation, immutable snapshots,
and supersession. Broad synthetic Auth and role tests belong only in a disposable
database. The PR records actual browser and provider evidence separately.

Generate synthetic previews with node scripts/preview-membership-decisions.js.
It writes ignored HTML/text/JSON artifacts and has no sending capability. Real
delivery QA uses explicitly labeled test messages to the user-authorized address;
it does not record a real membership decision or enable production automation.

Release requires a separately authorized migration, matching runtime deployment,
and verification of automatic dispatch against temporary applications. An older
client cannot create a new email-bearing decision without the explicit
applicant_message field. Previously committed command replays retain their old
result and create no new message.
