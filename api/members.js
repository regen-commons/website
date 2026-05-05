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
          or: [
            { property: "Status", select: { equals: "Active" } },
            { property: "Status", select: { equals: "Steward" } },
          ],
        },
        start_cursor: cursor,
        page_size: 100,
      });
      for (const page of response.results) {
        const props = page.properties;
        members.push({
          id: page.id,
          name: readTitle(props["Name"]),
          type: readSelect(props["Type"]) || "Individual",
          status: readSelect(props["Status"]),
          location: readRichText(props["Location"]),
          focusAreas: readMultiSelect(props["Focus areas"]),
          contributionAreas: readMultiSelect(props["Contribution areas"]),
          vision: readRichText(props["Vision"]),
          website: readUrl(props["Website"]),
          avatar: readFirstFileUrl(props["Avatar"]),
          affiliationIds: readRelationIds(props["Affiliation"]),
          dateJoined: readDate(props["Date joined"]),
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
