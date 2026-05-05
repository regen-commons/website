// Bring the Contributions database in line with the schema the site renders.
//
// Changes:
//   • "Capital form": rich_text → multi_select with 8 forms-of-capital options
//   • "Tier":         rich_text → select with the 4 tier labels
//   • "Terms":        new rich_text property (was missing)
//
// Type changes require deleting and recreating the property, so any existing
// values in "Capital form" or "Tier" will be lost. Run this when the DB is
// still mostly empty (now is the right time).
//
// Default mode is read-only. Pass --apply to make changes.
//
// Usage:
//   NOTION_TOKEN=secret_… node scripts/sync-contributions-db.js <db-id>
//   NOTION_TOKEN=secret_… node scripts/sync-contributions-db.js <db-id> --apply

import { Client } from "@notionhq/client";

const TOKEN = process.env.NOTION_TOKEN;
const DB_ID = process.argv[2];
const APPLY = process.argv.includes("--apply");

if (!TOKEN) {
  console.error("ERROR: NOTION_TOKEN env var is required.");
  process.exit(1);
}
if (!DB_ID || DB_ID.startsWith("--")) {
  console.error("Usage: node scripts/sync-contributions-db.js <database-id> [--apply]");
  process.exit(1);
}

const notion = new Client({ auth: TOKEN });

const CAPITAL_OPTIONS = [
  "Cultural", "Experiential", "Financial", "Intellectual",
  "Living", "Material", "Social", "Spiritual",
];

const TIER_OPTIONS = [
  "Tier 1 · Indexed",
  "Tier 2 · Member-Privileged",
  "Tier 3 · Licensed",
  "Tier 4 · Fully Contributed",
];

async function main() {
  console.log(`\nInspecting Contributions DB ${DB_ID}…\n`);

  const db = await notion.databases.retrieve({ database_id: DB_ID });
  const present = db.properties;

  const cap = present["Capital form"];
  const tier = present["Tier"];
  const terms = present["Terms"];

  const plan = [];

  if (!cap) {
    plan.push("+ ADD     Capital form  (multi_select)");
  } else if (cap.type !== "multi_select") {
    plan.push(`↻ REPLACE Capital form  ${cap.type} → multi_select (existing values WILL be lost)`);
  } else {
    const have = new Set((cap.multi_select.options || []).map((o) => o.name.toLowerCase()));
    const missing = CAPITAL_OPTIONS.filter((o) => !have.has(o.toLowerCase()));
    if (missing.length) plan.push(`~ OPTIONS Capital form  add: ${missing.join(", ")}`);
    else plan.push("✓ OK      Capital form");
  }

  if (!tier) {
    plan.push("+ ADD     Tier          (select)");
  } else if (tier.type !== "select") {
    plan.push(`↻ REPLACE Tier          ${tier.type} → select (existing values WILL be lost)`);
  } else {
    const have = new Set((tier.select.options || []).map((o) => o.name.toLowerCase()));
    const missing = TIER_OPTIONS.filter((o) => !have.has(o.toLowerCase()));
    if (missing.length) plan.push(`~ OPTIONS Tier          add: ${missing.join(", ")}`);
    else plan.push("✓ OK      Tier");
  }

  if (!terms) {
    plan.push("+ ADD     Terms         (rich_text)");
  } else if (terms.type !== "rich_text") {
    plan.push(`! TYPE    Terms          current=${terms.type}, expected=rich_text (manual fix)`);
  } else {
    plan.push("✓ OK      Terms");
  }

  plan.forEach((p) => console.log("  " + p));

  if (!APPLY) {
    console.log("\nRun again with --apply to make these changes.");
    return;
  }

  // Step 1: delete properties that need a type change (you can't change types in place)
  const deleteUpdate = {};
  if (cap && cap.type !== "multi_select") deleteUpdate["Capital form"] = null;
  if (tier && tier.type !== "select")    deleteUpdate["Tier"] = null;
  if (Object.keys(deleteUpdate).length) {
    console.log("\nDeleting old properties…");
    await notion.databases.update({ database_id: DB_ID, properties: deleteUpdate });
  }

  // Step 2: add the desired properties (and top up options on already-correct ones)
  const addUpdate = {};
  addUpdate["Capital form"] = {
    multi_select: { options: CAPITAL_OPTIONS.map((n) => ({ name: n })) },
  };
  addUpdate["Tier"] = {
    select: { options: TIER_OPTIONS.map((n) => ({ name: n })) },
  };
  if (!terms) addUpdate["Terms"] = { rich_text: {} };

  // If the existing prop was already correct type, merge new options with existing
  if (cap && cap.type === "multi_select") {
    const existing = (cap.multi_select.options || []).map((o) => ({ name: o.name }));
    const existingLower = new Set(existing.map((o) => o.name.toLowerCase()));
    const merged = [
      ...existing,
      ...CAPITAL_OPTIONS.filter((n) => !existingLower.has(n.toLowerCase())).map((n) => ({ name: n })),
    ];
    addUpdate["Capital form"] = { multi_select: { options: merged } };
  }
  if (tier && tier.type === "select") {
    const existing = (tier.select.options || []).map((o) => ({ name: o.name }));
    const existingLower = new Set(existing.map((o) => o.name.toLowerCase()));
    const merged = [
      ...existing,
      ...TIER_OPTIONS.filter((n) => !existingLower.has(n.toLowerCase())).map((n) => ({ name: n })),
    ];
    addUpdate["Tier"] = { select: { options: merged } };
  }

  console.log("Applying updates…");
  await notion.databases.update({ database_id: DB_ID, properties: addUpdate });
  console.log("Done.");
}

main().catch((err) => {
  console.error("\nERROR:", err.message);
  if (err.body) console.error(err.body);
  process.exit(1);
});
