import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { membershipDecision } from "../api/_lib/membership-email.js";
import { membershipCommand } from "../api/_lib/membership-contract.js";
import { drainNotifications } from "../api/_lib/intake-notifications.js";
import { createSupabaseProvider } from "../api/_lib/steward-data.js";
import { createStewardFixtures } from "../scripts/lib/steward-fixtures.js";

const review = (state, applicant_message = "") => ({
  action: "review-application",
  request_id: randomUUID(),
  id: randomUUID(),
  revision: 1,
  state,
  reason: "Private review reason — never email this",
  applicant_message,
});

test("decision templates distinguish outcomes, escape public text, and preserve the receipt design", () => {
  for (const state of ["approved", "declined", "changes_requested"]) {
    const message = membershipDecision({
      name: '<Afo & "team">',
      state,
      message: "Please clarify <script> & details.\nThank you.",
    });
    assert.match(message.text, /REGEN COMMONS/);
    assert.match(
      message.text,
      /Please clarify <script> & details\.\nThank you\./,
    );
    assert.match(message.html, /&lt;Afo &amp; &quot;team&quot;&gt;/);
    assert.match(
      message.html,
      /Please clarify &lt;script&gt; &amp; details\.<br>Thank you\./,
    );
    assert.doesNotMatch(message.html, /<script>/);
    assert.match(message.html, /background-color:#E0D6C0/);
    assert.match(message.html, /padding:28px/);
    assert.doesNotMatch(
      message.text,
      /membership is active|profile is published|Private review reason/i,
    );
    assert.match(
      message.text,
      state === "approved"
        ? /has been approved/
        : state === "declined"
          ? /unable to approve/
          : /Reply to this email with the details requested/,
    );
  }
  assert.throws(() => membershipDecision({ state: "pending", message: "" }));
  assert.throws(() =>
    membershipDecision({ state: "changes_requested", message: "  " }),
  );
  assert.throws(() =>
    membershipDecision({ state: "approved", message: "", version: 2 }),
  );
});

test("email decisions require explicit public text; requests for changes cannot be blank", () => {
  const approved = review("approved");
  assert.equal(membershipCommand(approved).applicant_message, "");
  const { applicant_message, ...oldCommand } = approved;
  assert.throws(() => membershipCommand(oldCommand));
  assert.throws(() => membershipCommand(review("changes_requested", "  ")));
  assert.equal(
    membershipCommand(review("changes_requested", "  Please reply.  "))
      .applicant_message,
    "Please reply.",
  );
  assert.throws(() => membershipCommand(review("approved", "x".repeat(4001))));
  const reopen = review("pending");
  delete reopen.applicant_message;
  assert.equal(membershipCommand(reopen).state, "pending");
  assert.throws(() =>
    membershipCommand({
      ...reopen,
      applicant_message: "Do not send on reopening",
    }),
  );
});

test("decision dispatch uses only the immutable applicant snapshot and stable Resend identity", async () => {
  const id = randomUUID(),
    providerId = randomUUID();
  let requestBody, requestHeaders, completion;
  await drainNotifications({
    claim: async () => [
      {
        id,
        channel: "decision",
        name: "Synthetic applicant",
        email: "applicant@example.test",
        state: "changes_requested",
        message: "Please share your preferred contribution.",
        version: 1,
        reason: "PRIVATE: not for applicant",
        original_answers: { secret: "never include" },
      },
    ],
    env: {
      RESEND_API_KEY: "synthetic-key",
      RESEND_FROM_EMAIL: "membership@example.test",
      RESEND_REPLY_TO_EMAIL: "reply@example.test",
      STEWARD_NOTIFY_EMAILS: "steward@example.test",
    },
    request: async (url, options) => {
      assert.equal(url, "https://api.resend.com/emails");
      requestBody = JSON.parse(options.body);
      requestHeaders = options.headers;
      return new Response(JSON.stringify({ id: providerId }), { status: 200 });
    },
    finish: async (job, status, outcome) => {
      completion = { status, ...outcome };
    },
  });
  assert.deepEqual(requestBody.to, ["applicant@example.test"]);
  assert.equal(requestBody.reply_to, "reply@example.test");
  assert.equal(requestHeaders["Idempotency-Key"], `membership/${id}`);
  assert.doesNotMatch(
    JSON.stringify(requestBody),
    /PRIVATE|original_answers|never include/,
  );
  assert.equal(completion.status, "sent");
  assert.equal(completion.provider_message_id, providerId);
});

test("a committed decision succeeds even when delivery cannot be confirmed", async () => {
  const id = randomUUID(),
    jobId = randomUUID();
  const saved = { id, revision: 2, notification_id: jobId };
  const calls = [];
  const provider = createSupabaseProvider({
    url: "https://database.example.test",
    key: "synthetic-publishable-key",
    env: { SUPABASE_INTAKE_SECRET: "synthetic-worker-key" },
    request: async (url, options) => {
      calls.push(String(url));
      if (String(url).endsWith("/rpc/membership_command"))
        return new Response(JSON.stringify(saved), { status: 200 });
      if (String(url).endsWith("/rpc/retry_notification")) {
        const body = JSON.parse(options.body);
        assert.equal(body.p_attempts, 0);
        assert.equal(body.p_job_id, jobId);
        return new Response(
          JSON.stringify({ message: "notification_changed", code: "PT409" }),
          { status: 409 },
        );
      }
      throw new Error("Unexpected request");
    },
  });
  assert.deepEqual(
    await provider.membershipCommand(
      "synthetic-session",
      randomUUID(),
      membershipCommand(review("approved")),
    ),
    saved,
  );
  assert.equal(calls.length, 2);
});

test("failed decision delivery stays separate from the decision and becomes ineligible after reopening", async () => {
  const provider = createStewardFixtures({ retryFailure: true });
  await provider.requestCode("steward@example.test");
  const { token } = await provider.verifyCode("steward@example.test", "123456");
  const id = provider.ids.application;
  const command = membershipCommand({
    ...review("changes_requested", "Please clarify your contribution."),
    id,
  });
  const requestId = randomUUID();
  const saved = await provider.membershipCommand(token, requestId, command);
  assert.equal(
    (await provider.application(token, id)).application.review_state,
    "changes_requested",
  );
  let job = (await provider.notifications(token, id)).notifications.find(
    (x) => x.id === saved.notification_id,
  );
  assert.equal(job.status, "failed");
  assert.equal(job.failure_code, "resend_unavailable");
  assert.equal(job.applicant_message, "Please clarify your contribution.");
  assert.doesNotMatch(JSON.stringify(job), /Private review reason/);
  await provider.retryNotification(token, {
    application_id: id,
    job_id: job.id,
    attempts: 1,
  });
  job = (await provider.notifications(token, id)).notifications.find(
    (x) => x.id === job.id,
  );
  assert.equal(job.attempts, 2);
  const reopen = review("pending");
  delete reopen.applicant_message;
  await provider.membershipCommand(
    token,
    randomUUID(),
    membershipCommand({ ...reopen, id, revision: 2 }),
  );
  job = (await provider.notifications(token, id)).notifications.find(
    (x) => x.id === job.id,
  );
  assert.equal(job.status, "superseded");
  assert.equal(job.retry_block, "decision_superseded");
  await assert.rejects(
    provider.retryNotification(token, {
      application_id: id,
      job_id: job.id,
      attempts: 2,
    }),
    { status: 409 },
  );
  assert.equal(
    (await provider.application(token, id)).application.review_state,
    "pending",
  );
});
