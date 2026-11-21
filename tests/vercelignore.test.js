import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, normalize, relative } from "node:path";
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

// Independent of the generator's scan: any relative .js or .mjs string the API
// or the root modules it reaches contain must name an uploaded file, or the
// function fails in production with "module not found".
test("every module the API reaches is uploaded", () => {
  const uploaded = new Set(deployedFiles());
  const walk = (dir) =>
    readdirSync(join(root, dir), { withFileTypes: true }).flatMap((entry) =>
      entry.isDirectory() ? walk(join(dir, entry.name)) : [join(dir, entry.name)]
    );
  const queue = walk("api").filter((file) => /\.m?js$/.test(file));
  const seen = new Set(queue);
  while (queue.length) {
    const file = queue.shift();
    const source = readFileSync(join(root, file), "utf8");
    for (const match of source.matchAll(/["'](\.{1,2}\/[^"'\s]+\.m?js)["']/g)) {
      const target = normalize(join(dirname(file), match[1]));
      if (!target.startsWith("api/")) {
        assert.ok(
          uploaded.has(target),
          `${file} imports ${relative(".", target)}, which .vercelignore leaves out`
        );
      }
      if (!seen.has(target)) {
        seen.add(target);
        queue.push(target);
      }
    }
  }
});
