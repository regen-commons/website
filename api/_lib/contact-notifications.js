// Contact text and reply addresses stay in the council dashboard.
export async function deliverContactNotifications({
  claim,
  finish,
  request = fetch,
  env = process.env,
}) {
  // Leave jobs pending until delivery is configured.
  if (!env.NOTIFY_URL || !env.NOTIFY_WEBHOOK_SECRET || !env.ADMIN_ORIGIN)
    return;
  const origin = new URL(env.ADMIN_ORIGIN);
  if (origin.protocol !== "https:") throw new Error("invalid_council_origin");
  const jobs = await claim();
  const results = await Promise.allSettled(
    jobs.map(async (job) => {
      let status = "needs_review";
      try {
        const response = await request(env.NOTIFY_URL, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${env.NOTIFY_WEBHOOK_SECRET}`,
          },
          body: JSON.stringify({
            type: "contact",
            text: "A new contact message is ready for the steward council to review.",
            url: `${origin.origin}/council#messages/${job.id}`,
          }),
          redirect: "manual",
          signal: AbortSignal.timeout(8000),
        });
        const result = await response.json().catch(() => null);
        if (response.ok && result?.ok === true) status = "sent";
      } catch {
        /* Delivery may have happened. Keep uncertain sends for review. */
      }
      await finish(job, status);
    }),
  );
  if (results.some((result) => result.status === "rejected"))
    throw new Error("contact_notification_status_update_failed");
}
