// Membership application intake rules, enforced by the API before any write.
// join.html repeats the written-answer limits as minlength/maxlength so the
// browser can guide applicants; tests/application-contract.test.js keeps the
// page and these rules in step.

export class InvalidApplication extends Error {}

export const applicantTypes = ["individual", "organization"];

// Minimums turn away empty or throwaway answers. Bots are handled separately
// by the honeypot field and the intake rate limit.
export const writtenAnswerLimits = {
  "regen-relationship": { min: 120, max: 2000 },
  "capital-contribution": { min: 120, max: 2000 },
};

// The seven values named in the Membership Agreement.
export const valueChoices = [
  "care",
  "stewardship",
  "transparency",
  "reciprocity",
  "plurality",
  "collaboration",
  "integrity",
];
export const maxValueChoices = 3;

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const isAnswer = (value) =>
  typeof value === "string" ||
  (Array.isArray(value) &&
    value.length <= 30 &&
    value.every((item) => typeof item === "string"));

export function applicationPayload(body) {
  const fail = (code) => {
    throw new InvalidApplication(code);
  };
  const name = body["full-name"];
  if (typeof name !== "string" || !name.trim() || name.length > 200)
    fail("missing_required_fields");
  if (
    typeof body.email !== "string" ||
    body.email.length > 254 ||
    !emailPattern.test(body.email)
  )
    fail("invalid_email");
  const type = body["applicant-type"] ?? "individual";
  if (!applicantTypes.includes(type)) fail("invalid_member_type");

  const { website_confirm, ...answers } = body;
  if (!Object.values(answers).every(isAnswer)) fail("invalid_request");

  for (const [key, { min, max }] of Object.entries(writtenAnswerLimits)) {
    const value = answers[key];
    const length = typeof value === "string" ? value.trim().length : 0;
    if (length < min || length > max) fail("invalid_answer_length");
  }
  // The Membership Agreement has organizations name their representative
  // when they apply.
  if (type === "organization") {
    const representative = answers["org-rep"];
    if (
      typeof representative !== "string" ||
      !representative.trim() ||
      representative.length > 200
    )
      fail("missing_required_fields");
  }
  if (answers.values !== undefined) {
    const values = [answers.values].flat();
    if (
      values.length > maxValueChoices ||
      values.some((value) => !valueChoices.includes(value))
    )
      fail("invalid_request");
  }

  return {
    ...answers,
    "full-name": name.trim(),
    email: body.email.trim().toLowerCase(),
  };
}
