import assert from "node:assert/strict";
import { once } from "node:events";
import { after, test } from "node:test";
import { createLocalServer } from "../scripts/lib/local-server.js";
import { createStewardFixtures } from "../scripts/lib/steward-fixtures.js";
import { createAdminHandler } from "../api/admin.js";
import {
  AdminError,
  createSupabaseProvider,
} from "../api/_lib/steward-data.js";

let fixtureTime = Date.now();
const provider = createStewardFixtures({ now: () => fixtureTime });
const server = createLocalServer({ stewardProvider: provider });
server.listen(0, "127.0.0.1");
await once(server, "listening");
const base = `http://127.0.0.1:${server.address().port}`;
after(async () => {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
});
const read = (query = "", cookie = "") =>
  fetch(`${base}/api/admin${query}`, { headers: { Cookie: cookie } });
const post = (body, cookie = "", headers = {}) =>
  fetch(`${base}/api/admin`, {
    method: "POST",
    headers: {
      Origin: base,
      "Content-Type": "application/json",
      Cookie: cookie,
      ...headers,
    },
    body: JSON.stringify(body),
  });
async function signIn(email = "steward@example.test") {
  assert.equal((await post({ action: "request-code", email })).status, 200);
  return post({ action: "verify-code", email, code: "123456" });
}
const sessionCookie = (response) =>
  response.headers.get("set-cookie").split(";")[0];

test("private routes reject missing and forged sessions, and never allow public caching", async () => {
  for (const query of [
    "",
    "?resource=applications",
    `?resource=application&id=${provider.ids.application}`,
    "?resource=members",
  ]) {
    for (const cookie of ["", "regen_steward=forged"]) {
      const response = await read(query, cookie);
      assert.equal(response.status, 401);
      assert.match(response.headers.get("cache-control"), /no-store/);
      assert.equal(
        response.headers.get("vercel-cdn-cache-control"),
        "no-store",
      );
      assert.doesNotMatch(
        await response.text(),
        /River|private demo|original_answers/i,
      );
    }
  }
});

test("email codes require a request, reject bad/reused codes, and cannot create or authorize visitors", async () => {
  assert.equal(
    (
      await post({
        action: "verify-code",
        email: "steward@example.test",
        code: "123456",
      })
    ).status,
    401,
  );
  await post({ action: "request-code", email: "steward@example.test" });
  assert.equal(
    (
      await post({
        action: "verify-code",
        email: "steward@example.test",
        code: "000000",
      })
    ).status,
    401,
  );
  const response = await post({
    action: "verify-code",
    email: "steward@example.test",
    code: "123456",
  });
  assert.equal(response.status, 200);
  assert.match(response.headers.get("set-cookie"), /HttpOnly; SameSite=Strict/);
  assert.doesNotMatch(await response.text(), /access_token|refresh_token/);
  assert.equal(
    (
      await post({
        action: "verify-code",
        email: "steward@example.test",
        code: "123456",
      })
    ).status,
    401,
  );
  assert.equal((await signIn("visitor@example.test")).status, 403);
  assert.equal((await signIn("unknown@example.test")).status, 401);
});

test("authorized review filters summaries and keeps original answers out of profile projections", async () => {
  const cookie = sessionCookie(await signIn());
  const queue = await (
    await read(
      "?resource=applications&search=river&type=individual&state=pending",
      cookie,
    )
  ).json();
  assert.equal(queue.total, 1);
  assert.equal(queue.applications[0].id, provider.ids.application);
  assert.doesNotMatch(
    JSON.stringify(queue),
    /original_answers|email|constraints/,
  );
  assert.equal(
    (
      await (
        await read("?resource=applications&type=organization", cookie)
      ).json()
    ).total,
    1,
  );
  assert.equal(
    (await (await read("?resource=applications&search=nomatch", cookie)).json())
      .total,
    0,
  );
  const detail = await (
    await read(`?resource=application&id=${provider.ids.application}`, cookie)
  ).json();
  assert.match(detail.application.original_answers.constraints, /Private demo/);
  assert.equal(detail.profile.publication_state, "draft");
  assert.equal(detail.application.review_state, "pending");
  assert.doesNotMatch(
    JSON.stringify(detail.profile),
    /email|constraints|private|original_answers/i,
  );
  assert.equal(detail.history[0].event_type, "demo_capture");
  const members = await (await read("?resource=members", cookie)).json();
  assert.equal(
    members.affiliations[0].organization_id,
    provider.ids.organization,
  );
  assert.equal(members.contributionMembers[0].member_id, provider.ids.person);
  assert.equal(members.contributions[0].publication_state, "draft");
  assert.equal(
    (
      await read(
        "?resource=application&id=10000000-0000-4000-8000-000000000099",
        cookie,
      )
    ).status,
    404,
  );
  assert.equal(
    (await read("?resource=application&id=bad-id", cookie)).status,
    400,
  );
  assert.equal(
    (await read("?resource=applications&offset=-1", cookie)).status,
    400,
  );
});

