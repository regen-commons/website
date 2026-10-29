import { randomUUID } from "node:crypto";

// Loaded only by the local server, before any production handler is imported.
// Deliberately replace inherited credentials as well as ignoring .env files.
process.env.NOTION_TOKEN = "local-fixture-token";
process.env.NOTION_MEMBERS_DB_ID = "fixture-members";
process.env.NOTION_CONTRIBUTIONS_DB_ID = "fixture-contributions";
process.env.NOTION_SEEDS_DB_ID = "fixture-seeds";
for (const key of ["RESEND_API_KEY", "RESEND_FROM_EMAIL", "STEWARD_NOTIFY_EMAILS", "NOTIFY_URL", "NOTIFY_WEBHOOK_SECRET"]) {
  delete process.env[key];
}

const { notion } = await import("../../api/_lib/notion.js");
const text = (value) => [{ type: "text", plain_text: value, text: { content: value } }];
const title = (value) => ({ title: text(value) });
const richText = (value) => ({ rich_text: text(value) });
const select = (name) => ({ select: { name } });
const multi = (...names) => ({ multi_select: names.map((name) => ({ name })) });
const page = (id, properties) => ({ id, properties });

const databases = {
  "fixture-members": [
    page("fixture-garden", {
      "Org/Individual Name": title("Demo Community Garden"),
      "Membership Type": select("Organization"), Status: select("Active"),
      "Based In": richText("Example bioregion"),
      "Focus areas": multi("Ecological restoration"),
      "Contribution to Commons' Work": multi("Community facilitation"),
      "Relationship to Regenerative work": richText("Synthetic member for local development."),
      Email: { email: "private-garden@example.test" },
    }),
    page("fixture-member", {
      "Org/Individual Name": title("Demo Gardener"),
      "Membership Type": select("Individual"), Status: select("Active"),
      "Based In": richText("Example bioregion"),
      "Focus areas": multi("Education & knowledge"),
      "Contribution to Commons' Work": multi("Knowledge sharing"),
      Affiliations: { relation: [{ id: "fixture-garden" }] },
      Email: { email: "private-person@example.test" },
      Telegram: { url: "https://example.test/private-handle" },
    }),
    page("fixture-pending", {
      "Org/Individual Name": title("Demo Pending Applicant"),
      Status: select("Pending"), Email: { email: "pending@example.test" },
    }),
  ],
  "fixture-contributions": [page("fixture-guide", {
    Title: title("Demo seed-sharing guide"), Type: select("Knowledge"),
    Stage: select("Sprout"), Status: select("Active"),
    Description: richText("Synthetic library entry for testing cards and filters."),
    "Capital form": multi("Intellectual"), Tier: select("Tier 1"),
    Terms: richText("Demonstration content only."),
    Contributor: { relation: [{ id: "fixture-member" }] },
    Tags: multi("Demo"),
  })],
  "fixture-seeds": [page("fixture-seed", {
    Text: title("Demo vision: a thriving commons in every bioregion."),
    Author: richText("Local demo"), Status: select("Active"), Tags: multi("Demo"),
  })],
};

// Preserve the actual handlers' validation, projections, and publication filter.
// Only their Notion transport is replaced; unsupported operations fail closed.
notion.request = async () => { throw new Error("Notion network access is disabled in fixture mode"); };
notion.databases.query = async ({ database_id, filter, start_cursor, page_size = 100 }) => {
  if (!databases[database_id]) throw new Error("Unknown fixture database");
  const rows = databases[database_id].filter((row) =>
    row.properties[filter.property]?.select?.name === filter.select.equals);
  const start = Number(start_cursor || 0);
  const results = rows.slice(start, start + page_size);
  const has_more = start + results.length < rows.length;
  return { results, has_more, next_cursor: has_more ? String(start + results.length) : null };
};
notion.pages.retrieve = async ({ page_id }) => {
  const result = Object.values(databases).flat().find((row) => row.id === page_id);
  if (!result) throw new Error("Unknown fixture page");
  return structuredClone(result);
};
notion.pages.create = async ({ parent, properties }) => {
  const rows = databases[parent.database_id];
  if (!rows) throw new Error("Unknown fixture database");
  const saved = structuredClone(properties);
  for (const property of Object.values(saved)) {
    for (const part of property.title || property.rich_text || []) {
      part.plain_text = part.text.content;
    }
  }
  const result = page(randomUUID(), saved);
  rows.push(result);
  return structuredClone(result);
};

export const handlers = Object.fromEntries(await Promise.all(
  ["members", "contributions", "seeds", "apply"].map(async (name) =>
    [`/api/${name}`, (await import(`../../api/${name}.js`)).default]),
));
