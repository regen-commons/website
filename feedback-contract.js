export const feedbackCategories = [
  "Bug",
  "Idea",
  "Technical suggestion",
  "Feature request",
  "Security consideration",
  "Other",
  "Fine Tuning",
];

export function feedbackPayload(input) {
  if (
    !input ||
    typeof input.message !== "string" ||
    input.message.trim().length < 3 ||
    input.message.trim().length > 5000 ||
    !Array.isArray(input.categories) ||
    input.categories.length > feedbackCategories.length ||
    input.categories.some((value) => !feedbackCategories.includes(value)) ||
    typeof input.page_path !== "string" ||
    input.page_path.length > 500 ||
    !/^\/(?!\/)[^\s?#\\]*$/.test(input.page_path)
  ) {
    throw new Error("invalid_feedback");
  }
  return {
    message: input.message.trim(),
    categories: [...new Set(input.categories)],
    page_path: input.page_path,
  };
}
