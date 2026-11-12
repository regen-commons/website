export function contactPayload(input) {
  if (!input || typeof input !== "object" || Array.isArray(input))
    throw new Error("invalid_contact");
  const result = {};
  for (const [field, max] of Object.entries({
    name: 200,
    email: 254,
    subject: 200,
    message: 5000,
  })) {
    if (
      typeof input[field] !== "string" ||
      !input[field].trim() ||
      input[field].trim().length > max
    )
      throw new Error("invalid_contact");
    result[field] = input[field].trim();
  }
  if (
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(result.email) ||
    result.message.length < 3
  )
    throw new Error("invalid_contact");
  result.email = result.email.toLowerCase();
  return result;
}
