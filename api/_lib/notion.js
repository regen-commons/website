import { Client } from "@notionhq/client";

export const notion = new Client({ auth: process.env.NOTION_TOKEN });

export const MEMBERS_DB = process.env.NOTION_MEMBERS_DB_ID;
export const CONTRIBUTIONS_DB = process.env.NOTION_CONTRIBUTIONS_DB_ID;
export const SEEDS_DB = process.env.NOTION_SEEDS_DB_ID;

export function readTitle(prop) {
  return prop?.title?.map((t) => t.plain_text).join("") || "";
}

export function readRichText(prop) {
  return prop?.rich_text?.map((t) => t.plain_text).join("") || "";
}

export function readSelect(prop) {
  return prop?.select?.name || "";
}

export function readMultiSelect(prop) {
  return (prop?.multi_select || []).map((o) => o.name);
}

export function readUrl(prop) {
  return prop?.url || "";
}

export function readEmail(prop) {
  return prop?.email || "";
}

export function readDate(prop) {
  return prop?.date?.start || "";
}

export function readRelationIds(prop) {
  return (prop?.relation || []).map((r) => r.id);
}

export function readFirstFileUrl(prop) {
  const f = prop?.files?.[0];
  if (!f) return "";
  return f.type === "external" ? f.external.url : f.file?.url || "";
}

export function title(value) {
  return { title: [{ type: "text", text: { content: value || "" } }] };
}

export function richText(value) {
  if (!value) return { rich_text: [] };
  return { rich_text: [{ type: "text", text: { content: String(value).slice(0, 1900) } }] };
}

export function select(value) {
  return value ? { select: { name: value } } : { select: null };
}

export function multiSelect(values) {
  const arr = Array.isArray(values) ? values : values ? [values] : [];
  return { multi_select: arr.filter(Boolean).map((name) => ({ name })) };
}

export function url(value) {
  return { url: value || null };
}

export function email(value) {
  return { email: value || null };
}

export function date(value) {
  return value ? { date: { start: value } } : { date: null };
}
