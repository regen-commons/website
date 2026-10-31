import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { once } from "node:events";
import { test, after } from "node:test";
import { createLocalServer } from "../scripts/lib/local-server.js";
import { createStewardFixtures } from "../scripts/lib/steward-fixtures.js";
import { membershipCommand } from "../api/_lib/membership-contract.js";
import { createSupabaseProvider } from "../api/_lib/steward-data.js";

const provider = createStewardFixtures();
const server = createLocalServer({ stewardProvider: provider });
server.listen(0, "127.0.0.1");
await once(server, "listening");
const base = "http://127.0.0.1:" + server.address().port;
after(async () => {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
});
const post = (body, cookie = "", origin = base) =>
  fetch(base + "/api/admin", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Origin: origin,
      Cookie: cookie,
    },
    body: JSON.stringify(body),
  });
const read = async (resource, id, cookie) => {
  const r = await fetch(
    base +
      "/api/admin?" +
      new URLSearchParams({ resource, ...(id ? { id } : {}) }),
    { headers: { Cookie: cookie } },
  );
  assert.equal(r.status, 200);
  assert.match(r.headers.get("cache-control"), /no-store/);
  return r.json();
};
async function signIn() {
  await post({ action: "request-code", email: "steward@example.test" });
  return (
    await post({
      action: "verify-code",
      email: "steward@example.test",
      code: "123456",
    })
  ).headers
    .get("set-cookie")
    .split(";")[0];
}
const payload = (overrides = {}) => ({
  name: "Synthetic new profile",
  member_type: "individual",
  location: "Demo region",
  summary: "Curated summary",
  vision: "A shared vision",
  website: "https://example.test",
  avatar: "",
  focus_areas: [],
  contribution_areas: [],
  organization_ids: [],
  ...overrides,
});
const command = (fields) => ({
  request_id: randomUUID(),
  reason: "Synthetic steward decision",
  ...fields,
});

test("approval, membership standing and visibility change independently; original answers stay intact", async () => {
  const cookie = await signIn();
  const before = await read("application", provider.ids.application, cookie);
  const approve = command({
    action: "review-application",
    id: before.application.id,
    revision: 1,
    state: "approved",
  });
  assert.equal((await post(approve, cookie)).status, 200);
  const after = await read("application", before.application.id, cookie);
  assert.equal(after.application.review_state, "approved");
  assert.equal(after.profile.membership_status, "unconfirmed");
  assert.equal(after.profile.publication_state, "draft");
  assert.deepEqual(
    after.application.original_answers,
    before.application.original_answers,
  );
  assert.equal(after.history.at(-1).reviewed_revision, 1);
  assert.equal(after.history.at(-1).resulting_revision, 2);
  assert.equal(after.history.at(-1).actor_label, "steward@example.test");
  assert.equal((await post(approve, cookie)).status, 200);
  assert.equal(
    (await read("application", before.application.id, cookie)).history.length,
    after.history.length,
  );
  assert.equal(
    (await post({ ...approve, state: "declined" }, cookie)).status,
    409,
  );
  assert.equal(
    (await post({ ...approve, request_id: randomUUID() }, cookie)).status,
    409,
  );
  assert.equal(
    (
      await post(
        command({
          action: "review-application",
          id: before.application.id,
          revision: 2,
          state: "declined",
        }),
        cookie,
      )
    ).status,
    409,
  );
  assert.equal(
    (
      await post(
        command({
          action: "review-application",
          id: before.application.id,
          revision: 2,
          state: "pending",
        }),
        cookie,
      )
    ).status,
    200,
  );
  for (const [action, state, revision] of [
    ["set-membership-status", "active", 1],
    ["set-profile-visibility", "published", 2],
    ["set-membership-status", "paused", 3],
  ]) {
    assert.equal(
      (
        await post(
          command({ action, state, revision, id: provider.ids.person }),
          cookie,
        )
      ).status,
      200,
    );
  }
  const profile = await read("member", provider.ids.person, cookie);
  assert.equal(profile.member.membership_status, "paused");
  assert.equal(profile.member.publication_state, "published");
  assert.equal(
    (await read("application", before.application.id, cookie)).application
      .review_state,
    "pending",
  );
  assert.equal(profile.history.length, 3);
  assert.equal(
    (await read("email-deliveries", before.application.id, cookie))
      .notifications[0].attempts,
    1,
  );
});

test("creating and linking an organization profile does not approve or publish, and a retry creates only one", async () => {
  const cookie = await signIn();
  const applicationId = "10000000-0000-4000-8000-000000000002";
  const save = command({
    action: "save-profile",
    application_id: applicationId,
    application_revision: 1,
    payload: payload({
      name: "New demo organization",
      member_type: "organization",
    }),
  });
  const first = await post(save, cookie);
  assert.equal(first.status, 200);
  const created = await first.json();
  assert.deepEqual(await (await post(save, cookie)).json(), created);
  const application = await read("application", applicationId, cookie);
  assert.equal(application.application.member_id, created.id);
  assert.equal(application.application.review_state, "pending");
  assert.equal(application.profile.membership_status, "unconfirmed");
  assert.equal(application.profile.publication_state, "draft");
  assert.equal(application.profile.summary, "Curated summary");
  assert.doesNotMatch(
    JSON.stringify(application.profile),
    /org-description|governance-consent|closing-notes|original_answers/,
  );
  assert.equal(
    (await post({ ...save, request_id: randomUUID() }, cookie)).status,
    409,
  );
  const wrongType = command({
    action: "link-profile",
    id: applicationId,
    revision: 2,
    member_id: provider.ids.person,
  });
  assert.equal((await post(wrongType, cookie)).status, 400);
});

