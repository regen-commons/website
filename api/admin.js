import { AdminError, createSupabaseProvider } from "./_lib/steward-data.js";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function createAdminHandler({ provider, origin, secureCookies = true }) {
  const cookieName = secureCookies ? "__Host-regen_steward" : "regen_steward";
  const cookie = (token = "", seconds = 0) =>
    `${cookieName}=${token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${seconds}${secureCookies ? "; Secure" : ""}`;
  return async (req, res) => {
    res.setHeader("Cache-Control", "private, no-store, max-age=0");
    res.setHeader("Vercel-CDN-Cache-Control", "no-store");
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Referrer-Policy", "no-referrer");
    const token = (req.headers.cookie || "")
      .split(";")
      .map((value) => value.trim())
      .find((value) => value.startsWith(`${cookieName}=`))
      ?.slice(cookieName.length + 1);
    try {
      if (!["GET", "POST"].includes(req.method)) {
        res.setHeader("Allow", "GET, POST");
        throw new AdminError(405, "method_not_allowed");
      }
      const params = new URL(req.url, "http://localhost").searchParams;
      if (req.method === "POST") {
        // Strict configured Origin plus JSON rejects cross-site forms and login CSRF.
        const expectedOrigin =
          typeof origin === "function" ? origin(req) : origin;
        if (!expectedOrigin) throw new AdminError(503, "admin_not_configured");
        if (
          req.headers.origin !== expectedOrigin ||
          req.headers["sec-fetch-site"] === "cross-site"
        )
          throw new AdminError(403, "same_origin_required");
        if (!req.headers["content-type"]?.startsWith("application/json"))
          throw new AdminError(415, "json_required");
        const body = req.body;
        if (!body || typeof body !== "object" || Array.isArray(body))
          throw new AdminError(400, "invalid_request");
        if (JSON.stringify(body).length > 2048)
          throw new AdminError(413, "body_too_large");
        if (body.action === "sign-out") {
          if (token) await provider().signOut(token);
          res.setHeader("Set-Cookie", cookie());
          return res.status(200).json({ ok: true });
        }
        if (!["request-code", "verify-code"].includes(body.action))
          throw new AdminError(400, "invalid_action");
        const email =
          typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
        if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
          throw new AdminError(400, "invalid_email");
        if (body.action === "request-code") {
          await provider().requestCode(email);
          return res.status(200).json({ ok: true });
        }
        if (typeof body.code !== "string" || !/^\d{6,10}$/.test(body.code))
          throw new AdminError(400, "invalid_code");
        const session = await provider().verifyCode(email, body.code);
        let user;
        try {
          user = await provider().authorize(session.token);
        } catch (error) {
          await provider()
            .signOut(session.token)
            .catch(() => {});
          res.setHeader("Set-Cookie", cookie());
          throw error;
        }
        res.setHeader("Set-Cookie", cookie(session.token, session.expiresIn));
        return res.status(200).json({ user, expiresIn: session.expiresIn });
      }
      if (!token) throw new AdminError(401, "sign_in_required");
      const db = provider();
      const user = await db.authorize(token);
      const resource = params.get("resource") || "session";
      if (resource === "session") return res.status(200).json({ user });
      if (resource === "applications") {
        const search = params.get("search") || "",
          state = params.get("state") || "",
          type = params.get("type") || "";
        const offsetValue = params.get("offset") || "0";
        if (
          search.length > 100 ||
          state.length > 50 ||
          (type && !["individual", "organization"].includes(type)) ||
          !/^\d{1,7}$/.test(offsetValue)
        )
          throw new AdminError(400, "invalid_filter");
        return res
          .status(200)
          .json(
            await db.applications(token, {
              search,
              state,
              type,
              offset: Number(offsetValue),
            }),
          );
      }
      if (resource === "application") {
        const id = params.get("id");
        if (!uuid.test(id || "")) throw new AdminError(400, "invalid_id");
        return res.status(200).json(await db.application(token, id));
      }
      if (resource === "members")
        return res.status(200).json(await db.members(token));
      throw new AdminError(404, "not_found");
    } catch (error) {
      if ([401, 403].includes(error.status))
        res.setHeader("Set-Cookie", cookie());
      // Provider errors may contain personal data. Return/log only our fixed codes.
      return res
        .status(error instanceof AdminError ? error.status : 503)
        .json({
          error:
            error instanceof AdminError
              ? error.message
              : "provider_unavailable",
        });
    }
  };
}

export default async function handler(req, res) {
  return createAdminHandler({
    origin: process.env.ADMIN_ORIGIN,
    provider: () =>
      createSupabaseProvider({
        url: process.env.SUPABASE_URL,
        key: process.env.SUPABASE_PUBLISHABLE_KEY,
      }),
  })(req, res);
}

export const config = { api: { bodyParser: { sizeLimit: "2kb" } } };
