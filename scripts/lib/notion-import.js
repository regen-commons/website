import { readFile, readdir, lstat } from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { parseCsv } from "./notion-export.js";

const collections = [
  ["members", "Membership Application Database", "Org/Individual Name"],
  ["contributions", "Contributions", "Title"],
  ["seeds", "Seeds", "Text"],
  [
    "feedback",
    "Participant Feedback",
    "How much have the objectives of this process have been achieved?",
  ],
];
export const digest = (value) =>
  createHash("sha256").update(value).digest("hex");
export function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object")
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`)
      .join(",")}}`;
  return JSON.stringify(value);
}
function targetId(source) {
  const hex = digest(`regen-commons-import-v1:${source}`)
    .slice(0, 32)
    .split("");
  hex[12] = "5";
  hex[16] = ((parseInt(hex[16], 16) & 3) | 8).toString(16);
  const id = hex.join("");
  return `${id.slice(0, 8)}-${id.slice(8, 12)}-${id.slice(12, 16)}-${id.slice(16, 20)}-${id.slice(20)}`;
}
const sourceId = (path) =>
  path.match(/([a-f\d]{32})(?:_all)?\.(?:csv|md)$/i)?.[1]?.toLowerCase();
const clean = (value = "") => value.replace(/\r\n/g, "\n").trim();
export const relationIds = (value = "") =>
  [
    ...new Set(
      [...value.matchAll(/([a-f\d]{32})\.(?:csv|md)/gi)].map((m) =>
        m[1].toLowerCase(),
      ),
    ),
  ].sort();
function requiredRelations(value) {
  const ids = relationIds(value);
  if (clean(value) && !ids.length)
    throw new Error("Relation has no source identity");
  return ids;
}
const list = (value = "") =>
  value
    ? value
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean)
    : [];
