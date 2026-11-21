import { readdir, readFile, access } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { Script } from "node:vm";
import { fileURLToPath } from "node:url";
import { pages, publicFiles, resolvePublicFile } from "./lib/site-files.js";
import { main as lint } from "./lint/run.mjs";

const root = new URL("../", import.meta.url);
let count = 0;
async function checkDirectory(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.name.startsWith(".") || ["node_modules", "artifacts"].includes(entry.name)) continue;
    const path = new URL(entry.name + (entry.isDirectory() ? "/" : ""), directory);
    if (entry.isDirectory()) await checkDirectory(path);
    else if (entry.name.endsWith(".js")) {
      const result = spawnSync(process.execPath, ["--check", fileURLToPath(path)], {
        encoding: "utf8",
      });
      if (result.error) throw result.error;
      if (result.status !== 0) throw new Error(result.stderr);
      count++;
    }
  }
}
await checkDirectory(root);
for (const file of pages) {
  const html = await readFile(new URL(file, root), "utf8");
  let index = 0;
  for (const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)) {
    if (!/\bsrc\s*=/.test(match[1])) {
      new Script(match[2], { filename: `${file}:inline-${++index}` });
      count++;
    }
  }
  for (const match of html.matchAll(/\b(?:src|href)="([^"#?]+)[^"]*"/g)) {
    const target = match[1];
    if (/^(?:[a-z]+:|\/\/)/i.test(target)) continue;
    const filePath = resolvePublicFile(target);
    if (!filePath) throw new Error(`${file}: public link is not served: ${target}`);
    await access(new URL(filePath, root));
  }
  // Link previews name absolute URLs; the image must ship with the site.
  for (const match of html.matchAll(
    /<meta property="og:image" content="https:\/\/regencommons\.com(\/[^"]+)"/g
  )) {
    const filePath = resolvePublicFile(match[1]);
    if (!filePath) throw new Error(`${file}: share image is not served: ${match[1]}`);
    await access(new URL(filePath, root));
  }
}
// Stylesheets load fonts and other stylesheets; each must ship with the site.
for (const file of publicFiles.filter((name) => name.endsWith(".css"))) {
  const css = await readFile(new URL(file, root), "utf8");
  const targets = [
    // A quoted url() is taken whole, so a data URL's inner url(#id) is skipped.
    ...[...css.matchAll(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^"')\s]+))\s*\)/g)].map(
      (match) => match[1] ?? match[2] ?? match[3]
    ),
    ...[...css.matchAll(/@import\s+["']([^"']+)["']/g)].map((match) => match[1]),
  ];
  for (const target of targets) {
    if (/^(?:[a-z]+:|\/\/|#)/i.test(target)) continue;
    const resolved = new URL(target.split(/[?#]/)[0], new URL(file, "https://site.test/")).pathname;
    const filePath = resolvePublicFile(resolved);
    if (!filePath) throw new Error(`${file}: stylesheet reference is not served: ${target}`);
    await access(new URL(filePath, root));
    count++;
  }
}
for (const file of ["package.json", "package-lock.json", "vercel.json"]) {
  JSON.parse(await readFile(new URL(file, root), "utf8"));
}
console.log(
  `Checked ${count} JavaScript files/inline scripts, local page links, and JSON configuration.`
);
// oxlint, Biome formatting and the project rules, against the shrink-only baseline.
process.exitCode = lint("check");
