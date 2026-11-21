import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";

const root = new URL("..", import.meta.url).pathname;
const migrationsDir = join(root, "supabase/migrations");
const manifest = JSON.parse(readFileSync(join(root, "supabase/migration-manifest.json"), "utf8"));
const sha256 = (file) =>
  createHash("sha256")
    .update(readFileSync(join(migrationsDir, file)))
    .digest("hex");
const owners = new Set(["website", "platform"]);

test("every migration file has a manifest entry with its owner", () => {
  const listed = new Set(manifest.migrations.map((entry) => entry.file));
  for (const file of readdirSync(migrationsDir)
    .filter((name) => name.endsWith(".sql"))
    .sort()) {
    const entry = JSON.stringify({ file, owner: "website or platform", sha256: sha256(file) });
    assert.ok(
      listed.has(file),
      `${file} has no entry in supabase/migration-manifest.json. Add ${entry} with its owner, in the same pull request as the migration.`
    );
  }
  for (const entry of manifest.migrations) {
    assert.ok(
      owners.has(entry.owner),
      `${entry.file}: owner must be website or platform, not ${entry.owner}`
    );
  }
});

test("applied migrations keep their exact bytes", () => {
  const files = new Set(readdirSync(migrationsDir));
  for (const entry of manifest.migrations) {
    assert.ok(
      files.has(entry.file),
      `${entry.file} is in the manifest but not in supabase/migrations. Never delete or rename an applied migration.`
    );
    assert.equal(
      sha256(entry.file),
      entry.sha256,
      `${entry.file} changed after it was recorded. Never edit an applied migration; restore its bytes and add a new migration instead.`
    );
  }
});

test("manifest entries are unique and in version order", () => {
  const names = manifest.migrations.map((entry) => entry.file);
  assert.deepEqual(names, [...new Set(names)].sort());
});

// Editing a migration together with its hash passes the tests above, so CI also
// compares with the base branch: recorded entries never change or disappear,
// and a new migration sorts after every recorded one, as the Supabase CLI
// expects. CI's checkout fetches the base and fails without it; elsewhere it skips.
test("the manifest only gains newer entries compared with the base branch", (t) => {
  const base = process.env.MANIFEST_BASE || `origin/${process.env.GITHUB_BASE_REF || "main"}`;
  const shown = spawnSync("git", ["show", `${base}:supabase/migration-manifest.json`], {
    cwd: root,
    encoding: "utf8",
  });
  if (shown.status !== 0) {
    const reason = shown.stderr.trim();
    // Only a base without a manifest yet may skip in CI; a missing base is a failure there.
    if (/exists on disk, but not in|does not exist in/.test(reason))
      return t.skip(`no manifest at ${base} yet`);
    assert.ok(
      !process.env.CI,
      `cannot read the manifest at ${base}: ${reason}. CI's check job must fetch the base branch.`
    );
    return t.skip(`git cannot read ${base} here: ${reason}`);
  }
  const before = JSON.parse(shown.stdout).migrations;
  const now = new Map(manifest.migrations.map((entry) => [entry.file, entry]));
  for (const entry of before) {
    assert.deepEqual(
      now.get(entry.file),
      entry,
      `${entry.file}: its manifest entry changed or disappeared since ${base}. Applied migrations and their entries never change; add a new migration instead.`
    );
  }
  const last = before
    .map((entry) => entry.file)
    .sort()
    .at(-1);
  for (const entry of manifest.migrations.filter(
    (entry) => !before.some((b) => b.file === entry.file)
  )) {
    assert.ok(
      !last || entry.file > last,
      `${entry.file} sorts before ${last}, the newest migration on ${base}. Give it a newer version.`
    );
  }
});
