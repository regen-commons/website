// Synthetic export used by unit tests and the disposable SQL replay check.
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

export const ids = {
  full: "11111111111111111111111111111111",
  alias: "22222222222222222222222222222222",
  org: "33333333333333333333333333333333",
  contribution: "44444444444444444444444444444444",
  seed: "55555555555555555555555555555555",
  feedback: "66666666666666666666666666666666",
};
export function csv(headers, rows) {
  return (
    [headers, ...rows.map((row) => headers.map((key) => row[key] || ""))]
      .map((row) => row.map((v) => `"${v.replaceAll('"', '""')}"`).join(","))
      .join("\r\n") + "\r\n"
  );
}
const relation = (title, id) => `${title} (Folder/${id}.csv)`;
export async function fixture() {
  const root = await mkdtemp(join(tmpdir(), "regen-import-test-"));
  const memberHeaders = [
    "Org/Individual Name",
    "Status",
    "Membership Type",
    "Email",
    "Date Applied",
    "Based In",
    "Relationship to Regenerative work",
    "Website/Portfolio",
    "Avatar",
    "Focus areas",
    "Contribution to Commons' Work",
    "Vouched By",
    "Affiliations",
    "Contributions",
  ];
  const members = [
    {
      "Org/Individual Name": "Synthetic Person",
      Status: "Active",
      "Membership Type": "Individual",
      Email: "person@example.test",
      "Date Applied": "May 6, 2026",
      "Relationship to Regenerative work":
        "Shared care\nSocial: still part of the answer",
      Affiliations: relation("Synthetic Organization", ids.org),
    },
    {
      "Org/Individual Name": "Synthetic Person",
      Contributions: relation("Synthetic guide", ids.contribution),
    },
    {
      "Org/Individual Name": "Synthetic Organization",
      Status: "Active",
      "Membership Type": "Organization",
    },
  ];
  const contributionHeaders = [
    "Title",
    "Status",
    "Description",
    "Contributor",
    "Type",
    "Capital form",
    "Tier",
    "Stage",
    "License",
    "Terms",
    "Link(s)",
    "Date contributed",
  ];
  const contribution = {
    Title: "Synthetic guide",
    Status: "Active",
    Description: "O'Brien’s shared guide",
    Contributor: relation("Synthetic Person", ids.alias),
    "Capital form": "Social, Intellectual",
    "Link(s)": "https://example.test/guide",
  };
  const specs = [
    [
      "Membership Application Database",
      "a".repeat(32),
      memberHeaders,
      members,
      [ids.full, ids.alias, ids.org],
    ],
    [
      "Contributions",
      "b".repeat(32),
      contributionHeaders,
      [contribution],
      [ids.contribution],
    ],
    [
      "Seeds",
      "c".repeat(32),
      ["Text", "Status", "Tags"],
      [{ Text: "A synthetic forest 🌳", Status: "Active", Tags: "Care, Land" }],
      [ids.seed],
    ],
    [
      "Participant Feedback",
      "d".repeat(32),
      ["Question", "Respondent", "Submission time"],
      [
        {
          Question: "Synthetic response",
          Respondent: "Anonymous",
          "Submission time": "October 6, 2025 12:22 PM",
        },
      ],
      [ids.feedback],
    ],
  ];
  for (const [folder, db, headers, rows, pageIds] of specs) {
    await mkdir(join(root, folder));
    await writeFile(join(root, `${folder} ${db}_all.csv`), csv(headers, rows));
    const projection =
      folder === "Participant Feedback"
        ? headers.slice(0, 1)
        : [...headers].reverse();
    await writeFile(
      join(root, `${folder} ${db}.csv`),
      csv(projection, [...rows].reverse()),
    );
    for (let i = 0; i < rows.length; i++) {
      const heading = rows[i][headers[0]];
      const properties = headers
        .slice(folder === "Participant Feedback" ? 0 : 1)
        .filter((key) => rows[i][key])
        .map((key) => `${key}: ${rows[i][key].replaceAll(".csv)", ".md)")}`)
        .join("\n");
      await writeFile(
        join(root, folder, `Page ${pageIds[i]}.md`),
        `# ${heading}\n\n${properties}\n`,
      );
    }
  }
  const decisions = {
    version: 1,
    member_types: { [ids.alias]: "individual" },
    member_aliases: { [ids.alias]: ids.full },
  };
  const recovered = [
    {
      source_id: "synthetic-recovery-1",
      error: "Synthetic Notion permission error",
      answers: {
        "full-name": "Recovered Synthetic Person",
        "applicant-type": "individual",
        email: "recovered@example.test",
        "closing-notes": "Private answer, preserve exactly",
      },
    },
  ];
  return { root, decisions, recovered };
}
