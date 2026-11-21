// Checks for rules this repository's guides state and no off-the-shelf linter
// knows: HTML sinks in browser code, provider calls without a timeout, and API
// logs that could carry a provider body or personal data. Each finding carries
// the fix, and run.mjs holds them to the same shrink-only baseline as oxlint.
import fs from "node:fs";
import path from "node:path";

export const RULES = {
  "regen(html-sink)": {
    scope: "browser scripts: root *.js, admin/*.js and inline page scripts",
    fix: "Set text with textContent, or build nodes with document.createElement and append them. Only if markup is unavoidable, escape every interpolated value first (admin/AGENTS.md: render submitted text as text).",
  },
  "regen(provider-timeout)": {
    scope: "api/**/*.js",
    fix: "Pass signal: AbortSignal.timeout(ms) to every fetch or injected request call (8000 for notifications, 10000 for Supabase) and map a timeout to a stable error code (api/AGENTS.md).",
  },
  "regen(log-literal-only)": {
    scope: "api/**/*.js",
    fix: 'Log one stable code string, for example console.warn("seed_notification_failed"). Never log a provider response, an error object or request data: they can carry personal data (api/AGENTS.md).',
  },
};

// These are heuristics over source text, not a parser: they catch the usual
// spellings and their common variants, and review still owns the rest.
const SINK = new RegExp(
  [
    String.raw`(?:\.\s*(?:innerHTML|outerHTML|srcdoc)|\[\s*["'\x60](?:innerHTML|outerHTML|srcdoc)["'\x60]\s*\])\s*\+?=(?!=)`,
    String.raw`\.\s*(?:insertAdjacentHTML|setHTMLUnsafe|createContextualFragment)\s*\(`,
    String.raw`\bdocument\s*\.\s*write(?:ln)?\s*\(`,
    String.raw`\b(?:innerHTML|outerHTML|srcdoc)\s*:`,
  ].join("|"),
  "g"
);
const CALL = /(?:\b(?:globalThis|window|self)\s*\.\s*|(?<![\w.$]))(?:fetch|request)\s*\(/g;
const LOG =
  /\bconsole\s*(?:\.\s*(?:log|info|warn|error|debug|trace)|\[\s*["'`](?:log|info|warn|error|debug|trace)["'`]\s*\])\s*\(/g;
const TIMEOUT = /\bsignal\s*:\s*(?!undefined\b|null\b|void\b)\S/;

// Source with comments blanked out (strings kept), so a comment can neither
// trigger a rule nor satisfy one.
export function withoutComments(source) {
  let out = "";
  let quote = null;
  for (let i = 0; i < source.length; i++) {
    const ch = source[i];
    if (quote) {
      out += ch;
      if (ch === "\\") out += source[++i] ?? "";
      else if (ch === quote) quote = null;
    } else if (ch === '"' || ch === "'" || ch === "`") {
      quote = ch;
      out += ch;
    } else if (ch === "/" && source[i + 1] === "/") {
      while (i < source.length && source[i] !== "\n") i++;
      out += "\n";
    } else if (ch === "/" && source[i + 1] === "*") {
      const close = source.indexOf("*/", i + 2);
      const end = close === -1 ? source.length : close + 2;
      out += source.slice(i, end).replace(/[^\n]/g, " ");
      i = end - 1;
    } else out += ch;
  }
  return out;
}

// The text between an opening parenthesis at `open` and its match, skipping
// strings, template literals and comments well enough for these checks.
export function argumentsAt(source, open) {
  let depth = 0;
  let quote = null;
  for (let i = open; i < source.length; i++) {
    const ch = source[i];
    if (quote) {
      if (ch === "\\") i++;
      else if (ch === quote) quote = null;
      continue;
    }
    if (ch === '"' || ch === "'" || ch === "`") quote = ch;
    else if (ch === "/" && source[i + 1] === "/")
      i = source.indexOf("\n", i) === -1 ? source.length : source.indexOf("\n", i);
    else if (ch === "/" && source[i + 1] === "*")
      i = source.indexOf("*/", i + 2) + 1 || source.length;
    else if (ch === "(") depth++;
    else if (ch === ")" && --depth === 0) return source.slice(open + 1, i);
  }
  return source.slice(open + 1);
}

const STRING_LITERAL = /^\s*(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\$]|\\.)*`)\s*$/;

export function htmlSinks(source) {
  return [...withoutComments(source).matchAll(SINK)].length;
}

export function untimedProviderCalls(text) {
  const source = withoutComments(text);
  let count = 0;
  for (const match of source.matchAll(CALL)) {
    const args = argumentsAt(source, match.index + match[0].length - 1);
    if (!TIMEOUT.test(args)) count++;
  }
  return count;
}

export function nonLiteralLogs(text) {
  const source = withoutComments(text);
  let count = 0;
  for (const match of source.matchAll(LOG)) {
    const args = argumentsAt(source, match.index + match[0].length - 1);
    if (!STRING_LITERAL.test(args)) count++;
  }
  return count;
}

function walk(root, directory, keep) {
  return fs.readdirSync(path.join(root, directory), { withFileTypes: true }).flatMap((entry) => {
    const rel = path.posix.join(directory, entry.name);
    if (entry.isDirectory()) return walk(root, rel, keep);
    return keep(rel) ? [rel] : [];
  });
}

// sources: [{ file, text }] for inline page scripts, keyed by "<page>#inline-<n>".
export function projectFindings(root, inlineScripts = []) {
  const findings = [];
  const add = (rule, file, count) => {
    for (let i = 0; i < count; i++) findings.push({ rule, file });
  };
  const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
  const browserFiles = [
    ...fs.readdirSync(root).filter((name) => name.endsWith(".js")),
    ...walk(root, "admin", (file) => file.endsWith(".js")),
  ];
  for (const file of browserFiles) add("regen(html-sink)", file, htmlSinks(read(file)));
  for (const { file, text } of inlineScripts) add("regen(html-sink)", file, htmlSinks(text));
  for (const file of walk(root, "api", (name) => name.endsWith(".js"))) {
    const text = read(file);
    add("regen(provider-timeout)", file, untimedProviderCalls(text));
    add("regen(log-literal-only)", file, nonLiteralLogs(text));
  }
  return findings;
}
