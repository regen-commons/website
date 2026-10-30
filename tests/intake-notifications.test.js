import assert from "node:assert/strict";
import { test } from "node:test";
import { drainNotifications } from "../api/_lib/intake-notifications.js";
import { createWebsiteHandler } from "../api/_lib/public-data.js";
test("notification errors stay separate from a confirmed application save", async () => {
  let saved = false;
  const handler = createWebsiteHandler("apply", {
    provider: () => ({
      async submit() {
        saved = true;
        return { id: "synthetic-id" };
      },
      async drain() {
        throw new Error("Synthetic mail outage");
      },
    }),
  });
  const response = {
    setHeader() {},
    status(value) {
      this.code = value;
      return this;
    },
    json(body) {
      this.body = body;
    },
  };
  await handler(
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: { "full-name": "Synthetic Person", email: "person@example.test" },
    },
    response,
  );
  assert.equal(saved, true);
  assert.equal(response.code, 200);
  assert.deepEqual(response.body, { ok: true });
});
test("receipt delivery checks provider errors and uses stable identities without exposing private answers", async () => {
  const job = {
    id: "synthetic-job",
    lease_id: "synthetic-lease",
    application_id: "synthetic-application",
    channel: "receipt",
    name: "<Synthetic person>",
    email: "person@example.test",
  };
  const delivered = [],
    requests = [];
  await drainNotifications({
    env: {
      RESEND_API_KEY: "synthetic-key",
      RESEND_FROM_EMAIL: "membership@example.test",
    },
    claim: async () => [job],
    finish: async (j, status) => delivered.push(status),
    request: async (url, options) => {
      requests.push({ url, options });
      return new Response('{"message":"synthetic rejected mail"}', {
        status: 422,
      });
    },
  });
  assert.deepEqual(delivered, ["failed"]);
  assert.equal(
    requests[0].options.headers["Idempotency-Key"],
    "membership/synthetic-job",
  );
  const body = JSON.parse(requests[0].options.body);
  assert.match(body.html, /&lt;Synthetic person&gt;/);
  assert.doesNotMatch(body.html, /<Synthetic person>|original_answers/);
});
test("uncertain Telegram delivery requests review instead of an automatic duplicate", async () => {
  let state;
  await drainNotifications({
    env: {
      NOTIFY_URL: "https://notify.example.test",
      NOTIFY_WEBHOOK_SECRET: "synthetic-secret",
    },
    claim: async () => [
      {
        id: "demo",
        channel: "telegram",
        name: "Synthetic person",
        member_type: "individual",
      },
    ],
    finish: async (job, status) => {
      state = status;
    },
    request: async () => {
      throw new Error("Uncertain result");
    },
  });
  assert.equal(state, "needs_review");
});
