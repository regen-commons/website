// This writes synthetic records. Run only in an empty disposable test database.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { rm } from "node:fs/promises";
import { fixture } from "./lib/notion-import-fixture.js";
import {
  prepareImport,
  importSql,
  stagedImportSql,
  canonical,
  digest,
} from "./lib/notion-import.js";
if (process.env.REGEN_IMPORT_SQL_TEST !== "synthetic-local-only")
  throw new Error(
    "Use a disposable database and set REGEN_IMPORT_SQL_TEST=synthetic-local-only",
  );
const source = await fixture();
function run(sql, expectedError) {
  const r = spawnSync(
    process.env.PSQL_BIN || "psql",
    ["-X", "-v", "ON_ERROR_STOP=1", "-At"],
    { input: sql, encoding: "utf8" },
  );
  if (r.error) throw r.error;
  if (expectedError) {
    assert.notEqual(r.status, 0);
    assert.match(r.stderr, expectedError);
  } else assert.equal(r.status, 0, r.stderr);
  return r.stdout.trim();
}
try {
  const plan = await prepareImport(
    source.root,
    source.decisions,
    source.recovered,
  );
  const staged = stagedImportSql(plan);
  // A missing transfer chunk cannot result in a partial entity import.
  run(staged.stages.slice(0, -1).join("\n"));
  run(staged.apply, /Staged import checksum mismatch/);
  assert.equal(run("select count(*) from public.members;"), "0");
  run(staged.stages.at(-1));
  // Existing target data also requires explicit reconciliation, even with valid bytes.
  run(
    "insert into public.members(name,member_type) values('Synthetic preexisting record','individual');",
  );
  run(staged.apply, /Initial import requires empty members/);
  run("delete from public.members where name='Synthetic preexisting record';");
  run(staged.apply);
  assert.equal(
    run(
      "select (select count(*) from public.members)||','||(select count(*) from public.applications)||','||(select count(*) from public.contribution_members)||','||(select count(*) from private.notification_jobs);",
    ),
    "2,2,1,0",
  );
  assert.equal(
    run(
      "select count(*) from private.import_records where collection='import_staging';",
    ),
    "0",
  );
  // Quoting preserves apostrophes and Unicode through PostgreSQL's real parser.
  assert.equal(
    run("select description from public.contributions;"),
    "O'Brien’s shared guide",
  );
  run(
    "update public.contributions set title='Later synthetic steward edit',revision=revision+1;",
  );
  run(staged.stages.join("\n") + "\n" + staged.apply);
  assert.equal(
    run("select title from public.contributions;"),
    "Later synthetic steward edit",
  );
  run(importSql(plan));
  assert.equal(run("select count(*) from public.applications;"), "2");
  const changed = structuredClone(plan);
  delete changed.checksum;
  changed.decisions.note = "Different reviewed mapping";
  changed.checksum = digest(canonical(changed));
  run(importSql(changed), /Different import already recorded/);
  assert.equal(
    run(
      "begin;set local role anon;select count(*) from public.website_members;rollback;",
    )
      .split("\n")
      .at(-2),
    "2",
  );
  run(
    "begin;set local role anon;select * from public.applications;rollback;",
    /permission denied/,
  );
  run(
    "begin;set local role anon;select * from private.import_records;rollback;",
    /permission denied/,
  );
  console.log(
    "PASS: staged checksum gate, nonempty-target rejection, atomic import, exact text, repeat preservation, changed-plan rejection, private boundaries",
  );
} finally {
  await rm(source.root, { recursive: true, force: true });
}
