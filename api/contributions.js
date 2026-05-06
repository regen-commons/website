import {
  notion,
  CONTRIBUTIONS_DB,
  readTitle,
  readRichText,
  readSelect,
  readMultiSelect,
  readRelationIds,
  readDate,
} from "./_lib/notion.js";

async function nameForMember(id) {
  try {
    const page = await notion.pages.retrieve({ page_id: id });
    return readTitle(page.properties?.["Org/Individual Name"]);
  } catch {
    return "";
  }
}

export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "method_not_allowed" });
  }

  try {
    const raw = [];
    let cursor;
    do {
      const response = await notion.databases.query({
        database_id: CONTRIBUTIONS_DB,
        filter: {
          property: "Status",
          select: { does_not_equal: "Archived" },
        },
        start_cursor: cursor,
        page_size: 100,
      });
      raw.push(...response.results);
      cursor = response.has_more ? response.next_cursor : undefined;
    } while (cursor);

    const contributorIds = new Set();
    raw.forEach((p) =>
      readRelationIds(p.properties?.["Contributor"]).forEach((id) =>
        contributorIds.add(id)
      )
    );
    const nameMap = {};
    await Promise.all(
      [...contributorIds].map(async (id) => {
        nameMap[id] = await nameForMember(id);
      })
    );

    const contributions = raw.map((page) => {
      const props = page.properties;
      const contribIds = readRelationIds(props["Contributor"]);
      return {
        id: page.id,
        title: readTitle(props["Title"]),
        type: readSelect(props["Type"]),
        stage: readSelect(props["Stage"]),
        status: readSelect(props["Status"]),
        description: readRichText(props["Description"]),
        capitalForm: readMultiSelect(props["Capital form"]),
        tier: readSelect(props["Tier"]),
        terms: readRichText(props["Terms"]),
        contributors: contribIds.map((id) => ({ id, name: nameMap[id] || "" })),
        license: readSelect(props["License"]),
        tags: readMultiSelect(props["Tags"]),
        dateContributed: readDate(props["Date contributed"]),
      };
    });

    res.setHeader(
      "Cache-Control",
      "public, s-maxage=300, stale-while-revalidate=600"
    );
    return res.status(200).json({ contributions });
  } catch (err) {
    console.error("contributions_query_failed", err);
    return res.status(500).json({ error: "notion_failed" });
  }
}
