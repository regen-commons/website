import { createServer } from "node:http";
import { gzipSync } from "node:zlib";
import { readFile } from "node:fs/promises";
import { createFixtureHandlers } from "./fixtures.js";
import { resolvePublicFile } from "./site-files.js";
import { createScenarios } from "./scenarios.js";
import { createAdminHandler } from "../../api/admin.js";
import { createStewardFixtures } from "./steward-fixtures.js";

const root = new URL("../../", import.meta.url);
const banner = '<aside aria-label="Local development" style="position:fixed;bottom:0;left:0;right:0;z-index:2147483647;background:#173c2c;color:white;padding:6px 12px;font:13px system-ui;text-align:center">Local demo · synthetic data · submissions stay in memory · restart to reset</aside>';
const types = { html: "text/html; charset=utf-8", css: "text/css; charset=utf-8", js: "text/javascript; charset=utf-8", svg: "image/svg+xml", woff2: "font/woff2" };

function json(res, status, body) {
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(body));
}

async function readBody(req, limit) {
  if (!req.headers["content-type"]?.startsWith("application/json")) {
    throw Object.assign(new Error("json_required"), { status: 415 });
  }
  let size = 0;
  const chunks = [];
  // Keep the socket alive to return a useful 413 response.
  for await (const chunk of req.iterator({ destroyOnReturn: false })) {
    size += chunk.length;
    if (size > limit) {
      req.resume();
      throw Object.assign(new Error("body_too_large"), { status: 413 });
    }
    chunks.push(chunk);
  }
  try {
    const body = JSON.parse(Buffer.concat(chunks).toString());
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error();
    return body;
  } catch {
    throw Object.assign(new Error("invalid_json"), { status: 400 });
  }
}

export function createLocalServer({ stewardProvider = createStewardFixtures() } = {}) {
  const scenarios = createScenarios();
  const handlers = createFixtureHandlers(stewardProvider);
  const admin = createAdminHandler({ provider: () => stewardProvider, secureCookies: false, origin: (req) => `http://${req.headers.host}` });
  return createServer(async (req, res) => {
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("X-Regen-Data", "fixture");
    res.setHeader("X-Content-Type-Options", "nosniff");
    // Only a loopback URL may address this server, including after DNS resolution.
    if (!/^(127\.0\.0\.1|localhost)(:\d+)?$/.test(req.headers.host || "")) {
      return json(res, 403, { error: "loopback_host_required" });
    }
    if (req.headers.origin && req.headers.origin !== `http://${req.headers.host}`) {
      return json(res, 403, { error: "same_origin_required" });
    }
    try {
      const url = new URL(req.url, "http://localhost");
      const path = url.pathname;
      if (scenarios.controls(req, res, url)) return;
      if (path === "/__dev/health" && req.method === "GET") {
        return json(res, 200, { ok: true, mode: "fixture", persistence: "memory", externalWrites: false });
      }
      const handler = path === "/api/admin" ? admin : handlers[path];
      if (handler) {
        if (req.method === "POST") req.body = await readBody(req, ["/api/apply","/api/admin","/api/feedback"].includes(path) ? 32768 : 8192);
        if (await scenarios.respond(req, res, path)) return;
        // Do not let forwarded headers bypass the real handlers' local rate limits.
        delete req.headers["x-forwarded-for"];
        res.status = (status) => { res.statusCode = status; return res; };
        res.json = (body) => {
          res.setHeader("Cache-Control", "no-store");
          json(res, res.statusCode, body);
        };
        await handler(req, res);
        return;
      }
      if (req.method !== "GET" && req.method !== "HEAD") {
        res.setHeader("Allow", "GET, HEAD");
        return json(res, 405, { error: "method_not_allowed" });
      }
      const file = resolvePublicFile(path);
      if (!file) return json(res, 404, { error: "not_found" });
      const type = file.split(".").at(-1);
      let content = await readFile(new URL(file, root));
      if (type === "html") content = content.toString("utf8");
      if (file === "admin.html") content = content.replace('id="demo-help" hidden', 'id="demo-help"');
      if (type === "html") content = content.replace("</body>", `${file === "admin.html" ? '<aside class="dev-banner">Local demo · synthetic data · no email is sent · restart to reset</aside>' : banner}</body>`);
      // Match the text compression used by the deployment CDN. Fonts are
      // already compressed and must remain byte-for-byte intact.
      if (["html", "css", "js", "svg"].includes(type)) {
        res.setHeader("Vary", "Accept-Encoding");
        const acceptsGzip = (req.headers["accept-encoding"] || "").split(",").some((entry) => {
          const [encoding, ...parameters] = entry.trim().toLowerCase().split(";");
          const quality = parameters.map((value) => value.trim()).find((value) => value.startsWith("q="));
          return encoding === "gzip" && (!quality || Number(quality.slice(2)) > 0);
        });
        if (acceptsGzip) {
          content = gzipSync(content);
          res.setHeader("Content-Encoding", "gzip");
        }
      }
      res.writeHead(200, { "Content-Type": types[type] });
      res.end(req.method === "HEAD" ? undefined : content);
    } catch (error) {
      console.error("local_request_failed", error.message);
      json(res, error.status || 500, { error: error.status ? error.message : "local_server_error" });
    }
  });
}
