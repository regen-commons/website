import { Webhook } from "svix";
import { createPublicProvider } from "./_lib/public-data.js";
import { resendMessageId } from "./_lib/notification-result.js";

const outcomes = new Map([
  ["email.delivered", "delivered"],
  ["email.bounced", "bounced"],
]);
const maxBytes = 64 * 1024;

export function createResendWebhookHandler({ secret, sender, record }) {
  return async (req, res) => {
    res.setHeader("Cache-Control", "no-store");
    const reply = (status, body) => {
      res.writeHead(status, { "Content-Type": "application/json" });
      res.end(JSON.stringify(body));
    };
    if (req.method !== "POST") {
      res.setHeader("Allow", "POST");
      return reply(405, { error: "method_not_allowed" });
    }
    if (!secret || !sender)
      return reply(503, { error: "webhook_not_configured" });

    const headers = Object.fromEntries(
      ["svix-id", "svix-timestamp", "svix-signature"].map((name) => [
        name,
        req.headers[name],
      ]),
    );
    if (!Object.values(headers).every((value) => typeof value === "string" && value))
      return reply(400, { error: "invalid_webhook" });

    let event;
    try {
      // Vercel's parsed req.body is a lazy getter. Read the stream instead:
      // the signed bytes must not be reconstructed from parsed JSON.
      const chunks = [];
      let size = 0;
      for await (const chunk of req.iterator({ destroyOnReturn: false })) {
        size += chunk.length;
        if (size > maxBytes) {
          req.resume();
          return reply(413, { error: "body_too_large" });
        }
        chunks.push(chunk);
      }
      const body = Buffer.concat(chunks);
      new Webhook(secret).verify(body, headers);
      event = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(body));
    } catch {
      return reply(400, { error: "invalid_webhook" });
    }

    const outcome = outcomes.get(event?.type);
    const from = event?.data?.from;
    const address = typeof from === "string"
      ? (from.match(/<([^<>]+)>\s*$/)?.[1] ?? from).trim().toLowerCase()
      : null;
    if (!outcome || address !== sender.trim().toLowerCase())
      return reply(200, { ok: true });

    const id = event.data.email_id;
    const at = event.created_at;
    if (!resendMessageId(id) || typeof at !== "string" ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$/.test(at) ||
      !Number.isFinite(Date.parse(at)))
      return reply(400, { error: "invalid_webhook_event" });

    try {
      await record({ id, outcome, at });
    } catch {
      // Resend retries non-2xx responses. Never log payloads or credentials.
      console.warn("resend_delivery_record_failed");
      return reply(503, { error: "delivery_store_unavailable" });
    }
    return reply(200, { ok: true });
  };
}

export default function handler(req, res) {
  return createResendWebhookHandler({
    secret: process.env.RESEND_WEBHOOK_SECRET,
    sender: process.env.RESEND_FROM_EMAIL,
    record: (event) =>
      createPublicProvider({
        url: process.env.SUPABASE_URL,
        key: process.env.SUPABASE_PUBLISHABLE_KEY,
        secret: process.env.SUPABASE_INTAKE_SECRET,
      }).recordEmailDelivery(event),
  })(req, res);
}

export const config = { api: { bodyParser: false } };
