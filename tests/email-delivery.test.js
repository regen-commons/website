import assert from "node:assert/strict";
import { once } from "node:events";
import { test } from "node:test";
import { createLocalServer } from "../scripts/lib/local-server.js";
import { createStewardFixtures } from "../scripts/lib/steward-fixtures.js";
import { createSupabaseProvider } from "../api/_lib/steward-data.js";
import { createPublicProvider } from "../api/_lib/public-data.js";

const application_id = "10000000-0000-4000-8000-000000000001";
const job_id = "50000000-0000-4000-8000-000000000001";
async function fixture(run, options) {
  const provider = createStewardFixtures(options);
  const server = createLocalServer({ stewardProvider: provider });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const base = `http://127.0.0.1:${server.address().port}`;
  const post = (body, cookie = "", origin = base) =>
    fetch(`${base}/api/admin`, {
      method: "POST",
      headers: {
        Origin: origin,
        Cookie: cookie,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
  const read = (id, cookie = "") =>
    fetch(`${base}/api/admin?resource=email-deliveries&id=${id}`, {
      headers: { Cookie: cookie },
    });
  try {
    await post({ action: "request-code", email: "steward@example.test" });
    const login = await post({
      action: "verify-code",
      email: "steward@example.test",
      code: "123456",
    });
    const cookie = login.headers.get("set-cookie").split(";")[0];
    await run({ provider, post, read, cookie });
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
}

test("private email status, retry validation and duplicate clicks use the current steward session", async () => {
  await fixture(async ({ post, read, cookie, provider }) => {
    const command = {
      action: "retry-email",
      application_id,
      job_id,
      attempts: 1,
    };
    assert.equal((await read(application_id)).status, 401);
    assert.equal((await post(command)).status, 401);
    assert.equal(
      (await post(command, cookie, "https://other.example.test")).status,
      403,
    );
    assert.equal(
      (await post({ ...command, attempts: -1 }, cookie)).status,
      400,
    );
    assert.equal(
      (await post({ ...command, application_id: "invalid" }, cookie)).status,
      400,
    );
    assert.equal(
      (
        await post(
          {
            ...command,
            application_id: "10000000-0000-4000-8000-000000000003",
          },
          cookie,
        )
      ).status,
      404,
    );
    const before = await read(application_id, cookie);
    assert.match(before.headers.get("cache-control"), /no-store/);
    const ledger = await before.json();
    assert.equal(
      ledger.notifications[0].failure_code,
      "resend_authentication_failed",
    );
    assert.doesNotMatch(
      JSON.stringify(ledger),
      /lease_id|original_answers|secret|@/,
    );
    const clicks = await Promise.all([
      post(command, cookie),
      post(command, cookie),
    ]);
    assert.deepEqual(clicks.map((r) => r.status).sort(), [200, 409]);
    const sent = (await (await read(application_id, cookie)).json())
      .notifications[0];
    assert.equal(sent.status, "sent");
    assert.equal(sent.attempts, 2);
    assert.match(sent.provider_message_id, /^[a-f0-9-]{36}$/);
    assert.equal(sent.failure_code, null);
    assert.equal((await post({ ...command, attempts: 2 }, cookie)).status, 409);
    const empty = await (
      await read("10000000-0000-4000-8000-000000000003", cookie)
    ).json();
    assert.deepEqual(empty, { notifications: [] });
    provider.setActive("steward@example.test", false);
    assert.equal((await read(application_id, cookie)).status, 403);
    assert.equal((await post(command, cookie)).status, 403);
  });
});

test("failed retries retain a safe reason and stop at the attempt and time limits", async () => {
  await fixture(
    async ({ post, read, cookie }) => {
      for (const attempts of [1, 2])
        assert.equal(
          (
            await post(
              { action: "retry-email", application_id, job_id, attempts },
              cookie,
            )
          ).status,
          200,
        );
      const failed = (await (await read(application_id, cookie)).json())
        .notifications[0];
      assert.equal(failed.status, "failed");
      assert.equal(failed.failure_code, "resend_unavailable");
      assert.equal(failed.retry_block, "retry_limit_reached");
      assert.equal(
        (
          await post(
            { action: "retry-email", application_id, job_id, attempts: 3 },
            cookie,
          )
        ).status,
        409,
      );
      const expired = await post(
        {
          action: "retry-email",
          application_id: "10000000-0000-4000-8000-000000000002",
          job_id: "50000000-0000-4000-8000-000000000003",
          attempts: 2,
        },
        cookie,
      );
      assert.equal(expired.status, 409);
      assert.equal((await expired.json()).error, "retry_window_expired");
    },
    { retryFailure: true },
  );
});

test("the adapter claims with the user session and records Resend results with the server capability", async () => {
  const calls = [],
    providerId = "60000000-0000-4000-8000-000000000009";
  const provider = createSupabaseProvider({
    url: "https://synthetic.supabase.co",
    key: "sb_publishable_synthetic",
    env: {
      SUPABASE_INTAKE_SECRET: "synthetic-intake-secret",
      RESEND_API_KEY: "synthetic-resend-secret",
      RESEND_FROM_EMAIL: "membership@example.test",
    },
    request: async (url, options) => {
      calls.push({ url: String(url), options, body: JSON.parse(options.body) });
      if (String(url).includes("/retry_notification"))
        return Response.json({
          id: job_id,
          lease_id: "lease",
          application_id,
          channel: "receipt",
          email: "saved@example.test",
          name: "Synthetic Person",
        });
      if (String(url) === "https://api.resend.com/emails")
        return Response.json({ id: providerId });
      return Response.json([]);
    },
  });
  await provider.retryNotification("synthetic-user-token", {
    application_id,
    job_id,
    attempts: 1,
    email: "forged@example.test",
  });
  for (const call of calls.filter((c) => c.url.includes("/rpc/"))) {
    const authorization = new Headers(call.options.headers).get(
      "Authorization",
    );
    if (call.url.includes("/notification_result")) {
      assert.notEqual(authorization, "Bearer synthetic-user-token");
      assert.equal(call.body.p_secret, "synthetic-intake-secret");
    } else {
      assert.equal(authorization, "Bearer synthetic-user-token");
      assert.equal(call.body.p_secret, undefined);
    }
    assert.doesNotMatch(
      JSON.stringify(call.body),
      /synthetic-resend-secret|forged@example/,
    );
  }
  const send = calls.find((c) => c.url === "https://api.resend.com/emails");
  assert.deepEqual(send.body.to, ["saved@example.test"]);
  assert.equal(send.options.headers["Idempotency-Key"], `membership/${job_id}`);
  const complete = calls.find((c) => c.url.includes("/notification_result"));
  assert.equal(complete.body.p_provider_message_id, providerId);
  assert.equal(complete.body.p_failure_code, null);
});

test("automatic receipt processing stores the provider result through the bounded worker credential", async () => {
  const calls = [],
    messageId = "60000000-0000-4000-8000-000000000010";
  const provider = createPublicProvider({
    url: "https://synthetic.supabase.co",
    key: "sb_publishable_synthetic",
    secret: "synthetic-intake-secret",
    env: {
      RESEND_API_KEY: "synthetic-resend-secret",
      RESEND_FROM_EMAIL: "membership@example.test",
    },
    request: async (url, options) => {
      const body = JSON.parse(options.body);
      calls.push({ url: String(url), body });
      if (String(url).includes("/notification_work"))
        return Response.json([
          {
            id: job_id,
            lease_id: "lease",
            application_id,
            channel: "receipt",
            name: "Synthetic Person",
            email: "saved@example.test",
          },
        ]);
      if (String(url) === "https://api.resend.com/emails")
        return Response.json({ id: messageId });
      return Response.json([]);
    },
  });
  await provider.drain(application_id);
  const result = calls.find((c) => c.url.includes("/notification_result"));
  assert.equal(result.body.p_status, "sent");
  assert.equal(result.body.p_provider_message_id, messageId);
  assert.equal(result.body.p_failure_code, null);
  assert.equal(result.body.p_secret, "synthetic-intake-secret");
  assert.equal(result.body.p_lease, "lease");
  assert.doesNotMatch(
    JSON.stringify(result.body),
    /synthetic-resend-secret|saved@example/,
  );
});

test("accepted results are recorded even if the steward session expires during the send", async () => {
  let sent = false,
    recorded = false;
  const provider = createSupabaseProvider({
    url: "https://synthetic.supabase.co",
    key: "sb_publishable_synthetic",
    env: {
      SUPABASE_INTAKE_SECRET: "synthetic-intake-secret",
      RESEND_API_KEY: "synthetic",
      RESEND_FROM_EMAIL: "sender@example.test",
    },
    request: async (url, options) => {
      const path = String(url),
        user =
          new Headers(options.headers).get("Authorization") ===
          "Bearer expires-during-send";
      if (sent && user)
        return Response.json(
          { message: "Expired session", code: "PGRST301" },
          { status: 401 },
        );
      if (path.includes("/retry_notification"))
        return Response.json({
          id: job_id,
          lease_id: "lease",
          application_id,
          channel: "receipt",
          email: "saved@example.test",
        });
      if (path === "https://api.resend.com/emails") {
        sent = true;
        return Response.json({ id: "60000000-0000-4000-8000-000000000011" });
      }
      if (path.includes("/notification_result")) {
        recorded = true;
        return Response.json([]);
      }
      return Response.json([]);
    },
  });
  await assert.rejects(
    provider.retryNotification("expires-during-send", {
      application_id,
      job_id,
      attempts: 1,
    }),
  );
  assert.equal(
    recorded,
    true,
    "A later read may fail, but the provider outcome must already be saved",
  );
});

test("missing retry completion capability fails before consuming an attempt", async () => {
  const provider = createSupabaseProvider({
    url: "https://synthetic.supabase.co",
    key: "synthetic",
    env: {},
    request: () => {
      throw new Error("Must not claim or send");
    },
  });
  await assert.rejects(
    provider.retryNotification("user", { application_id, job_id, attempts: 1 }),
    (error) =>
      error.status === 503 && error.message === "email_retry_not_configured",
  );
});
