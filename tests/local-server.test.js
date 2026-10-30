import assert from "node:assert/strict";
import { once } from "node:events";
import { get } from "node:http";
import { readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { after, test } from "node:test";

// Prove inherited integration configuration cannot turn local tests into live writes.
process.env.NOTION_TOKEN = "must-be-replaced";
process.env.NOTIFY_URL = "https://example.test/must-not-be-called";
process.env.NOTIFY_WEBHOOK_SECRET = "must-be-removed";
process.env.RESEND_API_KEY = "must-be-removed";
process.env.SUPABASE_URL = "https://must-not-be-called.example.test";
process.env.SUPABASE_PUBLISHABLE_KEY = "must-be-removed";
process.env.SUPABASE_SERVICE_ROLE_KEY = "must-be-removed";
const { createLocalServer } = await import("../scripts/lib/local-server.js");
const server = createLocalServer();
server.listen(0, "127.0.0.1");
await once(server, "listening");
const base = `http://127.0.0.1:${server.address().port}`;
after(async () => {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
});
const request = (path, options) => fetch(base + path, options);
const post = (path, body) => request(path, {
  method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
});

test("fixture mode replaces credentials and reports its limits", async () => {
  assert.equal(process.env.NOTION_TOKEN, "local-fixture-token");
  for (const key of ["NOTIFY_URL", "NOTIFY_WEBHOOK_SECRET", "RESEND_API_KEY", "SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "SUPABASE_SERVICE_ROLE_KEY"]) assert.equal(process.env[key], undefined);
  assert.deepEqual(await (await request("/__dev/health")).json(), {
    ok: true, mode: "fixture", persistence: "memory", externalWrites: false,
  });
});

test("the launcher reports an occupied port and preserves the existing server", async () => {
  const child = spawnSync(process.execPath, [fileURLToPath(new URL("../scripts/dev.js", import.meta.url))], {
    env: { ...process.env, PORT: String(server.address().port) },
    encoding: "utf8", timeout: 10000,
  });
  assert.equal(child.error, undefined);
  assert.equal(child.status, 1);
  assert.match(child.stderr, /is occupied/);
  assert.equal((await request("/__dev/health")).status, 200);
});

test("public pages and clean routes work; private files and foreign origins do not", async () => {
  for (const path of ["/", "/learn", "/map.html", "/seeds/", "/join?step=1"]) {
    const response = await request(path);
    assert.equal(response.status, 200, path);
    assert.match(await response.text(), /Local demo · synthetic data/);
  }
  for (const path of ["/.env.local", "/.git/config", "/package.json", "/api/_lib/notion.js", "/scripts/dev.js", "/missing"]) {
    assert.equal((await request(path)).status, 404, path);
  }
  const foreignHostStatus = await new Promise((resolve, reject) => {
    get(base, { headers: { Host: "example.test" } }, (response) => {
      response.resume();
      resolve(response.statusCode);
    }).on("error", reject);
  });
  assert.equal(foreignHostStatus, 403);
  assert.equal((await request("/api/seeds", { headers: { Origin: "https://example.test" } })).status, 403);
});

test("actual read handlers exclude pending members and private fields, and resolve contributors", async () => {
  const response = await request("/api/members");
  assert.equal(response.headers.get("cache-control"), "no-store");
  const { members } = await response.json();
  assert.equal(members.length, 2);
  assert.ok(members.every((member) => member.status === "Active"));
  assert.doesNotMatch(JSON.stringify(members), /private-|pending@example|Email|Telegram/);
  const { contributions } = await (await request("/api/contributions")).json();
  assert.equal(contributions[0].contributors[0].name, "Demo Gardener");
});

test("unsupported methods, malformed JSON, and oversized bodies fail clearly", async () => {
  const method = await request("/api/apply");
  assert.equal(method.status, 405);
  assert.equal(method.headers.get("allow"), "POST");
  assert.equal((await request("/api/seeds", { method: "POST", body: "text" })).status, 415);
  assert.equal((await request("/api/seeds", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: "{",
  })).status, 400);
  assert.equal((await post("/api/seeds", null)).status, 400);
  assert.equal((await post("/api/seeds", { text: "x".repeat(9000) })).status, 413);
});

test("seed validation and honeypot run in the actual handler; accepted seeds are readable", async () => {
  assert.equal((await post("/api/seeds", { text: "x" })).status, 400);
  assert.equal((await post("/api/seeds", { text: "x".repeat(241) })).status, 400);
  assert.equal((await post("/api/seeds", { text: "A synthetic new seed" })).status, 200);
  assert.equal((await post("/api/seeds", { text: "Bot seed", website_confirm: "spam" })).status, 200);
  const { seeds } = await (await request("/api/seeds")).json();
  assert.ok(seeds.some((seed) => seed.text === "A synthetic new seed"));
  assert.ok(!seeds.some((seed) => seed.text === "Bot seed"));
});

test("application validation, pending publication gate, and rate limiting use actual handlers", async () => {
  assert.equal((await post("/api/apply", {})).status, 400);
  assert.equal((await post("/api/apply", { "full-name": "Demo", email: "invalid" })).status, 400);
  const body = { "full-name": "New Demo Applicant", email: "new@example.test" };
  assert.deepEqual(await (await post("/api/apply", body)).json(), { ok: true });
  const { members } = await (await request("/api/members")).json();
  assert.ok(!members.some((member) => member.name === body["full-name"]));
  assert.equal((await post("/api/apply", body)).status, 429);
});

test("local scenarios distinguish empty/error data and allow recovery without live calls", async () => {
  const scenario = (name) => request(`/__dev/scenario?name=${name}`, { method: "POST" });
  try {
    await scenario("empty");
    assert.deepEqual(await (await request("/api/members")).json(), { members: [] });
    assert.deepEqual(await (await request("/api/contributions")).json(), { contributions: [] });
    await scenario("error-once");
    assert.equal((await request("/api/members")).status, 503);
    assert.equal((await request("/api/members")).status, 200);
    assert.equal((await request("/api/contributions")).status, 503);
    assert.equal((await request("/api/contributions")).status, 200);
    await scenario("rate-limit-once");
    assert.equal((await post("/api/seeds", { text: "An artificial rejection" })).status, 429);
    await scenario("offline");
    await assert.rejects(request("/api/members"), TypeError);
    await assert.rejects(post("/api/seeds", { text: "An unconfirmed draft" }), TypeError);
    assert.equal((await scenario("not-a-scenario")).status, 400);
  } finally {
    await scenario("normal");
  }
  assert.equal((await request("/api/members")).status, 200);
});

test("self-hosted fonts are served as unchanged binary assets", async () => {
  const path = "assets/fonts/fraunces-latin.woff2";
  const response = await request("/" + path);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "font/woff2");
  const bytes = Buffer.from(await response.arrayBuffer());
  assert.equal(bytes.subarray(0, 4).toString(), "wOF2");
  assert.deepEqual(bytes, await readFile(new URL("../" + path, import.meta.url)));
  assert.equal((await request("/favicon.svg")).headers.get("content-type"), "image/svg+xml");
});

test("static text supports gzip without changing the document or font bytes", async () => {
  const plain = await request("/style.css", { headers: { "Accept-Encoding": "identity" } });
  assert.equal(plain.headers.get("content-encoding"), null);
  const compressed = await request("/style.css", { headers: { "Accept-Encoding": "gzip" } });
  assert.equal(compressed.headers.get("content-encoding"), "gzip");
  assert.equal(compressed.headers.get("vary"), "Accept-Encoding");
  assert.equal(await compressed.text(), await plain.text());
  const declined = await request("/style.css", { headers: { "Accept-Encoding": "gzip;q=0" } });
  assert.equal(declined.headers.get("content-encoding"), null);
  const weighted = await request("/style.css", { headers: { "Accept-Encoding": "br, gzip;q=0.5" } });
  assert.equal(weighted.headers.get("content-encoding"), "gzip");
  assert.equal((await request("/assets/fonts/fraunces-latin.woff2")).headers.get("content-encoding"), null);
});
