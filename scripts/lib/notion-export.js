import { readdir, lstat, readFile } from "node:fs/promises";
import { join, relative } from "node:path";
import { createHash } from "node:crypto";

// Notion's CSV export uses quoted commas, embedded newlines, and doubled quotes.
export function parseCsv(source) {
  const rows = [];
  let row = [],
    field = "",
    quoted = false,
    closed = false;
  const input = source.replace(/^\uFEFF/, "");
  function cell() {
    row.push(field);
    field = "";
    closed = false;
  }
  function line() {
    cell();
    if (row.some((v) => v !== "")) rows.push(row);
    row = [];
  }
  for (let i = 0; i < input.length; i++) {
    const char = input[i];
    if (quoted) {
      if (char === '"' && input[i + 1] === '"') {
        field += '"';
        i++;
      } else if (char === '"') {
        quoted = false;
        closed = true;
      } else field += char;
    } else if (char === ",") cell();
    else if (char === "\r" || char === "\n") {
      if (char === "\r" && input[i + 1] === "\n") i++;
      line();
    } else if (char === '"') {
      if (field || closed) throw new Error("Invalid CSV quoting");
      quoted = true;
    } else {
      if (closed) throw new Error("Unexpected text after quoted CSV cell");
      field += char;
    }
  }
  if (quoted) throw new Error("Unclosed CSV quote");
  if (field || row.length || closed) line();
  if (!rows.length) throw new Error("Empty CSV export");
  const headers = rows.shift();
  if (headers.some((h) => !h) || new Set(headers).size !== headers.length)
    throw new Error("CSV headers must be nonempty and unique");
  return {
    headers,
    records: rows.map((cells, index) => {
      if (cells.length !== headers.length)
        throw new Error(
          `CSV row ${index + 2} has ${cells.length} cells; expected ${headers.length}`,
        );
      return Object.fromEntries(headers.map((key, i) => [key, cells[i]]));
    }),
  };
}
export function classifyCollection(headers) {
  if (headers.includes("Org/Individual Name")) return "members";
  if (
    headers.includes("Title") &&
    (headers.includes("Contributor") || headers.includes("Capital form"))
  )
    return "contributions";
  if (headers.includes("Text") && headers.includes("Status")) return "seeds";
  return "unmapped";
}
export async function inspectExport(root) {
  const files = [],
    collections = [];
  let bytes = 0;
  async function visit(directory) {
    const entries = await readdir(directory, { withFileTypes: true });
    entries.sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      const path = join(directory, entry.name),
        stat = await lstat(path);
      if (stat.isSymbolicLink())
        throw new Error(
          "Export contains a symbolic link; copy the actual source files instead",
        );
      if (stat.isDirectory()) {
        await visit(path);
        continue;
      }
      if (!stat.isFile())
        throw new Error("Export contains an unsupported file type");
      bytes += stat.size;
      if (bytes > 500 * 1024 * 1024)
        throw new Error("Export exceeds the 500 MiB inventory limit");
      const content = await readFile(path),
        name = relative(root, path);
      const item = {
        path: name,
        bytes: stat.size,
        sha256: createHash("sha256").update(content).digest("hex"),
      };
      const id = name.match(/([a-f\d]{32})(?:_all)?\.(?:csv|md)$/i)?.[1];
      if (id) item.source_id = id;
      files.push(item);
      if (/\.csv$/i.test(name)) {
        const { headers, records } = parseCsv(content.toString("utf8"));
        const statuses = {};
        for (const row of records) {
          const state = row.Status || "(missing)";
          statuses[state] = (statuses[state] || 0) + 1;
        }
        collections.push({
          path: name,
          kind: classifyCollection(headers),
          headers,
          row_count: records.length,
          statuses,
          records,
        });
      }
    }
  }
  await visit(root);
  return {
    schema_version: 1,
    captured_at: new Date().toISOString(),
    files,
    collections,
    summary: {
      files: files.length,
      bytes,
      csv_files: collections.length,
      collection_kinds: [...new Set(collections.map((c) => c.kind))],
    },
  };
}
