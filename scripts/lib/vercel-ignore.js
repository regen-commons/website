// What Vercel may upload: the fixture server's public files, the API, the root
// modules the API imports, and the files Vercel needs to install and route.
// Everything else (docs, migrations, tests, tooling, agent guidance) stays out
// of the deployment. tests/vercelignore.test.js keeps .vercelignore equal to
// vercelIgnore(), so adding a public file updates both the fixture server and
// production in one place.
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, normalize, relative } from "node:path";
import { publicFiles } from "./site-files.js";

const root = new URL("../../", import.meta.url).pathname;

// Needed by Vercel itself, not served as pages.
export const buildFiles = ["package.json", "package-lock.json", "vercel.json"];

// Shipped beside the self-hosted fonts, as the SIL Open Font License asks.
export const licenseFiles = [
  "assets/fonts/fraunces-OFL.txt",
  "assets/fonts/source-serif-4-OFL.txt",
  "assets/fonts/space-grotesk-OFL.txt",
];

// Guidance files inside deployed folders.
export const excludedInsideDeployed = ["api/AGENTS.md"];

function apiFiles(directory = join(root, "api")) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? apiFiles(path) : [relative(root, path)];
  });
}

// Relative module specifiers in static, side-effect and dynamic imports.
const IMPORT = /\b(?:from|import)\s*\(?\s*["'](\.{1,2}\/[^"']+)["']/g;

export function relativeImports(file) {
  const source = readFileSync(join(root, file), "utf8");
  return [...source.matchAll(IMPORT)].map((match) => normalize(join(dirname(file), match[1])));
}

// Root modules the API reaches through relative imports, followed through the
// root modules' own imports.
export function apiRootImports() {
  const found = new Set();
  const queue = apiFiles().filter((name) => name.endsWith(".js"));
  const seen = new Set(queue);
  while (queue.length) {
    for (const target of relativeImports(queue.shift())) {
      if (seen.has(target)) continue;
      seen.add(target);
      if (!target.startsWith("api/")) found.add(target);
      queue.push(target);
    }
  }
  return [...found].sort();
}

export function deployedFiles() {
  return [...new Set([...publicFiles, ...apiRootImports(), ...buildFiles, ...licenseFiles])].sort();
}

// A gitignore-style allowlist: ignore every top-level entry, then re-include
// each deployed file. A file inside a folder needs the folder re-included and
// the folder's other entries ignored again, level by level.
export function vercelIgnore() {
  const lines = [
    "# Generated from scripts/lib/vercel-ignore.js; tests/vercelignore.test.js keeps it in step.",
    "# Production uploads only what is re-included below. Do not edit by hand.",
    "/*",
    "!/api/",
    ...excludedInsideDeployed.map((file) => `/${file}`),
  ];
  const opened = new Set(["api"]);
  for (const file of deployedFiles()) {
    const parts = file.split("/");
    for (let depth = 1; depth < parts.length; depth++) {
      const folder = parts.slice(0, depth).join("/");
      if (opened.has(folder)) continue;
      opened.add(folder);
      lines.push(`!/${folder}/`, `/${folder}/*`);
    }
    lines.push(`!/${file}`);
  }
  return `${lines.join("\n")}\n`;
}