test("revocation takes effect with an existing session and sign-out invalidates it", async () => {
  const cookie = sessionCookie(await signIn());
  provider.setActive("steward@example.test", false);
  for (const resource of ["session", "applications", "members"])
    assert.equal((await read(`?resource=${resource}`, cookie)).status, 403);
  provider.setActive("steward@example.test", true);
  const signout = await post({ action: "sign-out" }, cookie);
  assert.equal(signout.status, 200);
  assert.match(signout.headers.get("set-cookie"), /Max-Age=0/);
  assert.equal((await read("?resource=applications", cookie)).status, 401);
});

test("API rejects cross-origin, malformed and unsupported actions; no decision writes exist", async () => {
  const cookie = sessionCookie(await signIn());
  assert.equal(
    (
      await post(
        { action: "request-code", email: "steward@example.test" },
        "",
        { Origin: "https://evil.example" },
      )
    ).status,
    403,
  );
  assert.equal(
    (
      await post(
        { action: "request-code", email: "steward@example.test" },
        "",
        { Origin: "" },
      )
    ).status,
    403,
  );
  assert.equal(
    (await post({ action: "verify-code", email: {}, code: "123456" })).status,
    400,
  );
  for (const action of ["accept", "publish", "grant-role"])
    assert.equal((await post({ action }, cookie)).status, 400);
  assert.equal(
    (await fetch(`${base}/api/admin`, { method: "DELETE" })).status,
    405,
  );
  assert.equal(
    (await read("?resource=applications&type=admin", cookie)).status,
    400,
  );
});

test("production cookies are secure and missing configuration fails closed", async () => {
  const headers = {};
  const res = {
    setHeader: (key, value) => {
      headers[key] = value;
    },
    status(code) {
      this.code = code;
      return this;
    },
    json(body) {
      this.body = body;
    },
  };
  const handler = createAdminHandler({
    origin: "https://commons.example",
    provider: () => provider,
  });
  await provider.requestCode("steward@example.test");
  await handler(
    {
      method: "POST",
      url: "/api/admin",
      headers: {
        origin: "https://commons.example",
        "content-type": "application/json",
      },
      body: {
        action: "verify-code",
        email: "steward@example.test",
        code: "123456",
      },
    },
    res,
  );
  assert.equal(res.code, 200);
  assert.match(
    headers["Set-Cookie"],
    /^__Host-regen_steward=.+; Path=\/; HttpOnly; SameSite=Strict; Max-Age=3600; Secure$/,
  );
  assert.throws(() => createSupabaseProvider({}), /admin_not_configured/);
});

