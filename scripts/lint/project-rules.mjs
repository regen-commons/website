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

const REGEX_AFTER_WORD = new Set([
  "return",
  "typeof",
  "instanceof",
  "in",
  "of",
  "new",
  "delete",
  "void",
  "throw",
  "case",
  "do",
  "else",
  "yield",
  "await",
]);

// One pass over JavaScript source that returns two views of the same length:
// `code`, with comments blanked and strings kept, and `mask`, which also
// blanks the inside of strings, template text and regex literals. Rules find
// calls and match parentheses in `mask`, then read the text from `code`. It
// tells a regex literal from division by the token before the slash, and
// follows `${}` inside template literals.
export function scan(source) {
  const code = source.split("");
  const mask = source.split("");
  const blank = (from, to, view) => {
    for (let k = from; k < to; k++) if (view[k] !== "\n") view[k] = " ";
  };
  const templates = []; // brace depth at each open `${`
  let braces = 0;
  let previous = ""; // last significant character, or a keyword marker
  let i = 0;
  const readString = (quote) => {
    let j = i + 1;
    while (j < source.length && source[j] !== quote && source[j] !== "\n")
      j += source[j] === "\\" ? 2 : 1;
    blank(i + 1, j, mask);
    i = j + 1;
    previous = "a";
  };
  const readTemplateText = () => {
    // From just after ` or } up to the closing ` or the next ${.
    let j = i;
    while (
      j < source.length &&
      source[j] !== "`" &&
      !(source[j] === "$" && source[j + 1] === "{")
    ) {
      j += source[j] === "\\" ? 2 : 1;
    }
    blank(i, j, mask);
    if (source[j] === "`") {
      i = j + 1;
      previous = "a";
    } else {
      templates.push(braces);
      braces++;
      i = j + 2;
      previous = "{";
    }
  };
  while (i < source.length) {
    const ch = source[i];
    const next = source[i + 1];
    if (ch === "/" && next === "/") {
      const end = source.indexOf("\n", i) === -1 ? source.length : source.indexOf("\n", i);
      blank(i, end, code);
      blank(i, end, mask);
      i = end;
    } else if (ch === "/" && next === "*") {
      const close = source.indexOf("*/", i + 2);
      const end = close === -1 ? source.length : close + 2;
      blank(i, end, code);
      blank(i, end, mask);
      i = end;
    } else if (ch === '"' || ch === "'") {
      readString(ch);
    } else if (ch === "`") {
      i++;
      readTemplateText();
    } else if (ch === "}" && templates.length && templates.at(-1) === braces - 1) {
      templates.pop();
      braces--;
      i++;
      readTemplateText();
    } else if (
      ch === "/" &&
      (previous === "" || previous === "kw" || "(,=:[!&|?{};+-*%<>~^".includes(previous))
    ) {
      let j = i + 1;
      let inClass = false;
      while (j < source.length && source[j] !== "\n") {
        if (source[j] === "\\") j++;
        else if (source[j] === "[") inClass = true;
        else if (source[j] === "]") inClass = false;
        else if (source[j] === "/" && !inClass) break;
        j++;
      }
      blank(i + 1, j, mask);
      i = j + 1;
      while (/[a-z]/i.test(source[i] ?? "")) i++;
      previous = "a";
    } else if (/[A-Za-z_$]/.test(ch)) {
      let j = i;
      while (/[\w$]/.test(source[j] ?? "")) j++;
      previous = REGEX_AFTER_WORD.has(source.slice(i, j)) ? "kw" : "a";
      i = j;
    } else {
      if (ch === "{") braces++;
      else if (ch === "}") braces--;
      if (!/\s/.test(ch)) previous = /[\w$)\].]/.test(ch) ? "a" : ch;
      i++;
    }
  }
  return { code: code.join(""), mask: mask.join("") };
}

export function withoutComments(source) {
  return scan(source).code;
}

// The text between an opening parenthesis at `open` and its match, found in
// the masked view and read from the comment-free one.
function argumentsAt({ code, mask }, open) {
  let depth = 0;
  for (let i = open; i < mask.length; i++) {
    if (mask[i] === "(") depth++;
    else if (mask[i] === ")" && --depth === 0) return code.slice(open + 1, i);
  }
  return code.slice(open + 1);
}

const STRING_LITERAL = /^\s*(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\$]|\\.)*`)\s*$/;

export function htmlSinks(source) {
  return [...scan(source).code.matchAll(SINK)].length;
}

export function untimedProviderCalls(source) {
  const views = scan(source);
  let count = 0;
  for (const match of views.code.matchAll(CALL)) {
    if (views.mask[match.index] !== views.code[match.index]) continue; // inside a string
    const args = argumentsAt(views, match.index + match[0].length - 1);
    if (!TIMEOUT.test(args)) count++;
  }
  return count;
}

export function nonLiteralLogs(source) {
  const views = scan(source);
  let count = 0;
  for (const match of views.code.matchAll(LOG)) {
    if (views.mask[match.index] !== views.code[match.index]) continue; // inside a string
    const args = argumentsAt(views, match.index + match[0].length - 1);
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
