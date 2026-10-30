import assert from "node:assert/strict";
import { once } from "node:events";
import { after, test } from "node:test";
import { randomUUID } from "node:crypto";
import { createLocalServer } from "../scripts/lib/local-server.js";

const server = createLocalServer();
server.listen(0, "127.0.0.1");
await once(server, "listening");
const base = `http://127.0.0.1:${server.address().port}`;
after(async () => {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
});
const get = (path, cookie) =>
  fetch(base + path, { headers: cookie ? { cookie } : {} });
const post = (path, body, cookie, extra = {}) =>
  fetch(base + path, {
    method: "POST",
    headers: {
      Origin: base,
      "Content-Type": "application/json",
      ...(cookie ? { cookie } : {}),
      ...extra,
    },
    body: JSON.stringify(body),
  });
async function signIn() {
  await post("/api/admin", {
    action: "request-code",
    email: "steward@example.test",
  });
  const response = await post("/api/admin", {
    action: "verify-code",
    email: "steward@example.test",
    code: "123456",
  });
  assert.equal(response.status, 200);
  return response.headers.get("set-cookie").split(";")[0];
}
test("a public seed appears in the desk; hide/restore affects public reads with recorded history", async () => {
  const key = randomUUID(),
    text = "A synthetic vision for community forests";
  assert.equal(
    (
      await post("/api/seeds", { text, author: "Demo" }, null, {
        "Idempotency-Key": key,
      })
    ).status,
    200,
  );
  assert.equal(
    (
      await post("/api/seeds", { text, author: "Demo" }, null, {
        "Idempotency-Key": key,
      })
    ).status,
    200,
  );
  assert.equal(
    (
      await post("/api/seeds", { text: "Changed request" }, null, {
        "Idempotency-Key": key,
      })
    ).status,
    409,
  );
  const cookie = await signIn(),
    listing = await (
      await get("/api/admin?resource=seeds&search=community", cookie)
    ).json();
  assert.equal(listing.items.length, 1);
  const seed = listing.items[0];
  assert.equal(seed.publication_state, "published");
  const moderation = {
    action: "moderate",
    resource: "seeds",
    id: seed.id,
    revision: 1,
    state: "hidden",
    reason: "Synthetic moderation review",
  };
  assert.equal(
    (await post("/api/admin", { ...moderation, reason: "" }, cookie)).status,
    400,
  );
  assert.equal((await post("/api/admin", moderation)).status, 401);
  assert.equal(
    (
      await post("/api/admin", moderation, cookie, {
        Origin: "https://other.example.test",
      })
    ).status,
    403,
  );
  assert.equal((await post("/api/admin", moderation, cookie)).status, 200);
  assert.equal((await post("/api/admin", moderation, cookie)).status, 409);
  assert.ok(
    !(await (await get("/api/seeds")).json()).seeds.some(
      (s) => s.id === seed.id,
    ),
  );
  const detail = await (
    await get(`/api/admin?resource=content&kind=seeds&id=${seed.id}`, cookie)
  ).json();
  assert.equal(detail.history[0].action, "hidden");
  assert.equal(detail.history[0].reason, moderation.reason);
  assert.ok(detail.history[0].actor_id);
  assert.equal(
    (
      await post(
        "/api/admin",
        {
          ...moderation,
          revision: 2,
          state: "published",
          reason: "Reviewed and restored",
        },
        cookie,
      )
    ).status,
    200,
  );
  const publicRead = await get("/api/seeds");
  assert.equal(publicRead.headers.get("cache-control"), "no-store");
  assert.equal(
    (await publicRead.json()).seeds.filter((s) => s.id === seed.id).length,
    1,
  );
});
test("contribution creation is immediately public and repeatable; edits preserve hidden state", async () => {
  const cookie = await signIn(),
    members = await (await get("/api/admin?resource=members", cookie)).json();
  const organization = members.members.find(
      (m) => m.member_type === "organization",
    ),
    draft = members.members.find((m) => m.publication_state === "draft");
  const body = {
    action: "save-contribution",
    request_id: randomUUID(),
    payload: {
      title: "Synthetic orchard guide",
      description: "Community knowledge",
      tags: ["Orchards"],
      capital_forms: ["Intellectual"],
      contributor_ids: [organization.id, draft.id],
    },
  };
  const first = await post("/api/admin", body, cookie);
  assert.equal(first.status, 200);
  const { id } = await first.json();
  assert.equal((await post("/api/admin", body, cookie)).status, 200);
  let published = (await (await get("/api/contributions")).json())
    .contributions;
  assert.equal(published.filter((c) => c.id === id).length, 1);
  assert.deepEqual(published.find((c) => c.id === id).contributors, [
    { id: organization.id, name: organization.name },
  ]);
  assert.equal(
    (
      await post(
        "/api/admin",
        {
          ...body,
          payload: { ...body.payload, title: "Changed identity payload" },
        },
        cookie,
      )
    ).status,
    409,
  );
  assert.equal(
    (
      await post(
        "/api/admin",
        {
          action: "moderate",
          resource: "contributions",
          id,
          revision: 1,
          state: "hidden",
          reason: "Check license",
        },
        cookie,
      )
    ).status,
    200,
  );
  assert.equal(
    (
      await post(
        "/api/admin",
        {
          ...body,
          request_id: randomUUID(),
          id,
          revision: 2,
          payload: { ...body.payload, title: "Revised orchard guide" },
        },
        cookie,
      )
    ).status,
    200,
  );
  published = (await (await get("/api/contributions")).json()).contributions;
  assert.ok(!published.some((c) => c.id === id));
  const detail = await (
    await get(`/api/admin?resource=content&kind=contributions&id=${id}`, cookie)
  ).json();
  assert.equal(detail.item.publication_state, "hidden");
  assert.equal(detail.item.revision, 3);
  assert.equal(detail.history.length, 3);
  assert.equal(
    (
      await post(
        "/api/admin",
        {
          action: "moderate",
          resource: "contributions",
          id,
          revision: 3,
          state: "published",
          reason: "License checked",
        },
        cookie,
      )
    ).status,
    200,
  );
  assert.ok(
    (await (await get("/api/contributions")).json()).contributions.some(
      (c) => c.title === "Revised orchard guide",
    ),
  );
});
test("membership requests remain private and arrive in the same Supabase fixture queue", async () => {
  const body = {
    "full-name": "Synthetic new organization",
    email: "org@example.test",
    "applicant-type": "organization",
    "closing-notes": "Private original answer",
  };
  const headers = { "Idempotency-Key": randomUUID() };
  assert.equal((await post("/api/apply", body, null, headers)).status, 200);
  assert.equal((await post("/api/apply", body, null, headers)).status, 200);
  const cookie = await signIn(),
    queue = await (
      await get(
        "/api/admin?resource=applications&search=Synthetic%20new",
        cookie,
      )
    ).json();
  assert.equal(queue.total, 1);
  assert.equal(queue.applications[0].applicant_type, "organization");
  assert.doesNotMatch(
    JSON.stringify(queue),
    /Private original answer|org@example.test/,
  );
  const privateRead = await (
    await get(
      `/api/admin?resource=application&id=${queue.applications[0].id}`,
      cookie,
    )
  ).json();
  assert.equal(
    privateRead.application.original_answers["closing-notes"],
    body["closing-notes"],
  );
  assert.ok(
    !(await (await get("/api/members")).json()).members.some(
      (m) => m.name === body["full-name"],
    ),
  );
});
