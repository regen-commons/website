import { mkdir, writeFile } from "node:fs/promises";
import { membershipDecision } from "../api/_lib/membership-email.js";

// Generates synthetic QA artifacts only. This script has no sending capability.
const destination = new URL(
  "../artifacts/membership-decision-emails/",
  import.meta.url,
);
await mkdir(destination, { recursive: true });
for (const state of ["approved", "declined", "changes_requested"]) {
  const email = membershipDecision({
    name: "Test applicant",
    state,
    message:
      "This is a delivery and formatting test. No membership decision has been made.\nFor the request-for-changes example, please share which area you would like to contribute to.",
    version: 1,
  });
  await writeFile(new URL(`${state}.html`, destination), email.html);
  await writeFile(new URL(`${state}.txt`, destination), email.text);
  await writeFile(
    new URL(`${state}.json`, destination),
    JSON.stringify({ ...email, subject: "[TEST] " + email.subject }, null, 2),
  );
}
console.log(
  "Generated three synthetic decision-email previews under artifacts/membership-decision-emails.",
);