function dateOnly(value) {
  if (!value) return null;
  const months = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];
  const match = value.match(/^(\w+) (\d{1,2}), (\d{4})$/);
  if (!match || !months.includes(match[1]))
    throw new Error(
      "Unrecognized date; preserve the source instead of guessing",
    );
  const iso = `${match[3]}-${String(months.indexOf(match[1]) + 1).padStart(2, "0")}-${match[2].padStart(2, "0")}`;
  if (new Date(`${iso}T00:00:00Z`).toISOString().slice(0, 10) !== iso)
    throw new Error("Invalid calendar date");
  return iso;
}
function publication(status, seed = false) {
  if (status === "Active") return "published";
  if (!status) return seed ? "hidden" : "draft";
  if (["Archived", "Hidden", "Inactive"].includes(status)) return "hidden";
  throw new Error("Unmapped publication status");
}
// Only known property names start a field. Colons inside free-text answers stay text.
export function markdownProperties(text, headers) {
  const fields = {},
    lines = text.replace(/\r\n/g, "\n").split("\n");
  let key = null;
  for (const line of lines.slice(1)) {
    const next = headers.find(
      (header) => line.startsWith(`${header}: `) || line === `${header}:`,
    );
    if (next) {
      if (Object.hasOwn(fields, next))
        throw new Error("Repeated Markdown property");
      key = next;
      fields[key] = line.slice(next.length + 1).replace(/^ /, "");
    } else if (key) fields[key] += `\n${line}`;
  }
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, clean(value)]),
  );
}
function sameField(left, right, key) {
  if (["Affiliations", "Contributions", "Contributor"].includes(key))
    return canonical(relationIds(left)) === canonical(relationIds(right));
  return clean(left) === clean(right);
}
async function file(root, relative) {
  const stat = await lstat(join(root, relative));
  if (!stat.isFile() || stat.isSymbolicLink())
    throw new Error("Import sources must be regular files, without symlinks");
  const bytes = await readFile(join(root, relative));
  return {
    path: relative,
    bytes: bytes.length,
    sha256: digest(bytes),
    content: new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(
      bytes,
    ),
  };
}
async function loadCollection(root, [kind, folder, title]) {
  const paths = (await readdir(root))
    .filter((path) => path.startsWith(`${folder} `) && /\.csv$/i.test(path))
    .sort();
  if (!paths.length) throw new Error(`Missing ${kind} CSV`);
  const files = await Promise.all(paths.map((path) => file(root, path)));
  const views = files.map((source) => ({
    source,
    ...parseCsv(source.content),
  }));
  const full =
    views.find((view) => view.source.path.endsWith("_all.csv")) || views[0];
  const dbid = sourceId(full.source.path);
  if (!dbid || views.some((view) => sourceId(view.source.path) !== dbid))
    throw new Error("Ambiguous collection identity");
  for (const view of views) {
    if (view.headers.some((key) => !full.headers.includes(key)))
      throw new Error("CSV projection has fields absent from the full export");
    const projected = full.records
      .map((row) =>
        canonical(
          Object.fromEntries(view.headers.map((key) => [key, row[key]])),
        ),
      )
      .sort();
    if (canonical(projected) !== canonical(view.records.map(canonical).sort()))
      throw new Error("CSV views disagree; reconcile before import");
  }
  const stat = await lstat(join(root, folder));
  if (!stat.isDirectory() || stat.isSymbolicLink())
    throw new Error("Source directory cannot be a symlink");
  const names = (await readdir(join(root, folder))).sort();
  if (names.some((name) => !name.endsWith(".md")))
    throw new Error(
      "Unmapped attachment or nested export: extend the import before proceeding",
    );
  const pages = await Promise.all(
    names.map((name) => file(root, `${folder}/${name}`)),
  );
  files.push(...pages);
  const used = new Set();
  const records = [];
  for (const page of pages) {
    const id = sourceId(page.path),
      heading = page.content.split("\n")[0].replace(/^# /, ""),
      properties = markdownProperties(page.content, full.headers);
    if (!id || records.some((row) => row.id === id))
      throw new Error("Missing or duplicate Notion page identity");
    const candidates = full.records
      .map((row, index) => ({ row, index }))
      .filter(
        ({ row, index }) =>
          !used.has(index) &&
          (kind === "feedback" || clean(row[title]) === clean(heading)) &&
          Object.entries(properties).every(([key, value]) =>
            sameField(row[key], value, key),
          ),
      );
    if (candidates.length !== 1)
      throw new Error(
        `Cannot uniquely reconcile ${kind} page ${id} (${candidates.length} candidates)`,
      );
    used.add(candidates[0].index);
    const row = candidates[0].row;
    // Absence of a property in Markdown must not hide conflicting source data.
    for (const key of full.headers) {
      if (key !== title && clean(row[key]) && !Object.hasOwn(properties, key))
        throw new Error(`Markdown missing populated ${kind} property ${key}`);
    }
    records.push({ id, row, markdown: page, database_id: dbid });
  }
  if (used.size !== full.records.length)
    throw new Error(`Unmatched ${kind} CSV rows`);
  return { kind, files, records };
}

export async function prepareImport(root, decisions, recovered) {
  if (decisions.version !== 1 || !Array.isArray(recovered))
    throw new Error("Unsupported import input");
  const sources = await Promise.all(
    collections.map((collection) => loadCollection(root, collection)),
  );
  const byKind = Object.fromEntries(
    sources.map((source) => [source.kind, source.records]),
  );
  const allIds = sources.flatMap((source) =>
    source.records.map((record) => record.id),
  );
  if (new Set(allIds).size !== allIds.length)
    throw new Error("Notion page occurs in multiple collections");
  const memberSources = new Map(
    byKind.members.map((member) => [member.id, member]),
  );
  const aliases = decisions.member_aliases || {};
  for (const [alias, destination] of Object.entries(aliases)) {
    if (
      !memberSources.has(alias) ||
      !memberSources.has(destination) ||
      aliases[destination] ||
      alias === destination
    )
      throw new Error("Invalid or chained member merge");
    const record = memberSources.get(alias).row;
    if (record.Email || record["Date Applied"] || record.Status)
      throw new Error(
        "A complete application cannot be discarded by a profile merge",
      );
    const destinationRow = memberSources.get(destination).row;
    const aliasType =
      record["Membership Type"].toLowerCase() ||
      decisions.member_types?.[alias];
    const destinationType =
      destinationRow["Membership Type"].toLowerCase() ||
      decisions.member_types?.[destination];
    if (aliasType !== destinationType)
      throw new Error("Member merge has conflicting types");
  }
  const memberId = (id) => {
    if (!memberSources.has(id))
      throw new Error(`Unresolved member relation ${id}`);
    return targetId(`member:${aliases[id] || id}`);
  };
  const members = [],
    applications = [],
    contributions = [],
    seeds = [],
    archive = [];
  const addArchive = (source_id, collection, payload, target_id = null) =>
    archive.push({
      source_id,
      collection,
      checksum: digest(canonical(payload)),
      payload,
      target_id,
    });
  for (const record of byKind.members) {
    const { row, id } = record,
      type =
        row["Membership Type"].toLowerCase() || decisions.member_types?.[id];
    if (!["individual", "organization"].includes(type))
      throw new Error(`Member type requires a decision for ${id}`);
    if (!aliases[id])
      members.push({
        id: memberId(id),
        source_notion_id: id,
        name: row["Org/Individual Name"],
        member_type: type,
        publication_state: publication(row.Status),
        location: row["Based In"],
        summary: "",
        vision: row["Relationship to Regenerative work"],
        website: row["Website/Portfolio"] || null,
        avatar: row.Avatar || null,
        focus_areas: list(row["Focus areas"]),
        contribution_areas: list(row["Contribution to Commons' Work"]),
        applied_at: dateOnly(row["Date Applied"]),
      });
    if (row.Email || row["Date Applied"])
      applications.push({
        id: targetId(`application:${id}`),
        source_notion_id: id,
        display_name: row["Org/Individual Name"],
        applicant_type: type,
        email: row.Email || null,
        submitted_at: null,
        review_state: row.Status
          ? `legacy_${row.Status.toLowerCase()}`
          : "pending",
        nominator: row["Vouched By"] || null,
        original_answers: row,
        member_id: memberId(id),
      });
    addArchive(
      `notion:${id}`,
      "members",
      {
        database_id: record.database_id,
        row,
        markdown: record.markdown.path,
        source_checksum: record.markdown.sha256,
        member_type: type,
        canonical_source_id: aliases[id] || id,
        application_id:
          applications.find((app) => app.source_notion_id === id)?.id || null,
      },
      memberId(id),
    );
  }
  const contributionSources = new Map(
    byKind.contributions.map((item) => [item.id, item]),
  );
  const edges = new Set(),
    reverseEdges = new Set(),
    affiliations = new Set();
  for (const record of byKind.contributions) {
    const { row, id } = record;
    const target = {
      id: targetId(`contribution:${id}`),
      source_notion_id: id,
      title: row.Title,
      publication_state: publication(row.Status),
      description: row.Description,
      contribution_type: row.Type || null,
      stage: row.Stage || null,
      capital_forms: list(row["Capital form"]),
      tier: row.Tier || null,
      terms: row.Terms || null,
      license: row.License || null,
      tags: list(row.Tags),
      contributed_at: null,
    };
    if (row["Date contributed"])
      throw new Error("Contribution timestamp needs explicit timezone mapping");
    contributions.push(target);
    for (const member of requiredRelations(row.Contributor)) {
      memberId(member);
      edges.add(`${id}:${member}`);
    }
    addArchive(
      `notion:${id}`,
      "contributions",
      {
        database_id: record.database_id,
        row,
        markdown: record.markdown.path,
        source_checksum: record.markdown.sha256,
      },
      target.id,
    );
  }
  for (const { id, row } of byKind.members) {
    for (const contribution of requiredRelations(row.Contributions)) {
      if (!contributionSources.has(contribution))
        throw new Error(`Unresolved Contribution ${contribution}`);
      reverseEdges.add(`${contribution}:${id}`);
    }
    for (const organization of requiredRelations(row.Affiliations)) {
      const target = members.find((m) => m.id === memberId(organization));
      if (target.member_type !== "organization" || memberId(id) === target.id)
        throw new Error("Invalid organization affiliation");
      affiliations.add(`${memberId(id)}:${target.id}`);
    }
  }
  if (canonical([...edges].sort()) !== canonical([...reverseEdges].sort()))
    throw new Error("Forward and reverse Contribution relations disagree");
  for (const record of byKind.seeds) {
    const { id, row } = record;
    if (row.Text.length < 3 || row.Text.length > 240)
      throw new Error("Legacy Seed exceeds the current text contract");
    const target = {
      id: targetId(`seed:${id}`),
      source_notion_id: id,
      text: row.Text,
      author: row.Author || "",
      tags: list(row.Tags),
      publication_state: publication(row.Status, true),
    };
    seeds.push(target);
    addArchive(
      `notion:${id}`,
      "seeds",
      {
        database_id: record.database_id,
        row,
        markdown: record.markdown.path,
        source_checksum: record.markdown.sha256,
      },
      target.id,
    );
  }
  for (const record of byKind.feedback)
    addArchive(`notion:${record.id}`, "feedback", {
      database_id: record.database_id,
      row: record.row,
      markdown: record.markdown.path,
      source_checksum: record.markdown.sha256,
    });
  const recoveryIds = new Set(),
    recoveryEmails = new Set();
  const existingEmails = new Set(
    applications.map((app) => app.email?.trim().toLowerCase()).filter(Boolean),
  );
  for (const recovery of recovered) {
    const { source_id, answers, error } = recovery,
      email = answers?.email?.trim().toLowerCase();
    if (
      !source_id ||
      typeof source_id !== "string" ||
      typeof error !== "string" ||
      recoveryIds.has(source_id) ||
      !answers?.["full-name"]?.trim() ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email || "") ||
      !["individual", "organization"].includes(answers?.["applicant-type"])
    )
      throw new Error("Invalid recovered application");
    if (existingEmails.has(email) || recoveryEmails.has(email))
      throw new Error(
        "Recovered email overlaps another application; explicit reconciliation required",
      );
    recoveryIds.add(source_id);
    recoveryEmails.add(email);
    const id = targetId(`recovered:${source_id}`);
    applications.push({
      id,
      source_notion_id: null,
      display_name: answers["full-name"].trim(),
      applicant_type: answers["applicant-type"],
      email: answers.email,
      submitted_at: null,
      review_state: "pending",
      nominator: answers.nominator || null,
      original_answers: answers,
      member_id: null,
    });
    addArchive(
      `recovered:${source_id}`,
      "recovered_applications",
      { answers, error, source: recovery.source || null, submitted_at: null },
      id,
    );
  }
  const files = sources
    .flatMap((source) => source.files)
    .sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  const snapshot = digest(
    canonical(
      files.map(({ path, sha256, bytes }) => ({ path, sha256, bytes })),
    ),
  );
  for (const source of files)
    addArchive(
      `file:${snapshot}:${digest(source.path)}`,
      "source_files",
      source,
    );
  const contribution_members = [
    ...new Set(
      [...edges].map((edge) => {
        const [contribution, member] = edge.split(":");
        return `${targetId(`contribution:${contribution}`)}:${memberId(member)}`;
      }),
    ),
  ]
    .sort()
    .map((edge) => {
      const [contribution_id, member_id] = edge.split(":");
      return { contribution_id, member_id };
    });
  const plan = {
    version: 1,
    snapshot,
    decisions,
    members,
    applications,
    contributions,
    seeds,
    contribution_members,
    affiliations: [...affiliations].sort().map((edge) => {
      const [member_id, organization_id] = edge.split(":");
      return { member_id, organization_id };
    }),
    archive,
  };
  const summary = {
    source_records:
      byKind.members.length +
      byKind.contributions.length +
      byKind.seeds.length +
      byKind.feedback.length,
    source_files: files.length,
    source_bytes: files.reduce((sum, f) => sum + f.bytes, 0),
    members: members.length,
    published_members: members.filter(
      (m) => m.publication_state === "published",
    ).length,
    applications: applications.length,
    recovered_applications: recovered.length,
    contributions: contributions.length,
    seeds: seeds.length,
    feedback: byKind.feedback.length,
    contributor_links: contribution_members.length,
    affiliations: affiliations.size,
    merged_member_sources: Object.keys(aliases).length,
  };
  plan.summary = summary;
  // Include the mapping decisions in the replay identity, separate from source capture identity.
  plan.checksum = digest(canonical(plan));
  return plan;
}

