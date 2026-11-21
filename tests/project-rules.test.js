import assert from "node:assert/strict";
import test from "node:test";
import {
  htmlSinks,
  nonLiteralLogs,
  untimedProviderCalls,
  withoutComments,
} from "../scripts/lint/project-rules.mjs";

test("html-sink flags markup written into the page and allows text", () => {
  assert.equal(htmlSinks('card.innerHTML = "<b>" + name + "</b>";'), 1);
  assert.equal(htmlSinks("card.innerHTML += row;"), 1);
  assert.equal(htmlSinks("card.outerHTML = html;"), 1);
  assert.equal(htmlSinks('list.insertAdjacentHTML("beforeend", item);'), 1);
  assert.equal(htmlSinks("document.write(banner);"), 1);
  assert.equal(htmlSinks("card.textContent = name;"), 0);
  assert.equal(htmlSinks("if (card.innerHTML === saved) restore();"), 0);
  assert.equal(htmlSinks("const copy = card.innerHTML;"), 0);
});

test("provider-timeout flags a provider call without an abort signal", () => {
  assert.equal(untimedProviderCalls('const r = await fetch(url, { method: "POST", body });'), 1);
  assert.equal(
    untimedProviderCalls(
      'await request(env.NOTIFY_URL, {\n  method: "POST",\n  body: JSON.stringify(payload),\n});'
    ),
    1
  );
  assert.equal(untimedProviderCalls("await fetch(url);"), 1);
  assert.equal(
    untimedProviderCalls(
      'await request(env.NOTIFY_URL, {\n  method: "POST",\n  signal: AbortSignal.timeout(8000),\n});'
    ),
    0
  );
  assert.equal(
    untimedProviderCalls(
      "fetch: (url, options) => request(url, { ...options, signal: AbortSignal.timeout(10000) }),"
    ),
    0
  );
  assert.equal(untimedProviderCalls("export function createProvider({ request = fetch }) {}"), 0);
  assert.equal(untimedProviderCalls('await db.request("x")'), 0);
});

test("log-literal-only flags API logs that could carry provider bodies or personal data", () => {
  assert.equal(nonLiteralLogs('console.error("resend failed", await response.text());'), 1);
  assert.equal(nonLiteralLogs("console.warn(error);"), 1);
  assert.equal(nonLiteralLogs("console.log(`sent to ${email}`);"), 1);
  assert.equal(nonLiteralLogs('console.log("[notify] POST", JSON.stringify(url));'), 1);
  assert.equal(nonLiteralLogs('console.warn("seed_notification_failed");'), 0);
  assert.equal(nonLiteralLogs("console.warn('contact_notification_processing_failed')"), 0);
  assert.equal(nonLiteralLogs("console.info(`resend_delivery_record_failed`);"), 0);
});

test("the rules see past common variants and comments", () => {
  assert.equal(htmlSinks('el["innerHTML"] = x;'), 1);
  assert.equal(htmlSinks("frame.srcdoc = page;"), 1);
  assert.equal(htmlSinks("el.setHTMLUnsafe(x);"), 1);
  assert.equal(htmlSinks("range.createContextualFragment(x);"), 1);
  assert.equal(htmlSinks("Object.assign(el, { innerHTML: x });"), 1);
  assert.equal(htmlSinks("// card.innerHTML = old;\ncard.textContent = name;"), 0);
  assert.equal(untimedProviderCalls('await globalThis.fetch(url, { method: "POST" });'), 1);
  assert.equal(
    untimedProviderCalls('await fetch(url, { /* signal: later */ method: "POST" });'),
    1
  );
  assert.equal(untimedProviderCalls("await fetch(url, { signal: undefined });"), 1);
  assert.equal(untimedProviderCalls("// fetch(url)\nconst x = 1;"), 0);
  assert.equal(nonLiteralLogs('console["error"](err);'), 1);
  assert.equal(nonLiteralLogs("console.trace(error);"), 1);
  assert.equal(nonLiteralLogs("// console.log(error);"), 0);
});

test("regex literals and template expressions do not confuse the scanner", () => {
  assert.equal(htmlSinks('s.replace(/^\\//, ""); el.innerHTML = p;'), 1);
  assert.equal(htmlSinks("const re = /[&<>\"']/g; el.innerHTML = p;"), 1);
  assert.equal(htmlSinks("const half = a / b; // el.innerHTML = p;\nx = c / d;"), 0);
  assert.equal(
    untimedProviderCalls(
      'const re = /["\']/g; await fetch("https://x", { signal: AbortSignal.timeout(8000) });'
    ),
    0
  );
  assert.equal(nonLiteralLogs("const re = /[\"']/g;\n// console.log(err);"), 0);
  assert.equal(nonLiteralLogs("const t = `a ${b ? `c` : d} e`; console.log(err);"), 1);
  assert.equal(htmlSinks("const t = `${x}`; // el.innerHTML = p"), 0);
  assert.equal(withoutComments("return /a\\/b/.test(x) // note"), "return /a\\/b/.test(x)        ");
});

test("postfix operators, strings and truncated input stay in step", () => {
  const source =
    "const pct = done++ / total; const url = `${base}/x`;\nawait fetch(url);\nconsole.log(err);";
  assert.equal(untimedProviderCalls(source), 1);
  assert.equal(nonLiteralLogs(source), 1);
  assert.equal(htmlSinks("s = 'el.innerHTML = x';"), 0);
  assert.equal(untimedProviderCalls('await fetch(u, { body: "signal: x" });'), 1);
  const truncated = 's = "abc\\';
  assert.equal(withoutComments(truncated).length, truncated.length);
});
