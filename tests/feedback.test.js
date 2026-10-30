import assert from "node:assert/strict";
import { test, after } from "node:test";
import { once } from "node:events";
import { randomUUID } from "node:crypto";
import { feedbackPayload, feedbackCategories } from "../feedback-contract.js";
import { createLocalServer } from "../scripts/lib/local-server.js";

const server = createLocalServer();
server.listen(0, "127.0.0.1");
await once(server, "listening");
const base = `http://127.0.0.1:${server.address().port}`;
after(async () => {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
});
const post = (body, key = randomUUID()) =>
  fetch(base + "/api/feedback", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Idempotency-Key": key },
    body: JSON.stringify(body),
  });
const valid = {
  message: "Synthetic private feedback",
  categories: ["Idea", "Bug"],
  page_path: "/map",
};

test("feedback preserves text and categories and rejects invalid or external context", () => {
  assert.deepEqual(
    feedbackPayload({
      ...valid,
      message: "  Shared care 🌱  ",
      categories: ["Idea", "Idea"],
    }),
    { message: "Shared care 🌱", categories: ["Idea"], page_path: "/map" },
  );
  assert.equal(feedbackCategories.length, 7);
  for (const body of [
    { ...valid, message: "  " },
    { ...valid, message: "x".repeat(5001) },
    { ...valid, categories: ["unsupported"] },
    { ...valid, page_path: "https://example.test/" },
    { ...valid, page_path: "//example.test" },
    { ...valid, page_path: "/map?private=value" },
  ])
    assert.throws(() => feedbackPayload(body), /invalid_feedback/);
});
test("private feedback intake supports safe retries, conflicts and no public listing", async () => {
  const key = randomUUID();
  assert.equal((await post(valid, key)).status, 200);
  assert.equal((await post(valid, key)).status, 200);
  assert.equal(
    (await post({ ...valid, message: "Changed payload" }, key)).status,
    409,
  );
  assert.equal((await fetch(base + "/api/feedback")).status, 405);
  assert.equal((await post({ ...valid, message: "" })).status, 400);
  for (const resource of ["members", "contributions", "seeds"]) {
    const response = await fetch(base + `/api/${resource}`);
    assert.doesNotMatch(await response.text(), /Synthetic private feedback/);
  }
});
test("feedback quota and honeypot do not create unbounded public intake", async () => {
  assert.equal((await post({ ...valid, website_confirm: "bot" })).status, 200);
  assert.equal((await post(valid)).status, 200);
  assert.equal((await post(valid)).status, 200);
  assert.equal((await post(valid)).status, 429);
});
