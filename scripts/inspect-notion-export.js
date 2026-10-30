import { mkdir, writeFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { inspectExport } from "./lib/notion-export.js";
const [, , input, output] = process.argv;
if (!input || !output) {
  console.error(
    "Usage: node scripts/inspect-notion-export.js SOURCE_FOLDER PRIVATE_REPORT.json",
  );
  process.exitCode = 1;
} else {
  try {
    const target = resolve(output);
    // A report contains private application fields; never put it in a source path.
    const artifactRoot = resolve("artifacts") + "/";
    if (!target.startsWith(artifactRoot))
      throw new Error("Save private reports under ignored artifacts/");
    const report = await inspectExport(resolve(input));
    await mkdir(dirname(target), { recursive: true, mode: 0o700 });
    await writeFile(target, JSON.stringify(report, null, 2) + "\n", {
      mode: 0o600,
      flag: "wx",
    });
    console.log(JSON.stringify(report.summary));
    console.log(
      "Private inventory saved. No database writes or notifications were performed.",
    );
  } catch (error) {
    console.error(
      error.code === "EEXIST"
        ? "Report already exists; choose a new output path."
        : error.message,
    );
    process.exitCode = 1;
  }
}
