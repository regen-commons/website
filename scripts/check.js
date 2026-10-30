import { readdir, readFile, access } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { Script } from "node:vm";
import { fileURLToPath } from "node:url";
import { pages, resolvePublicFile } from "./lib/site-files.js";

const root = new URL("../", import.meta.url);
let count = 0;
async function checkDirectory(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.name.startsWith(".") || ["node_modules", "artifacts"].includes(entry.name)) continue;
    const path = new URL(entry.name + (entry.isDirectory() ? "/" : ""), directory);
    if (entry.isDirectory()) await checkDirectory(path);
    else if (entry.name.endsWith(".js")) {
      const result = spawnSync(process.execPath, ["--check", fileURLToPath(path)], { encoding: "utf8" });
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
}
for (const file of ["package.json", "package-lock.json", "vercel.json"]) {
  JSON.parse(await readFile(new URL(file, root), "utf8"));
}
console.log(`Checked ${count} JavaScript files/inline scripts, local page links, and JSON configuration.`);
