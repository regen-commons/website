import {
  notion,
  SEEDS_DB,
  readTitle,
  readRichText,
  readMultiSelect,
} from "./_lib/notion.js";

export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "method_not_allowed" });
  }

  if (!SEEDS_DB) {
    return res.status(200).json({ seeds: [] });
  }

  try {
    const seeds = [];
    let cursor;
    do {
      const response = await notion.databases.query({
        database_id: SEEDS_DB,
        filter: {
          property: "Status",
          select: { equals: "Active" },
        },
        start_cursor: cursor,
        page_size: 100,
      });
      for (const page of response.results) {
        const props = page.properties;
        seeds.push({
          id: page.id,
          text: readTitle(props["Text"]),
          author: readRichText(props["Author"]),
          tags: readMultiSelect(props["Tags"]),
        });
      }
      cursor = response.has_more ? response.next_cursor : undefined;
    } while (cursor);

    res.setHeader(
      "Cache-Control",
      "public, s-maxage=300, stale-while-revalidate=600"
    );
    return res.status(200).json({ seeds });
  } catch (err) {
    console.error("seeds_query_failed", err);
    return res.status(500).json({ error: "notion_failed" });
  }
}
