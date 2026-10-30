// Persist fixed diagnostic codes, never provider messages, bodies or credentials.
export function resendFailure(status) {
  if ([401, 403].includes(status)) return "resend_authentication_failed";
  if (status === 429) return "resend_rate_limited";
  if (status === 409) return "resend_idempotency_conflict";
  if ([400, 422].includes(status)) return "resend_invalid_request";
  return status >= 500 ? "resend_unavailable" : "resend_rejected";
}

export function transportFailure(error) {
  return ["TimeoutError", "AbortError"].includes(error?.name)
    ? "notification_timeout"
    : "notification_connection_failed";
}

export const resendMessageId = (value) =>
  typeof value === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
