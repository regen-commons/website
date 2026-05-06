import { Resend } from "resend";
import {
  notion,
  MEMBERS_DB,
  title,
  richText,
  select,
  multiSelect,
  url,
  email,
  date,
} from "./_lib/notion.js";
import { notifyTelegram } from "./_lib/notify.js";

let _resend = null;
function getResend() {
  if (!process.env.RESEND_API_KEY) return null;
  if (!_resend) _resend = new Resend(process.env.RESEND_API_KEY);
  return _resend;
}

const rateLimitBuckets = new Map();
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;
const RATE_LIMIT_MAX = 3;

function rateLimit(ip) {
  const now = Date.now();
  const bucket = rateLimitBuckets.get(ip) || [];
  const recent = bucket.filter((t) => now - t < RATE_LIMIT_WINDOW_MS);
  if (recent.length >= RATE_LIMIT_MAX) return false;
  recent.push(now);
  rateLimitBuckets.set(ip, recent);
  return true;
}

function clientIp(req) {
  const fwd = req.headers["x-forwarded-for"];
  if (typeof fwd === "string") return fwd.split(",")[0].trim();
  return req.socket?.remoteAddress || "unknown";
}

const FOCUS_AREAS_BY_CONTRIB = {
  "governance-design": "Governance & coordination",
  "community-facilitation": "Community building",
  "knowledge-sharing": "Education & knowledge",
  "project-development": "Technology & infrastructure",
  "cultural-stewardship": "Arts & culture",
  "communications": "Policy & advocacy",
};

const CONTRIB_AREA_LABELS = {
  "governance-design": "Governance design",
  "community-facilitation": "Community facilitation",
  "knowledge-sharing": "Knowledge sharing",
  "project-development": "Project development",
  "cultural-stewardship": "Cultural stewardship",
  "communications": "Communications",
  "other": "Other",
};

