const NOTIFY_URL = process.env.NOTIFY_URL;
const NOTIFY_SECRET = process.env.NOTIFY_WEBHOOK_SECRET;

export async function notifyTelegram(payload) {
  if (!NOTIFY_URL || !NOTIFY_SECRET) return;
  const res = await fetch(NOTIFY_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${NOTIFY_SECRET}`,
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`notify failed (${res.status}): ${body}`);
  }
}
