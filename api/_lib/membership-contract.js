import { AdminError } from "./steward-data.js";
import { uuid } from "./content-contract.js";

export const membershipActions = [
  "review-application",
  "save-profile",
  "link-profile",
  "set-membership-status",
  "set-profile-visibility",
];
export const reviewTransitions = {
  pending: ["approved", "declined", "changes_requested"],
  changes_requested: ["approved", "declined", "pending"],
  approved: ["pending"],
  declined: ["pending"],
  legacy_active: ["approved", "declined", "changes_requested", "pending"],
};
export const membershipStates = ["unconfirmed", "active", "paused", "ended"];

export function membershipCommand(body) {
  const fail = () => {
    throw new AdminError(400, "invalid_membership_command");
  };
  const text = (value, max, required = false) => {
    if (
      typeof value !== "string" ||
      value.length > max ||
      (required && !value.trim())
    )
      fail();
    return value.trim();
  };
  const id = (value) => {
    if (typeof value !== "string" || !uuid.test(value)) fail();
    return value;
  };
  const revision = (value) => {
    if (!Number.isInteger(value) || value < 1 || value > 2147483646) fail();
    return value;
  };
  if (
    !membershipActions.includes(body.action) ||
    !uuid.test(body.request_id || "")
  )
    fail();
  const command = {
    action: body.action,
    reason: text(body.reason, 1000, true),
  };
  let fields;
  if (body.action === "save-profile") {
    fields = [
      "id",
      "revision",
      "application_id",
      "application_revision",
      "payload",
    ];
    if (body.id !== undefined) {
      command.id = id(body.id);
      command.revision = revision(body.revision);
    } else if (body.revision !== undefined) fail();
    if (body.application_id !== undefined) {
      if (body.id !== undefined) fail();
      command.application_id = id(body.application_id);
      command.application_revision = revision(body.application_revision);
    } else if (body.application_revision !== undefined) fail();
    const input = body.payload;
    if (!input || typeof input !== "object" || Array.isArray(input)) fail();
    const limits = {
      name: 200,
      member_type: 20,
      location: 300,
      summary: 2000,
      vision: 5000,
      website: 2048,
      avatar: 2048,
    };
    if (
      Object.keys(input).some(
        (k) =>
          ![
            ...Object.keys(limits),
            "focus_areas",
            "contribution_areas",
            "organization_ids",
          ].includes(k),
      )
    )
      fail();
    const payload = {};
    for (const [key, max] of Object.entries(limits))
      payload[key] = text(
        input[key] ?? "",
        max,
        ["name", "member_type"].includes(key),
      );
    if (!["individual", "organization"].includes(payload.member_type)) fail();
    for (const field of ["website", "avatar"])
      if (payload[field] && !/^https?:\/\/[^\s]+$/i.test(payload[field]))
        fail();
    for (const key of [
      "focus_areas",
      "contribution_areas",
      "organization_ids",
    ]) {
      const values = input[key] ?? [];
      if (!Array.isArray(values) || values.length > 20) fail();
      payload[key] = [
        ...new Set(
          values.map((value) =>
            key === "organization_ids" ? id(value) : text(value, 80, true),
          ),
        ),
      ];
    }
    if (
      payload.member_type === "organization" &&
      payload.organization_ids.length
    )
      fail();
    command.payload = payload;
  } else {
    fields = [
      "id",
      "revision",
      ...(body.action === "link-profile" ? ["member_id"] : ["state"]),
    ];
    command.id = id(body.id);
    command.revision = revision(body.revision);
    if (body.action === "link-profile")
      command.member_id = body.member_id === null ? null : id(body.member_id);
    else {
      const states =
        body.action === "review-application"
          ? ["pending", "approved", "declined", "changes_requested"]
          : body.action === "set-membership-status"
            ? membershipStates
            : ["draft", "published", "hidden"];
      if (!states.includes(body.state)) fail();
      command.state = body.state;
      if (body.action === "review-application" && body.state !== "pending") {
        fields.push("applicant_message");
        command.applicant_message = text(
          body.applicant_message,
          4000,
          body.state === "changes_requested",
        );
      }
    }
  }
  if (
    Object.keys(body).some(
      (key) => !["action", "request_id", "reason", ...fields].includes(key),
    )
  )
    fail();
  return command;
}
