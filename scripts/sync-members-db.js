// Bring the existing OpenCivics "Membership Application Database" up to the
// schema the Regen Commons site expects, while preserving its existing field
// names, options, and any historical applications.
//
// What this script does:
//   • Renames a few properties to fix trailing spaces and a typo
//   • Adds the small set of properties that don't yet exist (Status, Focus areas, etc.)
//   • Tops up select / multi-select options with anything missing
//   • Reports extras (existing properties unused by the site) but never deletes them
//
// Default mode is read-only. Pass --apply to actually make changes.
//
// Usage:
//   NOTION_TOKEN=secret_… node scripts/sync-members-db.js <db-id>
//   NOTION_TOKEN=secret_… node scripts/sync-members-db.js <db-id> --apply

import { Client } from "@notionhq/client";

const TOKEN = process.env.NOTION_TOKEN;
const DB_ID = process.argv[2];
const APPLY = process.argv.includes("--apply");

if (!TOKEN) {
  console.error("ERROR: NOTION_TOKEN env var is required.");
  process.exit(1);
}
if (!DB_ID || DB_ID.startsWith("--")) {
  console.error("Usage: node scripts/sync-members-db.js <database-id> [--apply]");
  process.exit(1);
}

const notion = new Client({ auth: TOKEN });

// ─── Trailing-space & typo fixes (renames) ───────────────────────────────────
const RENAMES = {
  "Telegram ": "Telegram",
  "Meaningful Participation ": "Meaningful Participation",
  "Participation Constriant": "Participation Constraint",
};

// ─── Final expected schema (after renames are applied) ───────────────────────
// Existing OpenCivics property names are kept as-is. Only "fix" renames above
// and brand-new additions below are introduced by this script.
const EXPECTED = {
  // Title
  "Org/Individual Name":                          { type: "title" },

  // Existing selects (keep names; ensure options exist)
  "Membership Type":                              { type: "select",       options: ["Individual", "Organization"] },
  "Participation Commitment":                     { type: "select",       options: ["Yes", "Yes with constraints", "Unsure"] },
  "Decision making authorization":                { type: "select",       options: ["Yes", "Yes with limits"] },
  "Membership Agreement Reviewed":                { type: "select",       options: ["Yes", "Has questions"] },
  "Consent to Governance Protocol":               { type: "select",       options: ["Yes", "Has questions"] },

  // Existing multi-select (keep name; ensure options exist)
  "Contribution to Commons' Work":                { type: "multi_select", options: [
    "Governance design", "Community facilitation", "Knowledge sharing",
    "Project development", "Cultural stewardship", "Communications", "Other",
  ]},

  // Existing URL
  "Website/Portfolio":                            { type: "url" },

  // Existing rich-text fields (post-rename names)
  "Based In":                                     { type: "rich_text" },
  "Telegram":                                     { type: "url" },
  "Name and Role of Org Rep":                     { type: "rich_text" },
  "Org mission, Size and activities":             { type: "rich_text" },
  "Invited By":                                   { type: "rich_text" },
  "Relationship to Regenerative work":            { type: "rich_text" },
  "Alignment with Core Values":                   { type: "rich_text" },
  "Meaningful Participation":                     { type: "rich_text" },
  "Pathways to Contribution":                     { type: "rich_text" },
  "Participation Constraint":                     { type: "rich_text" },
  "Colleague Name/Email":                         { type: "rich_text" },
  "Membership Agreement Question":                { type: "rich_text" },
  "Governance Protocol Question":                 { type: "rich_text" },
  "Anything else for Steward Council to Know?":   { type: "rich_text" },

  // ─── New properties (truly missing — added by this script) ───────────────
  "Status":                                       { type: "select",       options: ["Pending", "Active", "Steward", "Archived"] },
  "Focus areas":                                  { type: "multi_select", options: [
    "Ecological restoration", "Regenerative agriculture", "Governance & coordination",
    "Regenerative finance", "Community building", "Education & knowledge",
    "Technology & infrastructure", "Indigenous & traditional knowledge",
    "Health & wellbeing", "Arts & culture", "Policy & advocacy", "Other",
  ]},
  "Avatar":                                       { type: "files" },
  "Date Applied":                                 { type: "date" },
  "Email":                                        { type: "email" },
  "Contribution other":                           { type: "rich_text" },
  "Affiliations":                                 { type: "relation",     self: true },

  // Note: a "Contributions" relation pointing to the (future) Contributions
  // database will be added by a separate script once that DB exists.
};

