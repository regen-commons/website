import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  applicationPayload,
  InvalidApplication,
  valueChoices,
  writtenAnswerLimits,
} from "../application-contract.js";

const sentence = "Synthetic applicants tend a shared seed library together. ";
const text = (length) => sentence.repeat(Math.ceil(length / sentence.length)).slice(0, length);
const valid = (overrides = {}) => ({
  "full-name": "  Synthetic Applicant ",
  email: "Applicant@Example.test",
  "regen-relationship": text(120),
  "capital-contribution": text(400),
  ...overrides,
});
const rejects = (body, code) =>
  assert.throws(
    () => applicationPayload(body),
    (error) => error instanceof InvalidApplication && error.message === code,
  );

test("accepts written answers at the minimum and normalizes identity fields", () => {
  const payload = applicationPayload(valid({ website_confirm: "", values: ["care", "plurality"] }));
  assert.equal(payload["full-name"], "Synthetic Applicant");
  assert.equal(payload.email, "applicant@example.test");
  assert.deepEqual(payload.values, ["care", "plurality"]);
  assert.ok(!("website_confirm" in payload));
});

test("rejects written answers that are missing, short once trimmed, or too long", () => {
  for (const key of Object.keys(writtenAnswerLimits)) {
    const { min, max } = writtenAnswerLimits[key];
    const { [key]: _omitted, ...missing } = valid();
    rejects(missing, "invalid_answer_length");
    rejects(valid({ [key]: `   ${text(min - 1)}   ` }), "invalid_answer_length");
    rejects(valid({ [key]: text(max + 1) }), "invalid_answer_length");
  }
});

test("organizations must name a representative; individuals need not", () => {
  rejects(valid({ "applicant-type": "organization" }), "missing_required_fields");
  rejects(valid({ "applicant-type": "organization", "org-rep": "   " }), "missing_required_fields");
  assert.equal(
    applicationPayload(valid({ "applicant-type": "organization", "org-rep": "Sam, facilitator" }))["org-rep"],
    "Sam, facilitator",
  );
  assert.ok(applicationPayload(valid({ "applicant-type": "individual" })));
});

test("value choices are limited to three of the agreement's values", () => {
  assert.ok(applicationPayload(valid({ values: valueChoices.slice(0, 3) })));
  rejects(valid({ values: valueChoices.slice(0, 4) }), "invalid_request");
  rejects(valid({ values: ["speed"] }), "invalid_request");
});

test("keeps the existing identity and shape checks", () => {
  rejects(valid({ "full-name": " " }), "missing_required_fields");
  rejects(valid({ email: "not-an-email" }), "invalid_email");
  rejects(valid({ "applicant-type": "cooperative" }), "invalid_member_type");
  rejects(valid({ telegram: 42 }), "invalid_request");
});

test("join.html asks for written answers with the same limits the API enforces", async () => {
  const html = await readFile(new URL("../join.html", import.meta.url), "utf8");
  for (const [name, { min, max }] of Object.entries(writtenAnswerLimits)) {
    const tag = html.match(new RegExp(`<textarea[^>]*\\bname="${name}"[^>]*>`));
    assert.ok(tag, `${name} textarea`);
    assert.match(tag[0], new RegExp(`\\bminlength="${min}"`), name);
    assert.match(tag[0], new RegExp(`\\bmaxlength="${max}"`), name);
    assert.match(tag[0], /\brequired\b/, name);
  }
  const values = [...html.matchAll(/name="values" value="([^"]+)"/g)].map((match) => match[1]);
  assert.deepEqual(values, valueChoices);
  assert.match(html, /data-max-choices="3"/);
  assert.match(html, /<input[^>]*\bname="org-rep"[^>]*\brequired\b/);
  assert.doesNotMatch(html, /<input[^>]*\bname="telegram"[^>]*\brequired\b/);
});
