import { membershipReceipt, membershipDecision } from "./membership-email.js";
import {
  resendFailure,
  transportFailure,
  resendMessageId,
} from "./notification-result.js";

const escapeHtml = (value) =>
  String(value || "").replace(
    /[&<>"']/g,
    (char) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        char
      ],
  );
function mailBody(title, text, url) {
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td style="padding:24px"><table role="presentation" width="100%" style="max-width:560px;font-family:Georgia,serif;line-height:1.6;color:#26352b"><tr><td style="padding:24px"><h1>${escapeHtml(title)}</h1><p>${escapeHtml(text)}</p>${url ? `<p><a href="${escapeHtml(url)}">Open membership request</a></p>` : ""}<p>Regen Commons</p></td></tr></table></td></tr></table>`;
}
export async function drainNotifications({
  claim,
  finish,
  request = fetch,
  env = process.env,
  applicationId = null,
}) {
  const jobs = await claim(applicationId);
  const results = await Promise.allSettled(
    jobs.map(async (job) => {
      let status = "skipped";
      const result = {
        provider_message_id: null,
        failure_code: "resend_not_configured",
      };
      try {
        const origin = env.ADMIN_ORIGIN;
        const url = origin
          ? `${origin}/admin#applications/${job.application_id}`
          : null;
        if (job.channel === "telegram") {
          result.failure_code = "notification_not_configured";
          if (env.NOTIFY_URL && env.NOTIFY_WEBHOOK_SECRET) {
            const response = await request(env.NOTIFY_URL, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${env.NOTIFY_WEBHOOK_SECRET}`,
              },
              body: JSON.stringify({
                type: "application",
                text: `New membership request: ${job.name} (${job.member_type})`,
                ...(url ? { url } : {}),
              }),
              redirect: "manual",
              signal: AbortSignal.timeout(8000),
            });
            status = response.ok ? "sent" : "needs_review";
            result.failure_code = response.ok ? null : "notification_rejected";
          }
        } else if (env.RESEND_API_KEY && env.RESEND_FROM_EMAIL) {
          const recipients = ["receipt", "decision"].includes(job.channel)
            ? [job.email]
            : (env.STEWARD_NOTIFY_EMAILS || "")
                .split(",")
                .map((s) => s.trim())
                .filter(Boolean);
          result.failure_code = "recipients_not_configured";
          if (recipients.length) {
            const applicant = ["receipt", "decision"].includes(job.channel);
            const message =
              job.channel === "decision"
                ? membershipDecision(job)
                : job.channel === "receipt"
                  ? membershipReceipt(job.name)
                  : {
                      subject: "New Regen Commons membership request",
                      html: mailBody(
                        "New membership request",
                        `${job.name} has submitted a membership request.`,
                        url,
                      ),
                    };
            const response = await request("https://api.resend.com/emails", {
              method: "POST",
              headers: {
                Authorization: `Bearer ${env.RESEND_API_KEY}`,
                "Content-Type": "application/json",
                "Idempotency-Key": `membership/${job.id}`,
              },
              body: JSON.stringify({
                from: `Regen Commons <${env.RESEND_FROM_EMAIL}>`,
                to: recipients,
                ...message,
                ...(applicant
                  ? {
                      reply_to:
                        env.RESEND_REPLY_TO_EMAIL || "regencommons@gmail.com",
                    }
                  : {}),
              }),
              signal: AbortSignal.timeout(8000),
            });
            status = "failed";
            result.failure_code = response.ok
              ? "resend_invalid_response"
              : resendFailure(response.status);
            // An error response may echo private input. Do not persist or log it.
            if (response.ok) {
              const data = await response.json().catch(() => null);
              if (resendMessageId(data?.id)) {
                status = "sent";
                result.provider_message_id = data.id;
                result.failure_code = null;
              }
            }
          }
        }
      } catch (error) {
        status = job.channel === "telegram" ? "needs_review" : "failed";
        result.failure_code = transportFailure(error);
      }
      await finish(job, status, result);
    }),
  );
  if (results.some((result) => result.status === "rejected"))
    throw new Error("notification_status_update_failed");
}
