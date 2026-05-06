import {
  notion,
  MEMBERS_DB,
  readTitle,
  readRichText,
  readSelect,
  readMultiSelect,
  readUrl,
  readRelationIds,
  readFirstFileUrl,
  readDate,
} from "./_lib/notion.js";

export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "method_not_allowed" });
  }

  try {
    const members = [];
    let cursor;
    do {
      const response = await notion.databases.query({
        database_id: MEMBERS_DB,
        filter: {
          property: "Status",
          select: { equals: "Active" },
        },
        start_cursor: cursor,
        page_size: 100,
      });
      for (const page of response.results) {
        const props = page.properties;
        members.push({
          id: page.id,
          name: readTitle(props["Org/Individual Name"]),
          type: readSelect(props["Membership Type"]) || "Individual",
          status: readSelect(props["Status"]),
          location: readRichText(props["Based In"]),
          focusAreas: readMultiSelect(props["Focus areas"]),
          contributionAreas: readMultiSelect(props["Contribution to Commons' Work"]),
          vision: readRichText(props["Relationship to Regenerative work"]),
          website: readUrl(props["Website/Portfolio"]),
          avatar: readFirstFileUrl(props["Avatar"]),
          affiliationIds: readRelationIds(props["Affiliations"]),
          dateApplied: readDate(props["Date Applied"]),
        });
      }
      cursor = response.has_more ? response.next_cursor : undefined;
    } while (cursor);

    res.setHeader(
      "Cache-Control",
      "public, s-maxage=300, stale-while-revalidate=600"
    );
    return res.status(200).json({ members });
  } catch (err) {
    console.error("members_query_failed", err);
    return res.status(500).json({ error: "notion_failed" });
  }
}
