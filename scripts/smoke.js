import assert from "node:assert/strict";
import { once } from "node:events";
import { createLocalServer } from "./lib/local-server.js";
import { publicFiles, pages } from "./lib/site-files.js";

const server = createLocalServer();
server.listen(0, "127.0.0.1");
await once(server, "listening");
const base = `http://127.0.0.1:${server.address().port}`;
try {
  for (const file of publicFiles) {
    const response = await fetch(`${base}/${file}`);
    assert.equal(response.status, 200, file);
    assert.equal(response.headers.get("x-regen-data"), "fixture");
    await response.text();
  }
  for (const name of ["members", "contributions", "seeds"]) {
    const response = await fetch(`${base}/api/${name}`);
    assert.equal(response.status, 200, name);
    assert.ok((await response.json())[name].length > 0, name);
  }
  const seed = "Synthetic smoke-test seed";
  const planted = await fetch(`${base}/api/seeds`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ text: seed }),
  });
  assert.equal(planted.status, 200);
  const seeds = await (await fetch(`${base}/api/seeds`)).json();
  assert.ok(seeds.seeds.some((item) => item.text === seed));
  const application = await fetch(`${base}/api/apply`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ "full-name": "Smoke Applicant", email: "smoke@example.test" }),
  });
  assert.equal(application.status, 200);
  const members = await (await fetch(`${base}/api/members`)).json();
  assert.ok(!members.members.some((item) => item.name === "Smoke Applicant"));
  assert.equal((await fetch(`${base}/api/admin?resource=applications`)).status, 401);
  const authPost = (body) => fetch(`${base}/api/admin`, { method: "POST", headers: { Origin: base, "Content-Type": "application/json" }, body: JSON.stringify(body) });
  assert.equal((await authPost({ action: "request-code", email: "steward@example.test" })).status, 200);
  const login = await authPost({ action: "verify-code", email: "steward@example.test", code: "123456" });
  assert.equal(login.status, 200);
  const reviewed = await fetch(`${base}/api/admin?resource=applications`, { headers: { Cookie: login.headers.get("set-cookie").split(";")[0] } });
  assert.equal((await reviewed.json()).applications.length, 3);
  console.log(`Smoke passed: ${pages.length} pages, assets, public API reads/writes, publication gate, steward login and authorized queue.`);
  console.log("Evidence: local HTTP + actual handlers with fixture transport; external services and rendered UI are not covered.");
} finally {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
}
