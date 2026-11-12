import assert from "node:assert/strict";
import { after, test } from "node:test";
import { once } from "node:events";
import { randomUUID } from "node:crypto";
import { createLocalServer } from "../scripts/lib/local-server.js";
import { createStewardFixtures } from "../scripts/lib/steward-fixtures.js";
import {
  createWebsiteHandler,
  createPublicProvider,
} from "../api/_lib/public-data.js";
import { contactPayload } from "../contact-contract.js";
import { deliverContactNotifications } from "../api/_lib/contact-notifications.js";
const provider = createStewardFixtures();
const server = createLocalServer({ stewardProvider: provider });
server.listen(0, "127.0.0.1");
await once(server, "listening");
const base = `http://127.0.0.1:${server.address().port}`;
after(async () => {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
});
const valid = {
  name: "Synthetic Visitor",
  email: "visitor@example.test",
  subject: "A possible collaboration",
  message: "Private synthetic message <script>hello</script>",
};
const post = (body, key = randomUUID()) =>
  fetch(base + "/api/contact", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Idempotency-Key": key },
    body: JSON.stringify(body),
  });
async function signIn() {
  const send = (body) =>
    fetch(base + "/api/admin", {
      method: "POST",
      headers: { Origin: base, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  await send({ action: "request-code", email: "steward@example.test" });
  const response = await send({
    action: "verify-code",
    email: "steward@example.test",
    code: "123456",
  });
  return response.headers.get("set-cookie").split(";")[0];
}
test("contact validates required fields, types, email, lengths and normalizes the reply address", () => {
  assert.equal(
    contactPayload({ ...valid, email: " Person@Example.test " }).email,
    "person@example.test",
  );
  for (const input of [
    null,
    [],
    ...["name", "email", "subject", "message"].flatMap((field) => [
      { ...valid, [field]: " " },
      { ...valid, [field]: [] },
    ]),
    { ...valid, email: "bad@email" },
    { ...valid, name: "x".repeat(201) },
    { ...valid, subject: "x".repeat(201) },
    { ...valid, message: "🌱".repeat(2501) },
  ])
    assert.throws(() => contactPayload(input), /invalid_contact/);
});
test("contact saves once, keeps details private, and is visible only through authorized council reads", async () => {
  const key = randomUUID();
  assert.equal((await post(valid, key)).status, 200);
  assert.equal((await post(valid, key)).status, 200);
  assert.equal(
    (await post({ ...valid, message: "Changed message" }, key)).status,
    409,
  );
  assert.equal((await fetch(base + "/api/contact")).status, 405);
  for (const resource of ["members", "seeds", "contributions"])
    assert.doesNotMatch(
      await (await fetch(base + "/api/" + resource)).text(),
      /Private synthetic message/,
    );
  assert.equal(
    (await fetch(base + "/api/admin?resource=messages")).status,
    401,
  );
  const cookie = await signIn();
  const read = (query) =>
    fetch(base + "/api/admin?" + query, { headers: { Cookie: cookie } });
  const response = await read("resource=messages");
  assert.match(response.headers.get("cache-control"), /no-store/);
  const list = await response.json();
  assert.equal(list.total, 1);
  assert.doesNotMatch(JSON.stringify(list), /visitor@example|<script>/);
  const detail = await (
    await read("resource=message&id=" + list.items[0].id)
  ).json();
  assert.equal(detail.message.message, valid.message);
  assert.equal(detail.message.email, valid.email);
  assert.equal((await read("resource=message&id=" + randomUUID())).status, 404);
  assert.equal((await read("resource=messages&offset=-1")).status, 400);
  provider.setActive("steward@example.test", false);
  assert.equal((await read("resource=messages")).status, 403);
  assert.equal(
    (await read("resource=message&id=" + list.items[0].id)).status,
    403,
  );
  provider.setActive("steward@example.test", true);
});
test("contact rejects malformed input, respects the quota and ignores a filled honeypot", async () => {
  assert.equal((await post({ ...valid, message: "" })).status, 400);
  assert.equal((await post({ ...valid, website_confirm: "bot" })).status, 200);
  assert.equal((await post(valid)).status, 200);
  assert.equal((await post(valid)).status, 200);
  assert.equal((await post(valid)).status, 429);
});
test("a contact save succeeds even when Telegram processing fails, and a failed save never notifies", async () => {
  for (const failSave of [false, true]) {
    let notified = false;
    const handler = createWebsiteHandler("contact", {
      provider: () => ({
        async submit() {
          if (failSave) throw new Error("synthetic outage");
          return { id: "saved" };
        },
        async drainContact(id) {
          assert.equal(id, "saved");
          notified = true;
          throw new Error("synthetic Telegram outage");
        },
      }),
    });
    const response = {
      setHeader() {},
      status(code) {
        this.code = code;
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
        body: valid,
      },
      response,
    );
    assert.equal(response.code, failSave ? 503 : 200);
    assert.equal(notified, !failSave);
  }
});
test("contact provider calls the bounded RPC and hashes the network address", async () => {
  let body;
  const db = createPublicProvider({
    url: "https://synthetic.supabase.co",
    key: "synthetic-key",
    secret: "synthetic-secret",
    request: async (url, options) => {
      assert.match(String(url), /rpc\/submit_contact$/);
      body = JSON.parse(options.body);
      assert.ok(options.signal);
      return Response.json({ ok: true, id: "saved" });
    },
  });
  await db.submit("contact", randomUUID(), valid, "192.0.2.1");
  assert.equal(body.p_kind, undefined);
  assert.equal(body.p_payload.message, valid.message);
  assert.match(body.p_actor_hash, /^[a-f0-9]{64}$/);
  assert.doesNotMatch(JSON.stringify(body), /192\.0\.2\.1/);
});
test("Telegram contacts carry only an inbox link and record confirmed versus uncertain delivery", async () => {
  for (const mode of ["sent", "rejected", "timeout", "malformed"]) {
    let result;
    await deliverContactNotifications({
      env: {
        NOTIFY_URL: "https://agent.example.test/api/notify",
        NOTIFY_WEBHOOK_SECRET: "synthetic-secret",
        ADMIN_ORIGIN: "https://commons.example.test",
      },
      claim: async () => [{ id: "message-id", notification_lease: "lease" }],
      finish: async (job, status) => {
        result = status;
      },
      request: async (url, options) => {
        const body = JSON.parse(options.body);
        assert.equal(body.type, "contact");
        assert.equal(
          body.url,
          "https://commons.example.test/council#messages/message-id",
        );
        assert.doesNotMatch(
          options.body,
          /visitor@example|Private synthetic|collaboration/,
        );
        assert.ok(options.signal);
        if (mode === "timeout") throw new Error("synthetic timeout");
        return mode === "malformed"
          ? Response.json({})
          : Response.json(
              { ok: mode === "sent" },
              { status: mode === "rejected" ? 500 : 200 },
            );
      },
    });
    assert.equal(result, mode === "sent" ? "sent" : "needs_review");
  }
});
test("unconfigured contact notifications remain pending without claiming or sending", async () => {
  await deliverContactNotifications({
    env: {},
    claim: () => assert.fail("claimed unconfigured job"),
    finish: () => assert.fail("finished unconfigured job"),
    request: () => assert.fail("external request"),
  });
});
