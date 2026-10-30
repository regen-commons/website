import assert from "node:assert/strict";
import { test } from "node:test";
import { readFile, writeFile, rm, symlink } from "node:fs/promises";
import { join } from "node:path";
import { fixture, ids, csv } from "../scripts/lib/notion-import-fixture.js";
import {
  prepareImport,
  importSql,
  canonical,
  digest,
  markdownProperties,
} from "../scripts/lib/notion-import.js";

async function using(fn) {
  const value = await fixture();
  try {
    await fn(value);
  } finally {
    await rm(value.root, { recursive: true, force: true });
  }
}

test("reconciles reordered CSVs and identity-bearing Markdown, explicit merge and private recovery", async () =>
  using(async ({ root, decisions, recovered }) => {
    const plan = await prepareImport(root, decisions, recovered);
    assert.equal(plan.members.length, 2);
    assert.equal(plan.applications.length, 2);
    assert.equal(plan.members[0].applied_at, "2026-05-06");
    assert.equal(plan.applications[0].submitted_at, null);
    assert.equal(plan.applications[0].review_state, "legacy_active");
    assert.equal(plan.applications[1].review_state, "pending");
    assert.equal(plan.applications[1].member_id, null);
    assert.deepEqual(
      plan.applications[1].original_answers,
      recovered[0].answers,
    );
    const person = plan.members.find((m) => m.source_notion_id === ids.full);
    assert.equal(plan.contribution_members[0].member_id, person.id);
    assert.equal(
      plan.archive.find((r) => r.source_id === `notion:${ids.alias}`).target_id,
      person.id,
    );
    assert.equal(plan.affiliations.length, 1);
    assert.equal(plan.seeds[0].author, "");
    assert.equal(plan.contributions[0].contributed_at, null);
    assert.equal(
      plan.archive.filter((r) => r.collection === "feedback").length,
      1,
    );
    for (const row of plan.archive.filter(
      (r) => r.collection === "source_files",
    )) {
      assert.equal(Buffer.byteLength(row.payload.content), row.payload.bytes);
      assert.equal(digest(row.payload.content), row.payload.sha256);
    }
    assert.equal(
      plan.checksum,
      (await prepareImport(root, decisions, recovered)).checksum,
    );
    assert.match(importSql(plan), /^begin;/);
    assert.match(importSql(plan), /Initial import requires empty members/);
    assert.match(importSql(plan), /Different import already recorded/);
  }));
test("missing member types fail closed without a decision", async () =>
  using(async ({ root, recovered }) => {
    await assert.rejects(
      prepareImport(root, { version: 1 }, recovered),
      /Member type requires/,
    );
  }));
test("CSV view conflicts block import", async () =>
  using(async ({ root, decisions, recovered }) => {
    const p = join(root, `Seeds ${"c".repeat(32)}.csv`);
    await writeFile(
      p,
      csv(
        ["Text", "Status", "Tags"],
        [{ Text: "Different seed", Status: "Active", Tags: "Care" }],
      ),
    );
    await assert.rejects(
      prepareImport(root, decisions, recovered),
      /CSV views disagree/,
    );
  }));
test("recovery overlap needs explicit reconciliation; no email-based silent merge", async () =>
  using(async ({ root, decisions, recovered }) => {
    recovered[0].answers.email = "PERSON@example.test";
    await assert.rejects(
      prepareImport(root, decisions, recovered),
      /overlaps another application/,
    );
  }));
test("unknown attachments and symlink sources cannot be silently omitted", async () =>
  using(async ({ root, decisions, recovered }) => {
    const p = join(root, "Seeds", "unmapped.png");
    await writeFile(p, "Synthetic image placeholder");
    await assert.rejects(
      prepareImport(root, decisions, recovered),
      /Unmapped attachment/,
    );
    await rm(p);
    await symlink(
      join(root, "Seeds", `Page ${ids.seed}.md`),
      join(root, "Seeds", "link.md"),
    );
    await assert.rejects(
      prepareImport(root, decisions, recovered),
      /regular files/,
    );
  }));
test("changed plan refuses SQL generation; source instructions remain quoted data", async () =>
  using(async ({ root, decisions, recovered }) => {
    const plan = await prepareImport(root, decisions, recovered);
    plan.members[0].name = "Changed after review";
    assert.throws(() => importSql(plan), /checksum changed/);
    assert.equal(
      canonical({ b: 1, a: "text" }),
      canonical({ a: "text", b: 1 }),
    );
    assert.deepEqual(
      markdownProperties("# Title\n\nAnswer: first\nSocial: another line\n", [
        "Answer",
      ]),
      { Answer: "first\nSocial: another line" },
    );
  }));

test("forwarded-message provenance is retained privately", async () =>
  using(async ({ root, decisions, recovered }) => {
    recovered[0].source = {
      kind: "forwarded-notification",
      links: [
        {
          field: "website",
          text: "example.test",
          href: "https://example.test/",
        },
      ],
    };
    const plan = await prepareImport(root, decisions, recovered);
    assert.deepEqual(
      plan.archive.find((r) => r.collection === "recovered_applications")
        .payload.source,
      recovered[0].source,
    );
    assert.ok(
      !plan.members.some(
        (member) => member.name === recovered[0].answers["full-name"],
      ),
    );
  }));

test("a merge cannot discard a completed application", async () =>
  using(async ({ root, decisions, recovered }) => {
    decisions.member_aliases = { [ids.full]: ids.alias };
    await assert.rejects(
      prepareImport(root, decisions, recovered),
      /complete application cannot be discarded/,
    );
  }));

test("unresolved contributor identities cannot disappear during import", async () =>
  using(async ({ root, decisions, recovered }) => {
    for (const path of [
      join(root, `Contributions ${"b".repeat(32)}.csv`),
      join(root, `Contributions ${"b".repeat(32)}_all.csv`),
      join(root, "Contributions", `Page ${ids.contribution}.md`),
    ]) {
      await writeFile(
        path,
        (await readFile(path, "utf8")).replaceAll(ids.alias, "f".repeat(32)),
      );
    }
    await assert.rejects(
      prepareImport(root, decisions, recovered),
      /Unresolved member relation/,
    );
  }));
