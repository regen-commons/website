import {
  notion,
  SEEDS_DB,
  readTitle,
  readRichText,
  readMultiSelect,
  title,
  richText,
  select,
} from "./_lib/notion.js";
import { notifyTelegram } from "./_lib/notify.js";

const rateLimitBuckets = new Map();
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;
const RATE_LIMIT_MAX = 6;
const MIN_LENGTH = 3;
const MAX_LENGTH = 240;

function rateLimit(ip) {
  const now = Date.now();
  const bucket = (rateLimitBuckets.get(ip) || []).filter(
    (t) => now - t < RATE_LIMIT_WINDOW_MS
  );
  if (bucket.length >= RATE_LIMIT_MAX) return false;
  bucket.push(now);
  rateLimitBuckets.set(ip, bucket);
  return true;
}

function clientIp(req) {
  const fwd = req.headers["x-forwarded-for"];
  if (typeof fwd === "string") return fwd.split(",")[0].trim();
  return req.socket?.remoteAddress || "unknown";
}

async function handleGet(req, res) {
  if (!SEEDS_DB) return res.status(200).json({ seeds: [] });
  try {
    const seeds = [];
    let cursor;
    do {
      const response = await notion.databases.query({
        database_id: SEEDS_DB,
        filter: { property: "Status", select: { equals: "Active" } },
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

async function handlePost(req, res) {
  if (!SEEDS_DB) {
    return res.status(503).json({ error: "seeds_db_not_configured" });
  }

  const body = req.body || {};

  if (body.website_confirm) {
    return res.status(200).json({ ok: true });
  }

  if (!rateLimit(clientIp(req))) {
    return res.status(429).json({ error: "rate_limited" });
  }

  const text = String(body.text || "").trim();
  if (text.length < MIN_LENGTH || text.length > MAX_LENGTH) {
    return res.status(400).json({ error: "invalid_length" });
  }

  const author = String(body.author || "").trim().slice(0, 80);

  let seedPage;
  try {
    seedPage = await notion.pages.create({
      parent: { database_id: SEEDS_DB },
      properties: {
        Text: title(text),
        Status: select("Active"),
      },
    });
  } catch (err) {
    console.error("seeds_create_failed", err);
    return res.status(500).json({ error: "notion_failed" });
  }

  const notionPageUrl =
    seedPage.url || `https://www.notion.so/${seedPage.id.replace(/-/g, "")}`;

  try {
    await notifyTelegram({
      type: "seed",
      text: author ? `${text}\n\n— ${author}` : text,
      url: notionPageUrl,
    });
  } catch (err) {
    console.error("seeds_notify_failed", err);
  }

  return res.status(200).json({ ok: true });
}

export default async function handler(req, res) {
  if (req.method === "GET") return handleGet(req, res);
  if (req.method === "POST") return handlePost(req, res);
  res.setHeader("Allow", "GET, POST");
  return res.status(405).json({ error: "method_not_allowed" });
}

export const config = {
  api: { bodyParser: { sizeLimit: "8kb" } },
};
