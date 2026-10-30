import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtemp, mkdir, writeFile, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  parseCsv,
  classifyCollection,
  inspectExport,
} from "../scripts/lib/notion-export.js";
test("Notion CSV preserves quoted Unicode, commas, line breaks, empty cells and escaped quotes", () => {
  const result = parseCsv(
    '\uFEFFText,Author,Status\r\n"Forest, rivière\nshared \\"care\\"",,Active\r\n'.replaceAll(
      '\\"',
      '""',
    ),
  );
  assert.deepEqual(result.records, [
    { Text: 'Forest, rivière\nshared "care"', Author: "", Status: "Active" },
  ]);
  assert.equal(classifyCollection(result.headers), "seeds");
});
test("malformed CSV fails instead of truncating or dropping fields", () => {
  for (const value of [
    "A,A\nx,y",
    "A,B\nx",
    'A\n"unclosed',
    'A\n"value"trailing',
    'A\nab"cd',
  ])
    assert.throws(() => parseCsv(value));
});
test("inventory retains raw fields and file digests privately and rejects symlink escapes", async () => {
  const root = await mkdtemp(join(tmpdir(), "regen-export-test-"));
  try {
    await mkdir(join(root, "pages"));
    await writeFile(
      join(root, "Members.csv"),
      "Org/Individual Name,Email,Status\nSynthetic Person,synthetic@example.test,Pending\n",
    );
    await writeFile(
      join(root, "pages", "Example 0123456789abcdef0123456789abcdef.md"),
      "# Synthetic page\nPrivate source evidence",
    );
    const report = await inspectExport(root);
    assert.equal(report.summary.files, 2);
    assert.equal(report.collections[0].kind, "members");
    assert.equal(
      report.collections[0].records[0].Email,
      "synthetic@example.test",
    );
    assert.equal(report.files[1].source_id, "0123456789abcdef0123456789abcdef");
    assert.match(report.files[1].sha256, /^[a-f0-9]{64}$/);
    await symlink(join(root, "Members.csv"), join(root, "escape.csv"));
    await assert.rejects(inspectExport(root), /symbolic link/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
