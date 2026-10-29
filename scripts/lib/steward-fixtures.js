import { randomUUID } from "node:crypto";
import { AdminError } from "../../api/_lib/steward-data.js";

// Local-only provider. This module is never imported by production handlers.
export function createStewardFixtures({ now = Date.now } = {}) {
  const ids = {
    application: "10000000-0000-4000-8000-000000000001",
    person: "20000000-0000-4000-8000-000000000001",
    organization: "20000000-0000-4000-8000-000000000002",
  };
  const applications = [
    {
      id: ids.application,
      display_name: "River Morgan",
      applicant_type: "individual",
      email: "river@example.test",
      submitted_at: "2026-10-28T10:00:00Z",
      review_state: "pending",
      cohort: "Autumn 2026",
      nominator: "Demo Gardener",
      revision: 1,
      answers_schema_version: 1,
      member_id: ids.person,
      original_answers: {
        "regen-relationship":
          "I help neighbours restore their watershed. This original answer is private.",
        "values-resonance":
          "Care for place, shared learning, and accountable decisions.",
        "meaningful-participation": "Monthly seed-sharing sessions.",
        constraints: "Private demo answer: limited availability in winter.",
        telegram: "@synthetic_river",
        "closing-notes": "All names and answers in this demo are invented.",
      },
    },
    {
      id: "10000000-0000-4000-8000-000000000002",
      display_name: "Watershed Collective",
      applicant_type: "organization",
      email: "collective@example.test",
      submitted_at: "2026-10-27T12:00:00Z",
      review_state: "pending",
      cohort: "Autumn 2026",
      nominator: "Demo Community Garden",
      revision: 1,
      answers_schema_version: 1,
      member_id: null,
      original_answers: {
        "org-rep": "Sam, community facilitator",
        "org-description":
          "A synthetic group working on watershed restoration.",
        "governance-consent": "questions",
        "closing-notes": "We would like to understand the council process.",
      },
    },
    {
      id: "10000000-0000-4000-8000-000000000003",
      display_name: "Alex Rowan",
      applicant_type: "individual",
      email: "alex@example.test",
      submitted_at: "2026-10-26T09:00:00Z",
      review_state: "pending",
      cohort: "Autumn 2026",
      nominator: null,
      revision: 1,
      answers_schema_version: 1,
      member_id: null,
      original_answers: {
        "capital-contribution": "A community library of practical tools.",
      },
    },
  ];
  const members = [
    {
      id: ids.person,
      name: "River Morgan",
      member_type: "individual",
      publication_state: "draft",
      location: "Example watershed",
      summary: "A curated demonstration profile about community seed sharing.",
      website: "https://example.test",
      focus_areas: ["Ecological restoration"],
      contribution_areas: ["Knowledge sharing"],
    },
    {
      id: ids.organization,
      name: "Demo Community Garden",
      member_type: "organization",
      publication_state: "published",
      location: "Example bioregion",
      summary: "Growing local relationships through care for land.",
      website: null,
      focus_areas: ["Community building"],
      contribution_areas: ["Community facilitation"],
    },
  ];
  const relationships = {
    affiliations: [
      { member_id: ids.person, organization_id: ids.organization },
    ],
    contributions: [
      {
        id: "30000000-0000-4000-8000-000000000001",
        title: "Demo seed-sharing guide",
        publication_state: "draft",
      },
    ],
    contributionMembers: [
      {
        contribution_id: "30000000-0000-4000-8000-000000000001",
        member_id: ids.person,
      },
    ],
  };
  const users = new Map([
    [
      "steward@example.test",
      { id: randomUUID(), email: "steward@example.test", active: true },
    ],
    [
      "visitor@example.test",
      { id: randomUUID(), email: "visitor@example.test", active: false },
    ],
  ]);
  const codes = new Map(),
    sessions = new Map();
  return {
    ids,
    setActive(email, active) {
      users.get(email).active = active;
    },
    async requestCode(email) {
      if (users.has(email))
        codes.set(email, { expires: now() + 600000, attempts: 0 });
    },
    async verifyCode(email, token) {
      const code = codes.get(email);
      if (
        !code ||
        code.expires <= now() ||
        ++code.attempts > 5 ||
        token !== "123456"
      )
        throw new AdminError(401, "invalid_code");
      codes.delete(email);
      const sessionToken = randomUUID();
      sessions.set(sessionToken, { email, expires: now() + 3600000 });
      return { token: sessionToken, expiresIn: 3600 };
    },
    async authorize(token) {
      const session = sessions.get(token);
      if (!session || session.expires <= now())
        throw new AdminError(401, "sign_in_required");
      const user = users.get(session.email);
      if (!user?.active) throw new AdminError(403, "steward_required");
      return { id: user.id, email: user.email };
    },
    async signOut(token) {
      sessions.delete(token);
    },
    async applications(token, { search, type, state, offset }) {
      await this.authorize(token);
      const filtered = applications.filter(
        (row) =>
          row.display_name.toLowerCase().includes(search.toLowerCase()) &&
          (!type || type === row.applicant_type) &&
          (!state || state === row.review_state),
      );
      return {
        applications: filtered
          .slice(offset, offset + 25)
          .map(
            ({ email, original_answers, answers_schema_version, ...summary }) =>
              summary,
          ),
        total: filtered.length,
        offset,
      };
    },
    async application(token, id) {
      await this.authorize(token);
      const application = applications.find((row) => row.id === id);
      if (!application) throw new AdminError(404, "application_not_found");
      return structuredClone({
        application,
        profile:
          members.find((row) => row.id === application.member_id) || null,
        history: [
          {
            id: randomUUID(),
            event_type: "demo_capture",
            reviewed_revision: 1,
            created_at: application.submitted_at,
            note: "Synthetic application loaded for this local preview. No approval has been recorded.",
          },
        ],
      });
    },
    async members(token) {
      await this.authorize(token);
      return structuredClone({ members, ...relationships });
    },
  };
}
