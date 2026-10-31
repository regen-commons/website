import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { runInNewContext } from "node:vm";
import { test } from "node:test";
import { createSupabaseProvider } from "../api/_lib/steward-data.js";

const browser = { window: {}, structuredClone };
runInNewContext(
  await readFile(new URL("../admin/membership.js", import.meta.url), "utf8"),
  browser,
);

test("an uncertain create retries its original command even if editable data changes", async () => {
  assert.equal(typeof browser.window.createMembershipSubmission, "function");
  const submit = browser.window.createMembershipSubmission();
  let name = "First curated name",
    factories = 0;
  const saved = [];
  const makeCommand = () => {
    factories++;
    return { request_id: "same-request", payload: { name } };
  };
  const first = await submit(makeCommand, async (body) => {
    saved.push(structuredClone(body));
    return { status: 503 };
  });
  assert.equal(first.uncertain, true);
  name = "Edited after a lost response";
  const second = await submit(makeCommand, async (body) => {
    saved.push(structuredClone(body));
    return { ok: true };
  });
  assert.equal(second.uncertain, false);
  assert.equal(factories, 1);
  assert.deepEqual(saved[1], saved[0]);
});

test("a definitive validation rejection allows correction without changing request identity", async () => {
  assert.equal(typeof browser.window.createMembershipSubmission, "function");
  const submit = browser.window.createMembershipSubmission();
  let value = "";
  const make = () => ({ request_id: "one-request", payload: { name: value } });
  assert.equal(
    (await submit(make, async () => ({ status: 400 }))).uncertain,
    false,
  );
  value = "Corrected";
  let received;
  await submit(make, async (body) => {
    received = body;
    return { ok: true };
  });
  assert.equal(received.request_id, "one-request");
  assert.equal(received.payload.name, "Corrected");
});

test("profile detail owns the affiliation snapshot paired with its revision", async () => {
  let selection;
  const db = createSupabaseProvider({
    url: "https://synthetic.supabase.co",
    key: "sb_publishable_synthetic",
    request: async (input, options) => {
      const url = new URL(input);
      assert.equal(
        new Headers(options.headers).get("Authorization"),
        "Bearer scoped-steward",
      );
      if (url.pathname.endsWith("/member_events"))
        return new Response("[]", {
          headers: { "content-type": "application/json" },
        });
      selection = url.searchParams.get("select");
      return new Response(
        JSON.stringify({
          id: "20000000-0000-4000-8000-000000000001",
          revision: 2,
          affiliations: [
            {
              organization_id: "20000000-0000-4000-8000-000000000009",
              organization: {
                id: "20000000-0000-4000-8000-000000000009",
                name: "Newly linked organization",
              },
            },
          ],
        }),
        { headers: { "content-type": "application/json" } },
      );
    },
  });
  const detail = await db.member(
    "scoped-steward",
    "20000000-0000-4000-8000-000000000001",
  );
  assert.equal(detail.member.revision, 2);
  assert.deepEqual(detail.organizations, [
    {
      id: "20000000-0000-4000-8000-000000000009",
      name: "Newly linked organization",
    },
  ]);
  assert.match(selection, /affiliations!affiliations_member_id_fkey/);
  assert.match(
    selection,
    /organization:members!affiliations_organization_id_fkey/,
  );
  assert.equal(detail.member.affiliations, undefined);
});
