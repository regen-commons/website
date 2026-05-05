// Create the Contributions and Seeds databases as children of the parent page,
// then rename the auto-created reverse relation on Members to "Contributions".
//
// Idempotent: skips creation if a database with the target name already exists
// directly under the parent page.
//
// Usage:
//   NOTION_TOKEN=secret_… node scripts/create-contributions-and-seeds-dbs.js \
//       <parent-page-id> [members-db-id]

import { Client } from "@notionhq/client";

const TOKEN = process.env.NOTION_TOKEN;
const PARENT_PAGE_ID = process.argv[2];
const MEMBERS_DB_ID = process.argv[3] || "35606d2570f2804dac92cbdd35603c71";

if (!TOKEN) {
  console.error("ERROR: NOTION_TOKEN env var required.");
  process.exit(1);
}
if (!PARENT_PAGE_ID || PARENT_PAGE_ID.startsWith("--")) {
  console.error("Usage: node scripts/create-contributions-and-seeds-dbs.js <parent-page-id> [members-db-id]");
  process.exit(1);
}

const notion = new Client({ auth: TOKEN });

const stripDashes = (s) => (s || "").replace(/-/g, "");

async function findChildDatabase(parentId, name) {
  const search = await notion.search({
    query: name,
    filter: { property: "object", value: "database" },
    page_size: 100,
  });
  return search.results.find((r) =>
    r.title?.[0]?.plain_text === name &&
    stripDashes(r.parent?.page_id) === stripDashes(parentId)
  );
}

async function ensureDatabase(name, properties) {
  const existing = await findChildDatabase(PARENT_PAGE_ID, name);
  if (existing) {
    console.log(`  ✓ Already exists: "${name}" → ${existing.id}`);
    return existing.id;
  }
  const db = await notion.databases.create({
    parent: { type: "page_id", page_id: PARENT_PAGE_ID },
    title: [{ type: "text", text: { content: name } }],
    properties,
  });
  console.log(`  + Created: "${name}" → ${db.id}`);
  return db.id;
}

async function main() {
  console.log(`\nParent page: ${PARENT_PAGE_ID}`);
  console.log(`Members DB:  ${MEMBERS_DB_ID}\n`);

  console.log("Contributions database…");
  const contributionsId = await ensureDatabase("Contributions", {
    "Title":   { title: {} },
    "Type": {
      select: {
        options: [
          { name: "Knowledge" },
          { name: "Infrastructure" },
          { name: "Brand & IP" },
          { name: "Governance & Legal" },
          { name: "Coordination" },
        ],
      },
    },
    "Stage": {
      select: {
        options: [
          { name: "Seed" },
          { name: "Sprout" },
          { name: "Flowering" },
          { name: "Tree" },
        ],
      },
    },
    "Status": {
      select: {
        options: [
          { name: "Indexed" },
          { name: "In progress" },
          { name: "Curated" },
          { name: "Archived" },
        ],
      },
    },
    "Description":  { rich_text: {} },
    "Capital form": { rich_text: {} },
    "Tier":         { rich_text: {} },
    "Contributor": {
      relation: {
        database_id: MEMBERS_DB_ID,
        type: "dual_property",
        dual_property: {},
      },
    },
    "License": {
      select: {
        options: [
          { name: "CopyFair" },
          { name: "Open source" },
          { name: "Custom" },
        ],
      },
    },
    "Tags":             { multi_select: { options: [] } },
    "Date contributed": { date: {} },
  });

  console.log("\nSeeds database…");
  const seedsId = await ensureDatabase("Seeds", {
    "Text":   { title: {} },
    "Author": { rich_text: {} },
    "Status": {
      select: {
        options: [
          { name: "Active" },
          { name: "Archived" },
        ],
      },
    },
    "Tags":   { multi_select: { options: [] } },
  });

  // Rename the auto-created reverse relation on Members to "Contributions"
  console.log("\nMembers → reverse relation:");
  const members = await notion.databases.retrieve({ database_id: MEMBERS_DB_ID });
  const reverseEntry = Object.entries(members.properties).find(
    ([name, p]) =>
      p.type === "relation" &&
      stripDashes(p.relation?.database_id) === stripDashes(contributionsId) &&
      name !== "Affiliations"
  );

  if (!reverseEntry) {
    console.log(`  ! No reverse relation found pointing to Contributions. The dual_property may not have synced; investigate manually.`);
  } else {
    const [currentName] = reverseEntry;
    if (currentName === "Contributions") {
      console.log(`  ✓ Already named "Contributions"`);
    } else {
      console.log(`  ↻ Renaming "${currentName}" → "Contributions"`);
      await notion.databases.update({
        database_id: MEMBERS_DB_ID,
        properties: { [currentName]: { name: "Contributions" } },
      });
    }
  }

  console.log("\n────────────────────────────────────────");
  console.log("Save these IDs (you'll plug them into Vercel later):");
  console.log("");
  console.log(`  NOTION_MEMBERS_DB_ID=${MEMBERS_DB_ID}`);
  console.log(`  NOTION_CONTRIBUTIONS_DB_ID=${contributionsId}`);
  console.log(`  NOTION_SEEDS_DB_ID=${seedsId}`);
  console.log("────────────────────────────────────────\n");
}

main().catch((err) => {
  console.error("\nERROR:", err.message);
  if (err.code === "object_not_found" || err.status === 404) {
    console.error("\nLikely cause: the integration isn't connected to the parent page.");
    console.error("In Notion: open the parent page → ⋯ → Connections → add 'Regen Commons Site' → Confirm.");
  }
  if (err.body) console.error(err.body);
  process.exit(1);
});
