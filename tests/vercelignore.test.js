import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  deployedFiles,
  excludedInsideDeployed,
  vercelIgnore,
} from "../scripts/lib/vercel-ignore.js";

const root = new URL("..", import.meta.url).pathname;
const git = (...args) => spawnSync("git", args, { cwd: root, encoding: "utf8" });
const lines = (text) => text.split("\n").filter(Boolean);

test(".vercelignore matches the fixture server's public files", () => {
  assert.equal(
    readFileSync(new URL("../.vercelignore", import.meta.url), "utf8"),
    vercelIgnore(),
    "Regenerate it: node -e 'import(\"./scripts/lib/vercel-ignore.js\").then((m) => process.stdout.write(m.vercelIgnore()))' > .vercelignore"
  );
});

// Vercel reads .vercelignore with gitignore rules, so git can show what it
// uploads. The dev machine cannot read a worktree's git metadata; CI can.
test("Vercel uploads the site and API, never docs, migrations or tooling", (t) => {
  const tracked = git("ls-files", "-c");
  if (tracked.status !== 0)
    return t.skip(`git cannot read this checkout here: ${tracked.stderr.trim()}`);
  const ignored = new Set(
    lines(git("ls-files", "-c", "-i", "--exclude-from=.vercelignore").stdout)
  );
  const uploaded = lines(tracked.stdout)
    .filter((file) => !ignored.has(file))
    .sort();
  const apiFiles = lines(tracked.stdout).filter(
    (file) => file.startsWith("api/") && !excludedInsideDeployed.includes(file)
  );
  assert.deepEqual(uploaded, [...new Set([...deployedFiles(), ...apiFiles])].sort());
  for (const file of [
    "docs/work-plan.md",
    "HANDOFF.md",
    "scripts/dev.js",
    "README.md",
    "AGENTS.md",
    "api/AGENTS.md",
    ".agents/merge-policy.json",
  ]) {
    assert.ok(ignored.has(file), `${file} must not be uploaded`);
  }
  const migrations = lines(tracked.stdout).filter((file) => file.startsWith("supabase/"));
  assert.ok(
    migrations.length > 0 && migrations.every((file) => ignored.has(file)),
    "supabase/ must not be uploaded"
  );
});
