import { createClient } from "@supabase/supabase-js";
import { createHmac, randomUUID } from "node:crypto";
import { AdminError } from "./steward-data.js";
import { drainNotifications } from "./intake-notifications.js";
import { uuid } from "./content-contract.js";
import { feedbackPayload } from "../../feedback-contract.js";

export function createPublicProvider({ url, key, secret, request = fetch }) {
  if (!url || !key) throw new AdminError(503, "data_not_configured");
  const db = createClient(url, key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: {
      fetch: (url, options) =>
        request(url, { ...options, signal: AbortSignal.timeout(10000) }),
    },
  });
  function checked({ data, error, status }) {
    if (error) {
      const code = /^PT(400|403|409|429)$/.test(error.code || "")
        ? Number(error.code.slice(2))
        : status === 429
          ? 429
          : 503;
      throw new AdminError(
        code === 403 ? 503 : code,
        code === 403
          ? "data_not_configured"
          : /^PT/.test(error.code || "")
            ? error.message
            : "provider_unavailable",
      );
    }
    return data;
  }
  const provider = {
    async notifySeed(text) {
      if (!process.env.NOTIFY_URL || !process.env.NOTIFY_WEBHOOK_SECRET) return;
      const response = await request(process.env.NOTIFY_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${process.env.NOTIFY_WEBHOOK_SECRET}`,
        },
        body: JSON.stringify({ type: "seed", text }),
        redirect: "manual",
        signal: AbortSignal.timeout(8000),
      });
      if (!response.ok) throw new Error("seed_notification_failed");
    },
    async drain(applicationId = null) {
      const work = (args) =>
        db
          .rpc("notification_work", {
            p_secret: secret,
            p_application_id: null,
            p_job_id: null,
            p_lease: null,
            p_status: null,
            ...args,
          })
          .then(checked);
      return drainNotifications({
        applicationId,
        request,
        claim: (id) => work({ p_application_id: id }),
        finish: (job, status) =>
          work({ p_job_id: job.id, p_lease: job.lease_id, p_status: status }),
      });
    },
    async publicList(resource) {
      const rows = [];
      for (let offset = 0; ; offset += 500) {
        const page = checked(
          await db
            .from(`website_${resource}`)
            .select("*")
            .order("id")
            .range(offset, offset + 499),
        );
        rows.push(...page);
        if (page.length < 500) return rows;
      }
    },
    async submit(kind, requestId, payload, ip) {
      if (!secret) throw new AdminError(503, "data_not_configured");
      return checked(
        await db.rpc("submit_intake", {
          p_secret: secret,
          p_kind: kind,
          p_request_id: requestId,
          p_payload: payload,
          p_actor_hash: createHmac("sha256", secret).update(ip).digest("hex"),
        }),
      );
    },
  };
  return provider;
}
export function createWebsiteHandler(resource, { provider }) {
  return async (req, res) => {
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("Vercel-CDN-Cache-Control", "no-store");
    res.setHeader("X-Content-Type-Options", "nosniff");
    const privateIntake = ["apply", "feedback"].includes(resource);
    const writes = resource === "seeds" || privateIntake;
    const methods = privateIntake
      ? ["POST"]
      : writes
        ? ["GET", "POST"]
        : ["GET"];
    try {
      if (!methods.includes(req.method)) {
        res.setHeader("Allow", methods.join(", "));
        throw new AdminError(405, "method_not_allowed");
      }
      if (req.method === "GET")
        return res
          .status(200)
          .json({ [resource]: await provider().publicList(resource) });
      if (!req.headers["content-type"]?.startsWith("application/json"))
        throw new AdminError(415, "json_required");
      const body = req.body;
      if (!body || typeof body !== "object" || Array.isArray(body))
        throw new AdminError(400, "invalid_request");
      if (
        Buffer.byteLength(JSON.stringify(body)) > (privateIntake ? 32768 : 8192)
      )
        throw new AdminError(413, "body_too_large");
      if (body.website_confirm) return res.status(200).json({ ok: true });
      const requestId = req.headers["idempotency-key"] || randomUUID();
      if (typeof requestId !== "string" || !uuid.test(requestId))
        throw new AdminError(400, "invalid_request_id");
      let payload;
      if (resource === "seeds") {
        if (
          typeof body.text !== "string" ||
          body.text.trim().length < 3 ||
          body.text.trim().length > 240 ||
          (body.author !== undefined &&
            (typeof body.author !== "string" || body.author.length > 80))
        )
          throw new AdminError(400, "invalid_length");
        payload = {
          text: body.text.trim(),
          author: (body.author || "").trim(),
        };
      } else if (resource === "feedback") {
        try {
          payload = feedbackPayload(body);
        } catch {
          throw new AdminError(400, "invalid_feedback");
        }
      } else {
        if (
          typeof body["full-name"] !== "string" ||
          !body["full-name"].trim() ||
          body["full-name"].length > 200
        )
          throw new AdminError(400, "missing_required_fields");
        if (
          typeof body.email !== "string" ||
          body.email.length > 254 ||
          !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email)
        )
          throw new AdminError(400, "invalid_email");
        if (
          body["applicant-type"] !== undefined &&
          !["individual", "organization"].includes(body["applicant-type"])
        )
          throw new AdminError(400, "invalid_member_type");
        const { website_confirm, ...answers } = body;
        if (
          Object.values(answers).some(
            (v) =>
              typeof v !== "string" &&
              !(
                Array.isArray(v) &&
                v.length <= 30 &&
                v.every((x) => typeof x === "string")
              ),
          )
        )
          throw new AdminError(400, "invalid_request");
        payload = {
          ...answers,
          "full-name": body["full-name"].trim(),
          email: body.email.trim().toLowerCase(),
        };
      }
      const forwarded = req.headers["x-forwarded-for"];
      const ip =
        typeof forwarded === "string"
          ? forwarded.split(",")[0].trim()
          : req.socket?.remoteAddress || "unknown";
      const db = provider();
      const saved = await db.submit(
        resource === "seeds"
          ? "seed"
          : resource === "feedback"
            ? "feedback"
            : "application",
        requestId,
        payload,
        ip,
      );
      if (resource === "seeds" && saved.fresh && db.notifySeed)
        await db
          .notifySeed(payload.text)
          .catch(() => console.warn("seed_notification_failed"));
      if (resource === "apply" && db.drain)
        await db
          .drain(saved.id)
          .catch(() => console.warn("notification_processing_failed"));
      return res.status(200).json({ ok: true });
    } catch (error) {
      return res.status(error instanceof AdminError ? error.status : 503).json({
        error:
          error instanceof AdminError ? error.message : "provider_unavailable",
      });
    }
  };
}
export const websiteHandler = (resource) =>
  createWebsiteHandler(resource, {
    provider: () =>
      createPublicProvider({
        url: process.env.SUPABASE_URL,
        key: process.env.SUPABASE_PUBLISHABLE_KEY,
        secret: process.env.SUPABASE_INTAKE_SECRET,
      }),
  });
