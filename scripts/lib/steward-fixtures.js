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
  members.push({
    id: "20000000-0000-4000-8000-000000000003",
    name: "Demo Gardener",
    member_type: "individual",
    publication_state: "published",
    location: "Example bioregion",
    summary: "Synthetic public member.",
    website: null,
    focus_areas: [],
    contribution_areas: [],
  });
  const seeds = [
    {
      id: "40000000-0000-4000-8000-000000000001",
      text: "Demo vision: a thriving commons in every bioregion.",
      author: "Local demo",
      tags: ["Demo"],
      publication_state: "published",
      revision: 1,
      created_at: "2026-10-28T10:00:00Z",
    },
  ];
  relationships.contributions[0] = {
    ...relationships.contributions[0],
    description: "Draft guide",
    tags: [],
    capital_forms: [],
    revision: 1,
    created_at: "2026-10-27T10:00:00Z",
  };
  relationships.contributions.push({
    id: "30000000-0000-4000-8000-000000000002",
    title: "Public demo guide",
    publication_state: "published",
    description: "Synthetic library entry.",
    tags: ["Demo"],
    capital_forms: ["Intellectual"],
    contribution_type: "Knowledge",
    stage: "Sprout",
    revision: 1,
    created_at: "2026-10-28T10:00:00Z",
  });
  relationships.contributionMembers.push({
    contribution_id: "30000000-0000-4000-8000-000000000002",
    member_id: members[2].id,
  });
  const events = [],
    requests = new Map(),
    quotas = new Map();
  const rows = (resource) =>
    resource === "seeds" ? seeds : relationships.contributions;
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
    async publicList(resource) {
      if (resource === "seeds")
        return seeds
          .filter((r) => r.publication_state === "published")
          .map(({ id, text, author, tags }) =>
            structuredClone({ id, text, author, tags }),
          );
      if (resource === "members")
        return members
          .filter((r) => r.publication_state === "published")
          .map((r) => ({
            id: r.id,
            name: r.name,
            type:
              r.member_type === "organization" ? "Organization" : "Individual",
            status: "Active",
            location: r.location,
            focusAreas: r.focus_areas,
            contributionAreas: r.contribution_areas,
            vision: r.vision || "",
            website: r.website || "",
            avatar: "",
            dateApplied: "",
            affiliationIds: relationships.affiliations
              .filter(
                (a) =>
                  a.member_id === r.id &&
                  members.some(
                    (m) =>
                      m.id === a.organization_id &&
                      m.publication_state === "published",
                  ),
              )
              .map((a) => a.organization_id),
          }));
      return relationships.contributions
        .filter((r) => r.publication_state === "published")
        .map((r) => ({
          id: r.id,
          title: r.title,
          type: r.contribution_type || "",
          stage: r.stage || "",
          status: "Active",
          description: r.description,
          capitalForm: r.capital_forms,
          tier: r.tier || "",
          terms: r.terms || "",
          license: r.license || "",
          tags: r.tags,
          dateContributed: r.contributed_at || "",
          contributors: relationships.contributionMembers
            .filter((a) => a.contribution_id === r.id)
            .map((a) =>
              members.find(
                (m) =>
                  m.id === a.member_id && m.publication_state === "published",
              ),
            )
            .filter(Boolean)
            .map((m) => ({ id: m.id, name: m.name })),
        }));
    },
    async submit(kind, requestId, payload, ip) {
      const prior = requests.get(requestId);
      if (prior) {
        if (
          prior.kind !== kind ||
          JSON.stringify(prior.payload) !== JSON.stringify(payload)
        )
          throw new AdminError(409, "request_conflict");
        return { ok: true, id: prior.id };
      }
      const key = kind + ip + Math.floor(now() / 3600000),
        total = quotas.get(key) || 0;
      if (total >= (kind === "seed" ? 6 : 3))
        throw new AdminError(429, "rate_limited");
      quotas.set(key, total + 1);
      const id = randomUUID();
      if (kind === "seed")
        seeds.push({
          id,
          ...payload,
          tags: [],
          publication_state: "published",
          revision: 1,
          created_at: new Date(now()).toISOString(),
        });
      else
        applications.push({
          id,
          display_name: payload["full-name"],
          applicant_type: payload["applicant-type"] || "individual",
          email: payload.email,
          submitted_at: new Date(now()).toISOString(),
          review_state: "pending",
          revision: 1,
          answers_schema_version: 1,
          member_id: null,
          original_answers: structuredClone(payload),
        });
      requests.set(requestId, { kind, payload: structuredClone(payload), id });
      return { ok: true, id };
    },
    async content(
      token,
      resource,
      { search = "", state = "", offset = 0 } = {},
    ) {
      await this.authorize(token);
      const filtered = rows(resource)
        .filter(
          (r) =>
            (r.text || r.title).toLowerCase().includes(search.toLowerCase()) &&
            (!state || r.publication_state === state),
        )
        .sort(
          (a, b) =>
            b.created_at.localeCompare(a.created_at) ||
            a.id.localeCompare(b.id),
        );
      return structuredClone({
        items: filtered.slice(offset, offset + 25),
        total: filtered.length,
        offset,
      });
    },
    async contentDetail(token, resource, id) {
      await this.authorize(token);
      const item = rows(resource).find((r) => r.id === id);
      if (!item) throw new AdminError(404, "content_not_found");
      return structuredClone({
        item,
        history: events.filter(
          (e) => e.resource === resource && e.target_id === id,
        ),
        contributor_ids: relationships.contributionMembers
          .filter((r) => r.contribution_id === id)
          .map((r) => r.member_id),
      });
    },
    async moderate(token, body) {
      const actor = await this.authorize(token),
        item = rows(body.resource).find((r) => r.id === body.id);
      if (!item) throw new AdminError(404, "content_not_found");
      if (item.revision !== body.revision)
        throw new AdminError(409, "revision_conflict");
      if (item.publication_state !== body.state) {
        item.publication_state = body.state;
        item.revision++;
        events.push({
          id: randomUUID(),
          resource: body.resource,
          target_id: item.id,
          actor_id: actor.id,
          actor_label: actor.email,
          action: body.state === "hidden" ? "hidden" : "restored",
          revision: item.revision,
          reason: body.reason,
          created_at: new Date(now()).toISOString(),
        });
      }
      return {
        id: item.id,
        revision: item.revision,
        publication_state: item.publication_state,
      };
    },
    async saveContribution(token, body) {
      const actor = await this.authorize(token);
      const command = JSON.stringify({
          id: body.id,
          revision: body.revision,
          payload: body.payload,
        }),
        prior = requests.get(body.request_id);
      if (prior) {
        if (prior.actor !== actor.id || prior.command !== command)
          throw new AdminError(409, "request_conflict");
        return prior.result;
      }
      let item = relationships.contributions.find((r) => r.id === body.id);
      if (body.id && !item) throw new AdminError(404, "content_not_found");
      if (item && item.revision !== body.revision)
        throw new AdminError(409, "revision_conflict");
      if (
        body.payload.contributor_ids.some(
          (id) => !members.some((m) => m.id === id),
        )
      )
        throw new AdminError(400, "invalid_contributor");
      const isNew = !item;
      if (isNew) {
        item = {
          id: randomUUID(),
          publication_state: "published",
          revision: 0,
          created_at: new Date(now()).toISOString(),
        };
        relationships.contributions.push(item);
      }
      const { contributor_ids, ...fields } = body.payload;
      Object.assign(item, fields, { revision: item.revision + 1 });
      relationships.contributionMembers =
        relationships.contributionMembers.filter(
          (r) => r.contribution_id !== item.id,
        );
      contributor_ids.forEach((id) =>
        relationships.contributionMembers.push({
          contribution_id: item.id,
          member_id: id,
        }),
      );
      events.push({
        id: randomUUID(),
        resource: "contributions",
        target_id: item.id,
        actor_id: actor.id,
        actor_label: actor.email,
        action: isNew ? "created" : "updated",
        revision: item.revision,
        reason: "",
        created_at: new Date(now()).toISOString(),
      });
      const result = { id: item.id, revision: item.revision };
      requests.set(body.request_id, { actor: actor.id, command, result });
      return result;
    },
    async members(token) {
      await this.authorize(token);
      return structuredClone({ members, ...relationships });
    },
  };
}
