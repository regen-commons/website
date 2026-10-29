import assert from "node:assert/strict";
import { test } from "node:test";
import "../data-state.js";
import "../seed-form.js";

const response = (body, status = 200) => new Response(JSON.stringify(body), { status });

test("seed length boundaries match the API, and no invalid seed is sent", async () => {
  const states = [];
  let requests = 0;
  const dependencies = { fetch: async () => { requests++; return response({ ok: true }); } };
  const save = RegenSeeds.createSaver((state) => states.push(state), dependencies);
  for (const text of ["", "  ", "ab", "x".repeat(241)]) await save(text);
  assert.equal(requests, 0);
  assert.ok(states.every((state) => state.status === "invalid"));
  for (const text of ["abc", "x".repeat(240)]) {
    const saveValid = RegenSeeds.createSaver((state) => states.push(state), dependencies);
    await saveValid(text);
    assert.equal(states.at(-1).status, "saved");
  }
  assert.equal(requests, 2);
});

test("a pending save and an acknowledged save cannot be submitted twice", async () => {
  let complete;
  let requests = 0;
  let sent;
  const states = [];
  const save = RegenSeeds.createSaver((state) => states.push(state), {
    fetch: async (_, options) => {
      requests++;
      sent = JSON.parse(options.body);
      return new Promise((resolve) => { complete = resolve; });
    },
  });
  const first = save("  A seed to save  ");
  assert.equal(states.at(-1).status, "saving");
  await save("A second click");
  assert.equal(requests, 1);
  assert.equal(states.some((state) => state.status === "saved"), false);
  complete(response({ ok: true }));
  await first;
  await save("Another click after success");
  assert.equal(requests, 1);
  assert.equal(sent.text, "A seed to save");
  assert.equal(states.at(-1).text, "A seed to save");
});

test("HTTP, network, and malformed success responses preserve retry without false success", async () => {
  for (const failure of [
    () => response({ error: "rate_limited" }, 429),
    () => response({ error: "notion_failed" }, 500),
    () => response({ error: "unavailable" }, 503),
    () => { throw new TypeError("Network disconnected"); },
    () => response({}),
    () => new Response("not json"),
  ]) {
    const states = [];
    let attempt = 0;
    const save = RegenSeeds.createSaver((state) => states.push(state), {
      fetch: async () => ++attempt === 1 ? failure() : response({ ok: true }),
    });
    await save("Keep this draft");
    assert.equal(states.at(-1).status, "error");
    assert.ok(!states.some((state) => state.status === "saved"));
    await save("Keep this draft");
    assert.equal(states.at(-1).status, "saved");
    assert.equal(states.at(-1).text, "Keep this draft");
  }
});

test("a timed-out request becomes retryable and never reports a confirmed save", async () => {
  const states = [];
  const save = RegenSeeds.createSaver((state) => states.push(state), {
    timeoutMs: 10,
    fetch: (_, { signal }) => new Promise((_, reject) => {
      signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")));
    }),
  });
  await save("An uncertain save");
  assert.equal(states.at(-1).status, "error");
  assert.match(states.at(-1).message, /couldn't confirm/);
});

test("list reads distinguish loading, empty, ready, and error; retries recover", async () => {
  const states = [];
  const replies = [response({ members: [] }), response({ members: [{ id: "member" }] }),
    response({}, 503), response({ wrong: [] }), response({ members: [{ id: "recovered" }] })];
  const load = RegenData.createListLoader("/api/members", "members", (state) => states.push(state), {
    fetch: async () => replies.shift(),
  });
  for (const expected of ["empty", "ready", "error", "error", "ready"]) {
    const pending = load();
    assert.equal(states.at(-1).status, "loading");
    await pending;
    assert.equal(states.at(-1).status, expected);
  }
  assert.equal(states.at(-1).items[0].id, "recovered");
});

test("read retries do not overlap and graph/library state is independent", async () => {
  let complete;
  let requests = 0;
  const graph = [], library = [];
  const loadGraph = RegenData.createListLoader("/api/members", "members", (state) => graph.push(state), {
    fetch: () => { requests++; return new Promise((resolve) => { complete = resolve; }); },
  });
  const loadLibrary = RegenData.createListLoader("/api/contributions", "contributions", (state) => library.push(state), {
    fetch: async () => response({ contributions: [] }),
  });
  const pending = loadGraph();
  await loadGraph();
  await loadLibrary();
  assert.equal(requests, 1);
  assert.equal(graph.at(-1).status, "loading");
  assert.equal(library.at(-1).status, "empty");
  complete(response({ members: [{ id: "member" }] }));
  await pending;
  assert.equal(graph.at(-1).status, "ready");
});