test("profile editing preserves standing and visibility and updates published public fields without private history", async () => {
  const cookie = await signIn();
  const before = await read("member", provider.ids.person, cookie);
  const save = command({
    action: "save-profile",
    id: provider.ids.person,
    revision: before.member.revision,
    payload: payload({
      name: "Renamed demo person",
      organization_ids: [provider.ids.organization],
    }),
  });
  assert.equal((await post(save, cookie)).status, 200);
  const after = await read("member", provider.ids.person, cookie);
  assert.equal(after.member.membership_status, before.member.membership_status);
  assert.equal(after.member.publication_state, before.member.publication_state);
  assert.equal(
    after.history.at(-1).changes.before.profile.name,
    before.member.name,
  );
  assert.equal(
    after.history.at(-1).changes.after.profile.name,
    "Renamed demo person",
  );
  const publicData = await (await fetch(base + "/api/members")).json();
  assert.match(JSON.stringify(publicData), /Renamed demo person/);
  assert.doesNotMatch(
    JSON.stringify(publicData),
    /membership_status|Synthetic steward decision|actor_label|original_answers/,
  );
  assert.equal(
    (await post({ ...save, request_id: randomUUID() }, cookie)).status,
    409,
  );
});

test("commands validate fields, URLs, limits and relationships without enabling mass assignment", async () => {
  const cookie = await signIn();
  for (const fields of [
    { payload: payload({ website: "javascript:alert(1)" }) },
    { payload: payload({ avatar: "data:text/html,unsafe" }) },
    { payload: payload({ name: " " }) },
    { payload: payload({ vision: "x".repeat(5001) }) },
    { payload: payload({ membership_status: "active" }) },
    { payload: payload({ original_answers: { private: true } }) },
    {
      payload: payload({
        member_type: "organization",
        organization_ids: [provider.ids.organization],
      }),
    },
    { payload: payload({ focus_areas: [""] }) },
  ])
    assert.equal(
      (await post(command({ action: "save-profile", ...fields }), cookie))
        .status,
      400,
    );
  assert.equal(
    (
      await post(
        command({
          action: "save-profile",
          payload: payload({ organization_ids: [provider.ids.person] }),
        }),
        cookie,
      )
    ).status,
    400,
  );
  assert.throws(
    () =>
      membershipCommand(
        command({
          action: "set-membership-status",
          id: provider.ids.person,
          revision: 1,
          state: "active",
          active: true,
        }),
      ),
    /invalid_membership_command/,
  );
});

test("missing sessions, cross-origin posts and revoked roles cannot run membership commands", async () => {
  const body = command({
    action: "set-membership-status",
    id: provider.ids.person,
    revision: 1,
    state: "ended",
  });
  assert.equal((await post(body)).status, 401);
  const cookie = await signIn();
  assert.equal((await post(body, cookie, "https://other.example")).status, 403);
  provider.setActive("steward@example.test", false);
  assert.equal((await post(body, cookie)).status, 403);
  provider.setActive("steward@example.test", true);
});

test("membership RPC uses the steward token and never the intake capability", async () => {
  const calls = [];
  const db = createSupabaseProvider({
    url: "https://synthetic.supabase.co",
    key: "sb_publishable_synthetic",
    request: async (url, options) => {
      calls.push({ url: String(url), options });
      return new Response(
        JSON.stringify({ id: provider.ids.person, revision: 2 }),
        { headers: { "content-type": "application/json" } },
      );
    },
  });
  const body = command({
    action: "set-membership-status",
    id: provider.ids.person,
    revision: 1,
    state: "active",
  });
  await db.membershipCommand(
    "synthetic-steward-token",
    body.request_id,
    membershipCommand(body),
  );
  assert.match(calls[0].url, /rpc\/membership_command$/);
  assert.equal(
    new Headers(calls[0].options.headers).get("Authorization"),
    "Bearer synthetic-steward-token",
  );
  assert.doesNotMatch(calls[0].options.body, /secret|service_role/);
});

test("application and profile histories retain events beyond a provider page", async () => {
  for (const kind of ["application", "member"]) {
    const historyOffsets = [];
    const db = createSupabaseProvider({
      url: "https://synthetic.supabase.co",
      key: "sb_publishable_synthetic",
      request: async (input, options) => {
        assert.equal(
          new Headers(options.headers).get("Authorization"),
          "Bearer history-token",
        );
        const url = new URL(input),
          history = /_events$/.test(url.pathname);
        let data;
        if (history) {
          const offset = Number(url.searchParams.get("offset") || 0);
          historyOffsets.push(offset);
          data = Array.from({ length: offset === 0 ? 500 : 1 }, (_, i) => ({
            id: offset + i,
            event_type: "synthetic_event",
          }));
        } else
          data =
            kind === "application"
              ? { id: provider.ids.application, member_id: null }
              : { id: provider.ids.person };
        return new Response(JSON.stringify(data), {
          headers: { "content-type": "application/json" },
        });
      },
    });
    const detail = await db[kind](
      "history-token",
      kind === "application" ? provider.ids.application : provider.ids.person,
    );
    assert.equal(detail.history.length, 501);
    assert.equal(detail.history.at(-1).id, 500);
    assert.deepEqual(historyOffsets, [0, 500]);
  }
});
