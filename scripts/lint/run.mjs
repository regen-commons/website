#!/usr/bin/env node
// One lint gate: oxlint over the JavaScript and inline page scripts, Biome
// formatting over JavaScript, JSON and CSS, and this repository's own rules
// (project-rules.mjs), behind one shrink-only baseline (.agents/lint-baseline.json).
//
//   node scripts/lint/run.mjs          check: fail on any new or grown finding
//   node scripts/lint/run.mjs shrink   lower the baseline to what remains
//
// Counts are per rule and file, so code moving inside a file does not churn the
// baseline. A file Biome would reformat counts once under `biome(format)`.
// baseline.mjs is a copy of the shared agent kit (dev-surfaces agents/kit/lint);
// change it there first. npm run check runs this after its own checks.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { pages } from "../lib/site-files.js";
import {
  compareBaseline,
  countFindings,
  describe,
  normalizeFindings,
  readBaseline,
  shrinkBaseline,
} from "./baseline.mjs";
import { projectFindings, RULES } from "./project-rules.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const baselineFile = path.join(root, ".agents/lint-baseline.json");
export const OXLINT_TARGETS = ["admin", "api", "scripts", "tests"];
const bin = (name) => path.join(root, "node_modules/.bin", name);

// Classic and module scripts written inline in the pages, as { file, text }.
export function inlineScripts() {
  const scripts = [];
  for (const page of pages) {
    const html = fs.readFileSync(path.join(root, page), "utf8");
    let index = 0;
    for (const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)) {
      if (/\bsrc\s*=/.test(match[1])) continue;
      const type = /\btype\s*=\s*["']?([^"'\s>]+)/i.exec(match[1])?.[1];
      if (type && !/^(module|text\/javascript)$/i.test(type)) continue;
      scripts.push({ file: `${page}#inline-${++index}`, text: match[2] });
    }
  }
  return scripts;
}

function runJson(command, args) {
  const result = spawnSync(command, args, {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  // A linter exits non-zero when it reports findings; only unreadable output is an error.
  const start = result.stdout.indexOf("{");
  if (start === -1)
    throw new Error(
      `${path.basename(command)} ${args.join(" ")} printed no JSON:\n${result.stderr || result.stdout}`
    );
  return JSON.parse(result.stdout.slice(start));
}

// Each reader fails closed: a tool that read nothing, or reported something
// other than findings, stops the gate instead of passing it with fewer counts.
export function oxlintFindings(doc, rename = (file) => file) {
  if (!(doc.number_of_files > 0))
    throw new Error("oxlint linted no files; check OXLINT_TARGETS and .oxlintrc.json");
  return normalizeFindings(doc, { root }).map((finding) => ({
    ...finding,
    file: rename(finding.file),
  }));
}

export function biomeFindings(doc) {
  const diagnostics = doc.diagnostics || [];
  const other = diagnostics.filter((d) => d.category !== "format" || !d.location?.path);
  if (other.length) {
    throw new Error(
      `biome reported ${other.length} diagnostic(s) that are not formatting, such as ${other[0].category}: ${other[0].message}`
    );
  }
  const summary = doc.summary || {};
  if (summary.diagnosticsNotPrinted !== 0 || summary.errors !== diagnostics.length) {
    throw new Error(
      `biome's summary (${summary.errors} errors, ${summary.diagnosticsNotPrinted} not printed) does not match its ${diagnostics.length} diagnostics; the JSON reporter may have changed`
    );
  }
  if (!(summary.unchanged + summary.changed > 0))
    throw new Error("biome formatted no files; check biome.json files.includes");
  return diagnostics.map((d) => ({ rule: "biome(format)", file: d.location.path }));
}

export function collectFindings() {
  const scripts = inlineScripts();
  const rootScripts = fs.readdirSync(root).filter((name) => name.endsWith(".js"));
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "regen-lint-"));
  try {
    const names = new Map();
    scripts.forEach(({ file, text }, i) => {
      const name = path.join(temp, `inline-${i}.js`);
      fs.writeFileSync(name, text);
      names.set(name, file);
    });
    const rename = (file) => names.get(path.resolve(root, file)) ?? file;
    const oxlint = oxlintFindings(
      runJson(bin("oxlint"), ["--format=json", ...rootScripts, ...OXLINT_TARGETS, ...names.keys()]),
      rename
    );
    const biome = biomeFindings(
      runJson(bin("biome"), ["format", "--reporter=json", "--max-diagnostics=none", "."])
    );
    return [...oxlint, ...biome, ...projectFindings(root, scripts)];
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

function fixFor(rule) {
  if (RULES[rule]) return RULES[rule].fix;
  if (rule === "biome(format)") return "Format the file: npx biome format --write <file>.";
  return "Fix the oxlint finding: npx oxlint <file> prints it with its rule's docs link.";
}

export function main(command = "check") {
  const counts = countFindings(collectFindings());
  const baseline = readBaseline(baselineFile);
  const result = compareBaseline(baseline, counts);
  for (const line of describe(result)) console.log(line);
  if (!result.ok) {
    for (const rule of new Set([...result.grown, ...result.added].map((entry) => entry.rule))) {
      console.error(`  ${rule}: ${fixFor(rule)}`);
    }
    console.error(
      `lint: ${result.grown.length + result.added.length} rule and file count(s) grew past .agents/lint-baseline.json. Fix them; the baseline only shrinks.`
    );
    return 1;
  }
  if (command === "shrink") {
    fs.writeFileSync(
      baselineFile,
      `${JSON.stringify(shrinkBaseline(baseline, counts), null, 2)}\n`
    );
    console.log(`lint: lowered ${result.shrunk.length} count(s) in .agents/lint-baseline.json`);
  } else {
    console.log("lint: no new findings");
  }
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const command = process.argv[2] ?? "check";
  if (!["check", "shrink"].includes(command)) {
    console.error("usage: run.mjs [check|shrink]");
    process.exitCode = 2;
  } else {
    process.exitCode = main(command);
  }
}