const tables = {
  members: [
    "id",
    "source_notion_id",
    "name",
    "member_type",
    "publication_state",
    "location",
    "summary",
    "vision",
    "website",
    "avatar",
    "focus_areas",
    "contribution_areas",
    "applied_at",
  ],
  applications: [
    "id",
    "source_notion_id",
    "display_name",
    "applicant_type",
    "email",
    "submitted_at",
    "review_state",
    "nominator",
    "original_answers",
    "member_id",
  ],
  contributions: [
    "id",
    "source_notion_id",
    "title",
    "publication_state",
    "description",
    "contribution_type",
    "stage",
    "capital_forms",
    "tier",
    "terms",
    "license",
    "tags",
    "contributed_at",
  ],
  seeds: [
    "id",
    "source_notion_id",
    "text",
    "author",
    "tags",
    "publication_state",
  ],
  contribution_members: ["contribution_id", "member_id"],
  affiliations: ["member_id", "organization_id"],
};
const quote = (value) =>
  `E'${value.replaceAll("\\", "\\\\").replaceAll("'", "''")}'`;
const literal = (value) => `${quote(JSON.stringify(value))}::jsonb`;
function verifyPlan(plan) {
  const { checksum, ...content } = plan;
  if (digest(canonical(content)) !== checksum)
    throw new Error("Import plan checksum changed");
}
export function importSql(plan, staged = false) {
  verifyPlan(plan);
  // One transaction is a complete import. A repeat skips everything, preserving later steward edits.
  const key = `batch:${plan.checksum}`;
  const stagePrefix = `stage:${plan.checksum}:`;
  const transport = JSON.stringify(plan);
  const tag = `$import_${plan.checksum}$`;
  const statements = [
    "begin;",
    "set local lock_timeout='3s';",
    "set local statement_timeout='60s';",
    "select pg_advisory_xact_lock(hashtextextended('regen-commons-notion-import',0));",
    `do ${tag} declare p jsonb; transport text; begin if not exists(select 1 from private.import_records where source_id='${key}') then`,
    `if exists(select 1 from private.import_records where source_id like 'batch:%') then raise exception 'Different import already recorded; reconcile explicitly'; end if;`,
  ];
  if (staged)
    statements.push(
      `select string_agg(payload->>'content','' order by source_id) into transport from private.import_records where source_id like '${stagePrefix}%';`,
      `if transport is null or encode(sha256(convert_to(transport,'UTF8')),'hex')<>'${digest(transport)}' then raise exception 'Staged import checksum mismatch'; end if;`,
      `p := transport::jsonb;`,
    );
  else statements.push(`p := ${literal(plan)};`);
  statements.push(
    `lock table ${Object.keys(tables)
      .map((t) => `public.${t}`)
      .join(",")} in share row exclusive mode;`,
  );
  for (const table of Object.keys(tables))
    statements.push(
      `if exists(select 1 from public.${table}) then raise exception 'Initial import requires empty ${table}'; end if;`,
    );
  for (const [table, columns] of Object.entries(tables))
    if (plan[table].length)
      statements.push(
        `insert into public.${table}(${columns.join(",")}) select ${columns.join(",")} from jsonb_populate_recordset(null::public.${table},p->'${table}');`,
      );
  // Import evidence is private; do not create fake steward events or notification jobs.
  statements.push(
    `insert into private.import_records(source_id,collection,checksum,payload,target_id) select source_id,collection,checksum,payload,target_id from jsonb_populate_recordset(null::private.import_records,p->'archive');`,
  );
  statements.push(
    `insert into private.import_records(source_id,collection,checksum,payload) values('${key}','import_batches','${plan.checksum}',${literal({ snapshot: plan.snapshot, decisions: plan.decisions, summary: plan.summary })});`,
  );
  statements.push(
    `end if; delete from private.import_records where source_id like '${stagePrefix}%'; end ${tag};`,
    "commit;",
  );
  return statements.join("\n") + "\n";
}
export function stagedImportSql(plan) {
  verifyPlan(plan);
  const points = Array.from(JSON.stringify(plan)),
    stages = [];
  for (let offset = 0; offset < points.length; offset += 20000) {
    const content = points.slice(offset, offset + 20000).join("");
    const row = {
      source_id: `stage:${plan.checksum}:${String(stages.length).padStart(5, "0")}`,
      collection: "import_staging",
      checksum: digest(content),
      payload: { content },
    };
    stages.push(
      `begin; set local lock_timeout='3s';\ninsert into private.import_records(source_id,collection,checksum,payload) values(${quote(row.source_id)},'import_staging','${row.checksum}',${literal(row.payload)}) on conflict(source_id) do nothing;\ncommit;\n`,
    );
  }
  return { stages, apply: importSql(plan, true) };
}