test("the real Supabase SDK disables signup and uses a user-scoped database request", async () => {
  const calls = [];
  const db = createSupabaseProvider({
    url: "https://synthetic.supabase.co",
    key: "sb_publishable_synthetic",
    request: async (url, options) => {
      calls.push({ url: String(url), options });
      const body = String(url).includes("/user")
        ? { id: "synthetic-user", email: "steward@example.test" }
        : String(url).includes("/rpc/")
          ? true
          : {};
      return new Response(JSON.stringify(body), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    },
  });
  await db.requestCode("steward@example.test");
  assert.equal(JSON.parse(calls[0].options.body).create_user, false);
  assert.equal(
    (await db.authorize("synthetic-user-token")).id,
    "synthetic-user",
  );
  const rpc = calls.find((call) => call.url.includes("/rpc/steward_access"));
  assert.equal(
    new Headers(rpc.options.headers).get("Authorization"),
    "Bearer synthetic-user-token",
  );
  assert.equal(
    new Headers(rpc.options.headers).get("apikey"),
    "sb_publishable_synthetic",
  );
});

test("provider failure is unavailable, not empty data or a successful login", async () => {
  const db = createSupabaseProvider({
    url: "https://synthetic.supabase.co",
    key: "sb_publishable_synthetic",
    request: async () =>
      new Response('{"message":"synthetic failure"}', {
        status: 403,
        headers: { "content-type": "application/json" },
      }),
  });
  await assert.rejects(
    db.applications("token", { search: "", state: "", type: "", offset: 0 }),
    (error) => error.status === 503,
  );
  await assert.rejects(
    db.requestCode("steward@example.test"),
    (error) => error.status === 503,
  );
});

test("Auth outages and throttling remain retryable instead of invalidating credentials", async () => {
  for (const [status, expectedStatus, code] of [
    [503, 503, "provider_unavailable"],
    [429, 429, "rate_limited"],
  ]) {
    const db = createSupabaseProvider({
      url: "https://synthetic.supabase.co",
      key: "sb_publishable_synthetic",
      request: async () =>
        new Response('{"message":"synthetic failure"}', {
          status,
          headers: { "content-type": "application/json" },
        }),
    });
    for (const operation of [
      () => db.verifyCode("steward@example.test", "123456"),
      () => db.authorize("synthetic-user-token"),
    ]) {
      await assert.rejects(
        operation,
        (error) => error.status === expectedStatus && error.message === code,
      );
    }
  }
});

test("database throttling preserves the provider's HTTP status", async () => {
  const db = createSupabaseProvider({
    url: "https://synthetic.supabase.co",
    key: "sb_publishable_synthetic",
    request: async () =>
      new Response('{"message":"synthetic throttle","code":"429"}', {
        status: 429,
        headers: { "content-type": "application/json" },
      }),
  });
  await assert.rejects(
    db.applications("token", { search: "", state: "", type: "", offset: 0 }),
    (error) => error.status === 429 && error.message === "rate_limited",
  );
});

test("sign-out clears already invalid sessions while preserving real provider failures", async () => {
  for (const status of [204, 401, 403, 404, 503]) {
    const db = createSupabaseProvider({
      url: "https://synthetic.supabase.co",
      key: "sb_publishable_synthetic",
      request: async () => new Response(null, { status }),
    });
    if (status === 503) {
      await assert.rejects(
        db.signOut("expired-token"),
        (error) => error.status === 503,
      );
    } else {
      await db.signOut("expired-token");
    }
  }
});

test("the membership queue places dated requests ahead of imported unknown dates", async () => {
  let order;
  const db = createSupabaseProvider({
    url: "https://synthetic.supabase.co",
    key: "sb_publishable_synthetic",
    request: async (url) => {
      order = new URL(url).searchParams.get("order");
      return new Response("[]", {
        headers: { "content-type": "application/json", "content-range": "*/0" },
      });
    },
  });
  await db.applications("synthetic-token", {
    search: "",
    state: "",
    type: "",
    offset: 0,
  });
  assert.equal(order, "submitted_at.desc.nullslast,id.asc");
});

test("transient Auth responses do not clear the browser session cookie", async () => {
  for (const status of [503, 429]) {
    const db = createSupabaseProvider({
      url: "https://synthetic.supabase.co",
      key: "sb_publishable_synthetic",
      request: async () =>
        new Response('{"message":"synthetic failure"}', {
          status,
          headers: { "content-type": "application/json" },
        }),
    });
    const handler = createAdminHandler({
      origin: "https://commons.example",
      provider: () => db,
    });
    for (const method of ["GET", "POST"]) {
      const response = {
        headers: {},
        setHeader(key, value) {
          this.headers[key] = value;
        },
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
          method,
          url: "/api/admin",
          headers: {
            cookie: "__Host-regen_steward=synthetic-token",
            origin: "https://commons.example",
            "content-type": "application/json",
          },
          body: {
            action: "verify-code",
            email: "steward@example.test",
            code: "123456",
          },
        },
        response,
      );
      assert.equal(response.code, status);
      assert.equal(response.headers["Set-Cookie"], undefined);
      assert.doesNotMatch(
        JSON.stringify(response.body),
        /invalid_code|sign_in_required|access_token/,
      );
    }
  }
});

test("expired codes and sessions fail through the handler", async () => {
  await post({ action: "request-code", email: "steward@example.test" });
  fixtureTime += 600000;
  assert.equal(
    (
      await post({
        action: "verify-code",
        email: "steward@example.test",
        code: "123456",
      })
    ).status,
    401,
  );
  const cookie = sessionCookie(await signIn());
  fixtureTime += 3600000;
  const response = await read("?resource=applications", cookie);
  assert.equal(response.status, 401);
  assert.doesNotMatch(await response.text(), /River|original_answers/);
});

test("a failed sign-out retains the session only for a retry and never reports success", async () => {
  const local = createStewardFixtures();
  await local.requestCode("steward@example.test");
  const { token } = await local.verifyCode("steward@example.test", "123456");
  let fail = true;
  const handler = createAdminHandler({
    origin: "https://commons.example",
    provider: () => ({
      ...local,
      async signOut(token) {
        if (fail) {
          fail = false;
          throw new AdminError(503, "sign_out_failed");
        }
        return local.signOut(token);
      },
    }),
  });
  const req = {
    method: "POST",
    url: "/api/admin",
    headers: {
      cookie: `__Host-regen_steward=${token}`,
      origin: "https://commons.example",
      "content-type": "application/json",
    },
    body: { action: "sign-out" },
  };
  const response = () => ({
    headers: {},
    setHeader(key, value) {
      this.headers[key] = value;
    },
    status(code) {
      this.code = code;
      return this;
    },
    json(body) {
      this.body = body;
    },
  });
  const first = response();
  await handler(req, first);
  assert.equal(first.code, 503);
  assert.equal(first.body.error, "sign_out_failed");
  assert.equal(first.headers["Set-Cookie"], undefined);
  const retry = response();
  await handler(req, retry);
  assert.equal(retry.code, 200);
  assert.match(retry.headers["Set-Cookie"], /Max-Age=0/);
  await assert.rejects(local.authorize(token), (error) => error.status === 401);
});
