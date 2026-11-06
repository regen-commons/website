# Membership email delivery webhooks

The steward desk shows **Delivered** or **Bounced** on membership receipts and
decision emails when Resend reports that outcome. Delivered means the
recipient's mail server accepted the message. It does not confirm inbox
placement. An accepted send with no event continues to show **Accepted by
Resend**. Bounces include the event time and a link to inspect details in
Resend. They do not reopen the existing send retry action or change the
application decision, member standing, or profile visibility.

## Enable on a deployment

1. Apply the delivery outcome migration to that deployment's Supabase project.
2. In [Resend Webhooks](https://resend.com/webhooks), register the deployment's
   publicly reachable HTTPS `/api/resend-webhook` URL for `email.delivered` and
   `email.bounced`. Use a separate endpoint for a test deployment. Keep it
   disabled until the deployment has its signing secret.
3. Store the endpoint's signing secret as `RESEND_WEBHOOK_SECRET` in the matching
   server environment and redeploy. The receiver also uses the existing
   Supabase URL, publishable key, intake capability and `RESEND_FROM_EMAIL`.
4. Enable the endpoint. Send a labeled test receipt and decision to the
   authorized test inbox, then refresh the application’s email status. Check
   the Resend message ID, dashboard outcome and webhook HTTP 200 response.
   Use [Resend's bounce simulator](https://resend.com/changelog/sending-test-emails)
   in a test environment for the bounce path; do not provoke a bounce at a real
   inbox. Replay one event in Resend and verify that the status stays the same.

Do not use production credentials or applications for preview testing. To
pause tracking, disable the endpoint in Resend. Sending remains independent.
Previously sent messages keep their existing status until a matching event is
received. There is no historical backfill.

## Data handling

The endpoint checks the original signed bytes and the signature timestamp
before processing events. It accepts delivery and bounce events for the
configured sender. The database keeps one outcome and event time per Resend
message ID, so a webhook can arrive before send completion. Duplicate events
are harmless. The newest provider event wins; a bounce wins an exact timestamp
tie. Only matching receipt and decision records are shown to active stewards.
Recipient addresses, SMTP responses, subjects, and raw payloads are not
stored in the outcome table. Events without a matching job remain private.

If Supabase is unavailable, the endpoint returns 503 so Resend can retry.
See [Resend's replay instructions](https://resend.com/docs/webhooks/retries-and-replays)
to recover a missed event.
