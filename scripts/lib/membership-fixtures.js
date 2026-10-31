import { randomUUID } from "node:crypto";
import { AdminError } from "../../api/_lib/steward-data.js";
import { reviewTransitions } from "../../api/_lib/membership-contract.js";

// Synthetic-only state for the same commands enforced by PostgreSQL in production.
export function membershipFixtures({
  members,
  applications,
  relationships,
  now,
  notifications,
  decisionFailure = false,
}) {
  const requests = new Map(),
    reviewEvents = [],
    memberEvents = [];
  for (const m of members)
    Object.assign(m, {
      membership_status: "unconfirmed",
      revision: 1,
      vision: "",
      avatar: null,
      updated_at: new Date(now()).toISOString(),
    });
  const requireRevision = (item, revision, code) => {
    if (!item) throw new AdminError(404, code);
    if (item.revision !== revision)
      throw new AdminError(409, "revision_conflict");
  };
  return {
    membershipReviewHistory(id) {
      return structuredClone(
        reviewEvents.filter((e) => e.application_id === id),
      );
    },
    async member(token, id) {
      await this.authorize(token);
      const member = members.find((m) => m.id === id);
      if (!member) throw new AdminError(404, "member_not_found");
      return structuredClone({
        member,
        organizations: relationships.affiliations
          .filter((a) => a.member_id === id)
          .map((a) => {
            const org = members.find((m) => m.id === a.organization_id);
            return { id: org.id, name: org.name };
          }),
        history: memberEvents.filter((e) => e.member_id === id),
      });
    },
    async membershipCommand(token, requestId, command) {
      const actor = await this.authorize(token);
      const serialized = JSON.stringify(command),
        prior = requests.get(requestId);
      if (prior) {
        if (prior.actor !== actor.id || prior.command !== serialized)
          throw new AdminError(409, "request_conflict");
        return structuredClone(prior.result);
      }
      const { action, reason } = command;
      let item, result, notificationId;
      const stamp = () => ({
        id: randomUUID(),
        actor_id: actor.id,
        actor_label: actor.email,
        created_at: new Date(now()).toISOString(),
      });
      const recordLink = (a, memberId) => {
        const revision = a.revision++,
          before = a.member_id;
        a.member_id = memberId;
        reviewEvents.push({
          ...stamp(),
          application_id: a.id,
          event_type: "profile_linked",
          reviewed_revision: revision,
          resulting_revision: a.revision,
          from_state: a.review_state,
          to_state: a.review_state,
          changes: { before, after: memberId },
          note: reason,
        });
      };
      if (["review-application", "link-profile"].includes(action)) {
        item = applications.find((a) => a.id === command.id);
        requireRevision(item, command.revision, "application_not_found");
        if (action === "review-application") {
          if (!reviewTransitions[item.review_state]?.includes(command.state))
            throw new AdminError(409, "invalid_review_transition");
          const before = item.review_state,
            revision = item.revision++;
          item.review_state = command.state;
          const event = {
            ...stamp(),
            application_id: item.id,
            event_type:
              command.state === "pending" ? "reopened" : command.state,
            reviewed_revision: revision,
            resulting_revision: item.revision,
            from_state: before,
            to_state: item.review_state,
            note: reason,
            applicant_message: command.applicant_message ?? null,
          };
          reviewEvents.push(event);
          for (const job of notifications)
            if (
              job.application_id === item.id &&
              job.channel === "decision" &&
              ["pending", "failed", "skipped"].includes(job.status)
            )
              Object.assign(job, {
                status: "superseded",
                updated_at: new Date(now()).toISOString(),
              });
          if (command.state !== "pending") {
            notificationId = randomUUID();
            notifications.push({
              id: notificationId,
              application_id: item.id,
              channel: "decision",
              review_event_id: event.id,
              decision_state: command.state,
              decision_revision: item.revision,
              applicant_message: command.applicant_message,
              recipient: item.email,
              status: decisionFailure ? "failed" : "sent",
              attempts: 1,
              provider_message_id: decisionFailure ? null : randomUUID(),
              failure_code: decisionFailure ? "resend_unavailable" : null,
              created_at: event.created_at,
              updated_at: event.created_at,
              last_attempt_at: event.created_at,
            });
          }
        } else {
          const profile = members.find((m) => m.id === command.member_id);
          if (
            command.member_id !== null &&
            (!profile || profile.member_type !== item.applicant_type)
          )
            throw new AdminError(400, "profile_type_mismatch");
          recordLink(item, command.member_id);
        }
      } else if (action === "save-profile") {
        const { organization_ids, ...fields } = command.payload;
        if (
          organization_ids.some(
            (id) =>
              !members.some(
                (m) => m.id === id && m.member_type === "organization",
              ),
          )
        )
          throw new AdminError(400, "invalid_affiliation");
        let application;
        if (command.application_id) {
          application = applications.find(
            (a) => a.id === command.application_id,
          );
          requireRevision(
            application,
            command.application_revision,
            "application_not_found",
          );
          if (application.member_id)
            throw new AdminError(409, "revision_conflict");
          if (application.applicant_type !== fields.member_type)
            throw new AdminError(400, "profile_type_mismatch");
        }
        item = members.find((m) => m.id === command.id);
        if (command.id) {
          requireRevision(item, command.revision, "member_not_found");
          if (item.member_type !== fields.member_type)
            throw new AdminError(400, "profile_type_immutable");
        }
        const before = item
          ? {
              profile: structuredClone(item),
              organization_ids: relationships.affiliations
                .filter((a) => a.member_id === item.id)
                .map((a) => a.organization_id),
            }
          : null;
        const isNew = !item;
        if (!item) {
          item = {
            id: randomUUID(),
            membership_status: "unconfirmed",
            publication_state: "draft",
            revision: 0,
          };
          members.push(item);
        }
        fields.website ||= null;
        fields.avatar ||= null;
        Object.assign(item, fields, {
          revision: item.revision + 1,
          updated_at: new Date(now()).toISOString(),
        });
        relationships.affiliations = relationships.affiliations.filter(
          (a) => a.member_id !== item.id,
        );
        organization_ids.forEach((id) =>
          relationships.affiliations.push({
            member_id: item.id,
            organization_id: id,
          }),
        );
        memberEvents.push({
          ...stamp(),
          member_id: item.id,
          event_type: isNew ? "profile_created" : "profile_updated",
          revision: item.revision,
          reason,
          changes: {
            before,
            after: { profile: structuredClone(item), organization_ids },
          },
        });
        if (application) recordLink(application, item.id);
      } else {
        item = members.find((m) => m.id === command.id);
        requireRevision(item, command.revision, "member_not_found");
        const key =
          action === "set-membership-status"
            ? "membership_status"
            : "publication_state";
        const before = item[key];
        item[key] = command.state;
        item.revision++;
        item.updated_at = new Date(now()).toISOString();
        memberEvents.push({
          ...stamp(),
          member_id: item.id,
          event_type:
            key === "membership_status"
              ? "membership_changed"
              : "visibility_changed",
          revision: item.revision,
          reason,
          changes: { before, after: command.state },
        });
      }
      result = { id: item.id, revision: item.revision };
      if (notificationId) result.notification_id = notificationId;
      requests.set(requestId, {
        actor: actor.id,
        command: serialized,
        result: structuredClone(result),
      });
      return result;
    },
  };
}
