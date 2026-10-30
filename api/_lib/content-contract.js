import { AdminError } from "./steward-data.js";
export const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const contentResources = ["seeds", "contributions"];
export function contributionPayload(input) {
  if (!input || typeof input !== "object" || Array.isArray(input))
    throw new AdminError(400, "invalid_contribution");
  const result = {};
  for (const [field, max] of Object.entries({
    title: 200,
    description: 10000,
    contribution_type: 100,
    stage: 100,
    tier: 100,
    terms: 10000,
    license: 200,
  })) {
    const value = input[field] ?? "";
    if (typeof value !== "string" || value.length > max)
      throw new AdminError(400, "invalid_contribution");
    result[field] = value.trim();
  }
  if (!result.title) throw new AdminError(400, "invalid_contribution");
  for (const field of ["tags", "capital_forms", "contributor_ids"]) {
    const values = input[field] ?? [];
    if (
      !Array.isArray(values) ||
      values.length > (field === "contributor_ids" ? 50 : 20) ||
      values.some(
        (v) =>
          typeof v !== "string" ||
          (field === "contributor_ids"
            ? !uuid.test(v)
            : !v.trim() || v.length > 80),
      )
    )
      throw new AdminError(400, "invalid_contribution");
    result[field] = [...new Set(values.map((v) => v.trim()))];
  }
  return result;
}