function telegramUrl(value) {
  if (!value) return null;
  const s = String(value).trim();
  if (!s) return null;
  if (/^https?:\/\//i.test(s)) return s;
  if (/^t\.me\//i.test(s)) return "https://" + s;
  return "https://t.me/" + s.replace(/^@/, "");
}

function commitmentLabel(value) {
  return (
    {
      "yes": "Yes",
      "yes-with-constraints": "Yes with constraints",
      "unsure": "Unsure",
    }[value] || ""
  );
}

function consentLabel(value) {
  return ({ "yes": "Yes", "questions": "Has questions" }[value] || "");
}

function authorizedLabel(value) {
  return (
    { "yes": "Yes", "yes-with-limits": "Yes with limits" }[value] || ""
  );
}

function buildProperties(body) {
  const isOrg = body["applicant-type"] === "organization";
  const contribAreasRaw = Array.isArray(body["contribution-area"])
    ? body["contribution-area"]
    : body["contribution-area"]
    ? [body["contribution-area"]]
    : [];
  const contributionAreaNames = contribAreasRaw
    .map((c) => CONTRIB_AREA_LABELS[c])
    .filter(Boolean);

  const focusAreas = Array.from(
    new Set(
      contribAreasRaw
        .map((c) => FOCUS_AREAS_BY_CONTRIB[c])
        .filter(Boolean)
    )
  );

  return {
    "Org/Individual Name":               title(body["full-name"]),
    "Membership Type":                   select(isOrg ? "Organization" : "Individual"),
    "Status":                            select("Pending"),
    "Based In":                          richText(body["location"]),
    "Focus areas":                       multiSelect(focusAreas),
    "Contribution to Commons' Work":     multiSelect(contributionAreaNames),
    "Website/Portfolio":                 url(body["website"]),
    "Date Applied":                      date(new Date().toISOString().slice(0, 10)),

    "Email":                             email(body["email"]),
    "Telegram":                          url(telegramUrl(body["telegram"])),
    "Name and Role of Org Rep":          richText(body["org-rep"]),
    "Org mission, Size and activities":  richText(body["org-description"]),
    "Invited By":                        richText(body["nominator"]),
    "Relationship to Regenerative work": richText(body["regen-relationship"]),
    "Alignment with Core Values":        richText(body["values-resonance"]),
    "Meaningful Participation":          richText(body["meaningful-participation"]),
    "Pathways to Contribution":          richText(body["capital-contribution"]),
    "Contribution other":                richText(body["contribution-area-other"]),
    "Participation Commitment":          select(commitmentLabel(body["commitment"])),
    "Participation Constraint":          richText(body["constraints"]),
    "Decision making authorization":     select(authorizedLabel(body["authorized"])),
    "Colleague Name/Email":              richText(body["other-colleagues"]),
    "Membership Agreement Reviewed":     select(consentLabel(body["agreement-reviewed"])),
    "Consent to Governance Protocol":    select(consentLabel(body["governance-consent"])),
    "Anything else for Steward Council to Know?": richText(body["closing-notes"]),
  };
}

function applicantEmailHtml(name) {
  const greeting = name ? `Dear ${escapeHtml(name)},` : "Hello,";
  return `
    <div style="font-family:Georgia,serif;max-width:560px;line-height:1.6;color:#2a2a2a">
      <p>${greeting}</p>
      <p>Thank you for offering your application to Regen Commons.</p>
      <p>We've received what you shared and a steward will review it within the next few days. When your application is welcomed in, you'll appear in the living network on the map.</p>
      <p>If anything in your application changes, just reply to this email and we'll update it.</p>
      <p style="margin-top:2em">In gratitude,<br>The Regen Commons stewards</p>
    </div>
  `;
}

function stewardEmailHtml(body, notionPageUrl) {
  const isOrg = body["applicant-type"] === "organization";
  return `
    <div style="font-family:system-ui,sans-serif;max-width:640px;line-height:1.5">
      <h2 style="margin-bottom:0.4em">New application: ${escapeHtml(body["full-name"] || "(no name)")}</h2>
      <p style="color:#666;margin-top:0">${isOrg ? "Organization" : "Individual"} · ${escapeHtml(body["location"] || "—")}</p>
      <p><strong>Email:</strong> ${escapeHtml(body["email"] || "—")}<br>
      <strong>Telegram:</strong> ${escapeHtml(body["telegram"] || "—")}<br>
      <strong>Website:</strong> ${body["website"] ? `<a href="${escapeAttr(body["website"])}">${escapeHtml(body["website"])}</a>` : "—"}</p>
      <p><strong>Vision offered:</strong><br>${escapeHtml(body["regen-relationship"] || "")}</p>
      <p style="margin-top:2em"><a href="${escapeAttr(notionPageUrl)}" style="background:#2a4a2a;color:#fff;padding:0.6em 1.2em;text-decoration:none;border-radius:4px">Open in Notion</a></p>
    </div>
  `;
}

function applicationSummary(body) {
  const isOrg = body["applicant-type"] === "organization";
  const name = body["full-name"] || "(no name)";
  const type = isOrg ? "Organization" : "Individual";
  const lines = [`${name} (${type})`];
  if (body["location"]) lines.push(`Based in: ${body["location"]}`);
  if (body["website"]) lines.push(`Website: ${body["website"]}`);
  return lines.join("\n");
}

function escapeHtml(s) {
  return String(s || "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
function escapeAttr(s) {
  return escapeHtml(s);
}

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "method_not_allowed" });
  }

  const body = req.body || {};

  if (body.website_confirm) {
    return res.status(200).json({ ok: true });
  }

  if (!rateLimit(clientIp(req))) {
    return res.status(429).json({ error: "rate_limited" });
  }

  if (!body["full-name"] || !body["email"]) {
    return res.status(400).json({ error: "missing_required_fields" });
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body["email"])) {
    return res.status(400).json({ error: "invalid_email" });
  }

  let notionPage;
  try {
    notionPage = await notion.pages.create({
      parent: { database_id: MEMBERS_DB },
      properties: buildProperties(body),
    });
  } catch (err) {
    console.error("notion_create_failed", err);
    return res.status(500).json({ error: "notion_failed" });
  }

  const notionPageUrl = notionPage.url || `https://www.notion.so/${notionPage.id.replace(/-/g, "")}`;
  const stewardEmails = (process.env.STEWARD_NOTIFY_EMAILS || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const fromEmail = process.env.RESEND_FROM_EMAIL;

  const tasks = [];
  const resend = getResend();
  if (resend && fromEmail && body["email"]) {
    tasks.push(
      resend.emails.send({
        from: `Regen Commons <${fromEmail}>`,
        to: body["email"],
        subject: "We received your application — Regen Commons",
        html: applicantEmailHtml(body["full-name"]),
      })
    );
  }
  if (resend && fromEmail && stewardEmails.length) {
    tasks.push(
      resend.emails.send({
        from: `Regen Commons <${fromEmail}>`,
        to: stewardEmails,
        subject: `New application: ${body["full-name"] || "(no name)"}`,
        html: stewardEmailHtml(body, notionPageUrl),
      })
    );
  }
  tasks.push(
    notifyTelegram({
      type: "application",
      text: applicationSummary(body),
      url: notionPageUrl,
    })
  );

  const results = await Promise.allSettled(tasks);
  results.forEach((r, i) => {
    if (r.status === "rejected") console.error(`resend_email_${i}_failed`, r.reason);
  });

  return res.status(200).json({ ok: true });
}

export const config = {
  api: { bodyParser: { sizeLimit: "32kb" } },
};
