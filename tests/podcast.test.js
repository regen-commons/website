import assert from "node:assert/strict";
import { after, test } from "node:test";
import { once } from "node:events";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { createLocalServer } from "../scripts/lib/local-server.js";
import {
  podcastInterests,
  podcastMessage,
  podcastNoteLimit,
} from "../podcast-contract.js";

const server = createLocalServer();
server.listen(0, "127.0.0.1");
await once(server, "listening");
const base = `http://127.0.0.1:${server.address().port}`;
after(async () => {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
});
const sender = { name: "Synthetic Listener", email: "Listener@Example.test" };

test("a podcast message names the chosen interests for the council and keeps the note", () => {
  assert.deepEqual(
    podcastMessage({
      ...sender,
      // Order and repeats come from the page; the council sees the listed order.
      interests: ["question", "guest", "question"],
      note: "  How does a commons credit oral knowledge?  ",
    }),
    {
      name: "Synthetic Listener",
      email: "listener@example.test",
      subject: "Podcast: guest, question",
      message:
        "Ways to take part: Join a conversation as a guest; Suggest a question or topic\n\n" +
        "How does a commons credit oral knowledge?",
    },
  );
  const noteOnly = podcastMessage({ ...sender, note: "Call it Commons Table" });
  assert.equal(noteOnly.subject, "Podcast: note");
  assert.equal(noteOnly.message, "Call it Commons Table");
  assert.equal(
    podcastMessage({ ...sender, interests: ["updates"], note: "" }).message,
    "Ways to take part: Hear when the first episode is out",
  );
});

test("a podcast message needs something to answer, a known interest and a way to reply", () => {
  for (const input of [
    { ...sender },
    { ...sender, interests: [], note: " hi " },
  ])
    assert.throws(() => podcastMessage(input), /empty_podcast_message/);
  for (const input of [
    null,
    [],
    { ...sender, interests: ["host"] },
    { ...sender, interests: "guest" },
    { ...sender, interests: ["guest"], note: 5 },
    { ...sender, note: "x".repeat(podcastNoteLimit + 1) },
  ])
    assert.throws(() => podcastMessage(input), /invalid_podcast_message/);
  for (const input of [
    { interests: ["guest"] },
    { ...sender, name: " ", interests: ["guest"] },
    { ...sender, email: "listener@example", interests: ["guest"] },
  ])
    assert.throws(() => podcastMessage(input), /invalid_contact/);
});

test("every interest plus the longest note still fits one contact message", () => {
  const { subject, message } = podcastMessage({
    ...sender,
    interests: podcastInterests.map((interest) => interest.value),
    note: "🌱".repeat(podcastNoteLimit / 2),
  });
  assert.ok(subject.length <= 200);
  assert.ok(message.length <= 5000);
});

test("a podcast message reaches the private council inbox and no public listing", async () => {
  const body = podcastMessage({
    ...sender,
    interests: ["guest"],
    note: "Synthetic podcast note <b>kept as text</b>",
  });
  const saved = await fetch(base + "/api/contact", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Idempotency-Key": randomUUID(),
    },
    body: JSON.stringify(body),
  });
  assert.equal(saved.status, 200);
  for (const resource of ["members", "seeds", "contributions"])
    assert.doesNotMatch(
      await (await fetch(base + "/api/" + resource)).text(),
      /Synthetic podcast note|listener@example/,
    );
  assert.equal(
    (await fetch(base + "/api/admin?resource=messages")).status,
    401,
  );
  const send = (payload) =>
    fetch(base + "/api/admin", {
      method: "POST",
      headers: { Origin: base, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
  await send({ action: "request-code", email: "steward@example.test" });
  const login = await send({
    action: "verify-code",
    email: "steward@example.test",
    code: "123456",
  });
  const read = (query) =>
    fetch(base + "/api/admin?" + query, {
      headers: { Cookie: login.headers.get("set-cookie").split(";")[0] },
    });
  const inbox = await (await read("resource=messages")).json();
  assert.deepEqual(
    inbox.items.map((item) => item.subject),
    ["Podcast: guest"],
  );
  const detail = await (
    await read("resource=message&id=" + inbox.items[0].id)
  ).json();
  assert.equal(detail.message.email, "listener@example.test");
  assert.equal(detail.message.message, body.message);
});

test("a submit made before the form script runs is refused and never placed in a URL", async () => {
  // Without method and action a browser would GET the page with the name,
  // email and note in the query string.
  assert.match(
    await (await fetch(base + "/podcast")).text(),
    /<form id="podcast-form"[^>]*\smethod="post"[^>]*\saction="\/api\/contact"/,
  );
  const native = await fetch(base + "/api/contact", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      name: "Synthetic Listener",
      email: "listener@example.test",
      note: "Sent without the script",
    }),
  });
  assert.equal(native.status, 415);
  assert.deepEqual(await native.json(), { error: "json_required" });
});

test("the podcast page is served with its form scripts and linked from the site", async () => {
  const page = await (await fetch(base + "/podcast")).text();
  assert.match(page, /id="podcast-form"/);
  assert.match(page, /src="\/podcast-form\.js"/);
  for (const script of [
    "/podcast-form.js",
    "/podcast-contract.js",
    "/contact-submit.js",
    "/contact-contract.js",
  ])
    assert.equal((await fetch(base + script)).status, 200, script);
  const file = (name) => readFile(new URL("../" + name, import.meta.url), "utf8");
  // Each page carries its own copy of the site navigation.
  for (const name of [
    "index.html",
    "learn.html",
    "map.html",
    "seeds.html",
    "join.html",
    "about.html",
    "constitution.html",
    "podcast.html",
  ])
    assert.match(
      await file(name),
      /<nav class="page-nav"(?:(?!<\/nav>)[\s\S])*href="\/podcast"/,
      name,
    );
  assert.match(await file("sitemap.xml"), /regencommons\.com\/podcast</);
});
