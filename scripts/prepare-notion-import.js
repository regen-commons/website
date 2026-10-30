import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import {
  prepareImport,
  importSql,
  stagedImportSql,
} from "./lib/notion-import.js";
const [root, decisionsPath, recoveredPath, output] = process.argv.slice(2);
try {
  if (!root || !decisionsPath || !recoveredPath || !output)
    throw new Error(
      "Usage: node scripts/prepare-notion-import.js SOURCE_FOLDER DECISIONS.json RECOVERED.json artifacts/PRIVATE_OUTPUT",
    );
  const directory = resolve(output);
  if (!directory.startsWith(resolve("artifacts") + "/"))
    throw new Error("Save private import files under ignored artifacts/");
  const plan = await prepareImport(
    resolve(root),
    JSON.parse(await readFile(decisionsPath, "utf8")),
    JSON.parse(await readFile(recoveredPath, "utf8")),
  );
  await mkdir(dirname(directory), { recursive: true, mode: 0o700 });
  await mkdir(directory, { mode: 0o700 });
  await writeFile(
    `${directory}/plan.json`,
    JSON.stringify(plan, null, 2) + "\n",
    { mode: 0o600, flag: "wx" },
  );
  await writeFile(`${directory}/import.sql`, importSql(plan), {
    mode: 0o600,
    flag: "wx",
  });
  const staged = stagedImportSql(plan);
  for (let i = 0; i < staged.stages.length; i++)
    await writeFile(
      `${directory}/stage-${String(i).padStart(5, "0")}.sql`,
      staged.stages[i],
      { mode: 0o600, flag: "wx" },
    );
  await writeFile(`${directory}/apply-staged.sql`, staged.apply, {
    mode: 0o600,
    flag: "wx",
  });
  console.log(
    JSON.stringify({
      checksum: plan.checksum,
      snapshot: plan.snapshot,
      ...plan.summary,
    }),
  );
  console.log(
    "Private plan and transactional SQL prepared. No database writes or notifications performed.",
  );
} catch (error) {
  console.error(
    error.code === "EEXIST"
      ? "Output already exists; choose a new directory."
      : error.message,
  );
  process.exitCode = 1;
}
