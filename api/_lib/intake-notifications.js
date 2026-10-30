import { membershipReceipt } from "./membership-email.js";

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
  if (
    !(env.RESEND_API_KEY && env.RESEND_FROM_EMAIL) &&
    !(env.NOTIFY_URL && env.NOTIFY_WEBHOOK_SECRET)
  )
    return;
  const jobs = await claim(applicationId);
  const results = await Promise.allSettled(
    jobs.map(async (job) => {
      let status = "skipped";
      try {
        const origin = env.ADMIN_ORIGIN;
        const url = origin
          ? `${origin}/admin#applications/${job.application_id}`
          : null;
        if (job.channel === "telegram") {
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
          }
        } else if (env.RESEND_API_KEY && env.RESEND_FROM_EMAIL) {
          const recipients =
            job.channel === "receipt"
              ? [job.email]
              : (env.STEWARD_NOTIFY_EMAILS || "")
                  .split(",")
                  .map((s) => s.trim())
                  .filter(Boolean);
          if (recipients.length) {
            const receipt = job.channel === "receipt";
            const message = receipt
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
                ...(receipt
                  ? { reply_to: env.RESEND_REPLY_TO_EMAIL || "regencommons@gmail.com" }
                  : {}),
              }),
              signal: AbortSignal.timeout(8000),
            });
            const data = await response.json();
            status =
              response.ok && typeof data.id === "string" ? "sent" : "failed";
          }
        }
      } catch {
        status = job.channel === "telegram" ? "needs_review" : "failed";
      }
      await finish(job, status);
    }),
  );
  if (results.some((result) => result.status === "rejected"))
    throw new Error("notification_status_update_failed");
}
