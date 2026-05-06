const NOTIFY_URL = (process.env.NOTIFY_URL || "").trim();
const NOTIFY_SECRET = (process.env.NOTIFY_WEBHOOK_SECRET || "").trim();

export async function notifyTelegram(payload) {
  if (!NOTIFY_URL || !NOTIFY_SECRET) {
    console.warn("[notify] skipped — env vars missing", {
      hasUrl: Boolean(NOTIFY_URL),
      hasSecret: Boolean(NOTIFY_SECRET),
    });
    return;
  }

  console.log("[notify] POST", JSON.stringify(NOTIFY_URL));

  const res = await fetch(NOTIFY_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${NOTIFY_SECRET}`,
    },
    body: JSON.stringify(payload),
    redirect: "manual",
  });

  console.log("[notify] response", res.status);

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`notify failed (${res.status}): ${body}`);
  }
}
