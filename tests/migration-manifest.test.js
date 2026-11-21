import assert from "node:assert/strict";
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