function buildPropertySchema(def) {
  switch (def.type) {
    case "title":        return { title: {} };
    case "rich_text":    return { rich_text: {} };
    case "url":          return { url: {} };
    case "email":        return { email: {} };
    case "date":         return { date: {} };
    case "files":        return { files: {} };
    case "select":       return { select:       { options: def.options.map((n) => ({ name: n })) } };
    case "multi_select": return { multi_select: { options: def.options.map((n) => ({ name: n })) } };
    case "relation":     return {
      relation: {
        database_id: DB_ID,
        type: "single_property",
        single_property: {},
      },
    };
  }
}

function pad(s, n) { return (s + " ".repeat(n)).slice(0, n); }

async function main() {
  console.log(`\nInspecting database ${DB_ID}…\n`);
  let db;
  try {
    db = await notion.databases.retrieve({ database_id: DB_ID });
  } catch (err) {
    console.error("Failed to retrieve database:", err.message);
    if (err.code === "object_not_found" || err.status === 404) {
      console.error("\nMost likely cause: the integration isn't connected to this database yet.");
      console.error("In Notion: open the DB → ⋯ (top-right) → Connections → add 'Regen Commons Site' → Confirm.");
    }
    process.exit(1);
  }

  const dbTitle = db.title?.[0]?.plain_text || "(untitled)";
  console.log(`Database: ${dbTitle}\n`);

  const present = db.properties;
  const updates = {};
  const issues = [];

  // 1. Renames
  for (const [oldName, newName] of Object.entries(RENAMES)) {
    if (present[oldName]) {
      if (present[newName]) {
        issues.push(`! RENAME-CONFLICT  Both "${oldName}" and "${newName}" exist. Manual cleanup needed.`);
      } else {
        console.log(`  ↻ RENAME  "${oldName}" → "${newName}"`);
        updates[oldName] = { name: newName };
      }
    }
  }

  // 2. Additions and option top-ups
  let okCount = 0;
  let addCount = 0;
  let optionAddCount = 0;
  for (const [name, def] of Object.entries(EXPECTED)) {
    // Skip if this name will be created via a rename
    const willBeCreatedByRename = Object.values(RENAMES).includes(name) && Object.entries(RENAMES).some(([oldN, newN]) => newN === name && present[oldN]);
    if (willBeCreatedByRename) {
      console.log(`  ✓ OK      ${pad(name, 42)} (${def.type}, post-rename)`);
      okCount++;
      continue;
    }

    const cur = present[name];

    if (!cur) {
      console.log(`  + ADD     ${pad(name, 42)} (${def.type})`);
      updates[name] = buildPropertySchema(def);
      addCount++;
      continue;
    }

    if (cur.type !== def.type) {
      issues.push(`! TYPE     ${pad(name, 42)} current=${cur.type}, expected=${def.type} (manual fix)`);
      continue;
    }

    if (def.type === "select" || def.type === "multi_select") {
      const norm = (s) => s.trim().toLowerCase();
      const have = new Set((cur[def.type].options || []).map((o) => norm(o.name)));
      const missing = def.options.filter((o) => !have.has(norm(o)));
      if (missing.length) {
        console.log(`  ~ OPTIONS ${pad(name, 42)} adding: ${missing.join(", ")}`);
        const merged = [
          ...(cur[def.type].options || []).map((o) => ({ name: o.name })),
          ...missing.map((n) => ({ name: n })),
        ];
        updates[name] = { [def.type]: { options: merged } };
        optionAddCount += missing.length;
        continue;
      }
    }

    okCount++;
  }

  // 3. Extras
  const expectedNames = new Set(Object.keys(EXPECTED));
  const renameSources = new Set(Object.keys(RENAMES));
  const extras = Object.keys(present).filter(
    (n) => !expectedNames.has(n) && !renameSources.has(n)
  );

  console.log("");
  console.log(`Summary:`);
  console.log(`  ${okCount} properties already match`);
  console.log(`  ${addCount} properties to add`);
  console.log(`  ${Object.keys(RENAMES).filter((n) => present[n] && !present[RENAMES[n]]).length} properties to rename`);
  console.log(`  ${optionAddCount} select / multi-select options to add`);
  console.log(`  ${issues.length} issues needing attention`);
  console.log(`  ${extras.length} extra properties (kept as-is)`);

  if (issues.length) {
    console.log("\nIssues:");
    issues.forEach((i) => console.log("  " + i));
  }
  if (extras.length) {
    console.log("\nExtra properties on the DB (unused by site, kept):");
    extras.forEach((e) => console.log("  · " + e));
  }

  if (Object.keys(updates).length === 0) {
    console.log("\nNothing to apply. ✓");
    return;
  }

  if (!APPLY) {
    console.log("\nRun again with --apply to make these changes.");
    return;
  }

  console.log("\nApplying…");
  await notion.databases.update({
    database_id: DB_ID,
    properties: updates,
  });
  console.log("Done.");
}

main().catch((err) => {
  console.error("\nERROR:", err.message);
  if (err.body) console.error(err.body);
  process.exit(1);
});
