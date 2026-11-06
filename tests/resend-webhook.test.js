import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import { test } from "node:test";
import { Webhook } from "svix";
import { createResendWebhookHandler } from "../api/resend-webhook.js";
import { createPublicProvider } from "../api/_lib/public-data.js";

const secret = `whsec_${Buffer.alloc(32, 7).toString("base64")}`;
const sender = "membership@example.test";
const id = "60000000-0000-4000-8000-000000000001";
const at = "2026-10-30T10:00:00.123456Z";

test("signed delivery and bounce events over HTTP record only allowlisted fields", async (t) => {
  const writes = [];
  let unavailable = false;
  const provider = createPublicProvider({
    url: "https://database.example.test",
    key: "synthetic-key",
    secret: "synthetic-intake-capability",
    request: async (url, options) => {
      assert.equal(String(url), "https://database.example.test/rest/v1/rpc/record_email_delivery");
      assert.equal(options.method, "POST");
      if (unavailable) return new Response("temporarily unavailable", { status: 503 });
      writes.push(JSON.parse(options.body));
      return new Response(null, { status: 204 });
    },
  });
  const server = createServer(createResendWebhookHandler({
    secret, sender, record: (event) => provider.recordEmailDelivery(event),
  }));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const url = `http://127.0.0.1:${server.address().port}/api/resend-webhook`;
  const webhook = new Webhook(secret);
  const event = (type, from = `Regen Commons <${sender}>`, email_id = id) =>
    JSON.stringify({
      type,
      created_at: at,
      data: {
        from, email_id, to: ["applicant@example.test"],
        bounce: { message: "raw SMTP error is private" },
        subject: "private subject",
      },
    }, null, 2);
  const post = async (body, { signed = body, age = 0, unsigned = false } = {}) => {
    const stamp = new Date(Date.now() - age);
    const msgId = "msg_synthetic";
    const headers = unsigned ? {} : {
      "svix-id": msgId,
      "svix-timestamp": String(Math.floor(stamp.getTime() / 1000)),
      "svix-signature": webhook.sign(msgId, stamp, signed),
    };
    const response = await fetch(url, {
      method: "POST", headers: { ...headers, "Content-Type": "application/json" }, body,
    });
    assert.equal(response.headers.get("cache-control"), "no-store");
    await response.json();
    return response.status;
  };
  const delivered = event("email.delivered");
  const bounced = event("email.bounced");
  assert.equal((await fetch(url)).status, 405);
  assert.equal(await post(delivered, { unsigned: true }), 400);
  assert.equal(await post(delivered + " ", { signed: delivered }), 400);
  assert.equal(await post(delivered, { age: 600_000 }), 400);
  assert.equal(await post(" ".repeat(65_537)), 413);
  assert.equal(await post(event("email.delivered", sender, "invalid")), 400);
  assert.equal(await post(event("email.opened")), 200);
  assert.equal(await post(event("email.bounced", "login@example.test")), 200);
  assert.deepEqual(writes, []);
  unavailable = true;
  assert.equal(await post(delivered), 503);
  unavailable = false;
  assert.equal(await post(delivered), 200);
  assert.equal(await post(bounced), 200);
  assert.deepEqual(writes, ["delivered", "bounced"].map((outcome) => ({
    p_secret: "synthetic-intake-capability",
    p_provider_message_id: id,
    p_outcome: outcome,
    p_occurred_at: at,
  })));
});
