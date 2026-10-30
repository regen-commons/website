import assert from "node:assert/strict";
import { test } from "node:test";
import { drainNotifications } from "../api/_lib/intake-notifications.js";
import { createWebsiteHandler } from "../api/_lib/public-data.js";
import { membershipReceipt } from "../api/_lib/membership-email.js";

test("membership receipts confirm saved requests and pending review in HTML and text", () => {
  const message = membershipReceipt('<A name & "organization">');
  assert.match(message.html, /&lt;A name &amp; &quot;organization&quot;&gt;/);
  for (const body of [message.html, message.text]) {
    assert.match(body, /membership request has been saved/);
    assert.match(body, /Membership is still subject to steward review/);
    assert.match(body, /https:\/\/regencommons.com\/map/);
    assert.doesNotMatch(body, /admin#|Welcome as a member|original_answers/);
  }
  assert.match(message.html, /<td[^>]*padding:28px;/);
  assert.doesNotMatch(message.html, /<script|<link|<canvas|<form|@import/i);
  assert.match(membershipReceipt(null).text, /Thank you for reaching out/);
});

test("successful receipt uses the verified sender, reply inbox and one applicant only", async () => {
  let requestBody, requestHeaders;
  const finished = [];
  await drainNotifications({
    env: {
      RESEND_API_KEY: "synthetic-key",
      RESEND_FROM_EMAIL: "membership@example.test",
      RESEND_REPLY_TO_EMAIL: "replies@example.test",
      STEWARD_NOTIFY_EMAILS: "steward@example.test",
      ADMIN_ORIGIN: "https://admin.example.test",
    },
    claim: async () => [{
      id: "receipt-job", lease_id: "lease", application_id: "application",
      channel: "receipt", name: "Synthetic Applicant", email: "person@example.test",
      original_answers: { private_notes: "Private test answer must stay private" },
    }],
    finish: async (job, status) => finished.push({ id: job.id, status }),
    request: async (url, options) => {
      assert.equal(url, "https://api.resend.com/emails");
      requestBody = JSON.parse(options.body);
      requestHeaders = options.headers;
      return new Response('{"id":"synthetic-provider-id"}', { status: 200 });
    },
  });
  assert.deepEqual(finished, [{ id: "receipt-job", status: "sent" }]);
  assert.equal(requestHeaders["Idempotency-Key"], "membership/receipt-job");
  assert.equal(requestBody.from, "Regen Commons <membership@example.test>");
  assert.equal(requestBody.reply_to, "replies@example.test");
  assert.deepEqual(requestBody.to, ["person@example.test"]);
  assert.match(requestBody.text, /Your request is in/);
  assert.doesNotMatch(JSON.stringify(requestBody), /Private test answer|admin\.example|steward@example/);
});

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
