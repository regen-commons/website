// Local-only controls for repeatable browser proof. Never imported by api/.
const scenarios = ["normal", "empty", "error-once", "offline", "rate-limit-once", "slow"];

export function createScenarios() {
  let current = "normal";
  const used = new Set();
  return {
    controls(req, res, url) {
      if (url.pathname === "/__dev/scenario" && req.method === "POST") {
        const name = url.searchParams.get("name");
        if (!scenarios.includes(name)) {
          res.writeHead(400).end("Unknown scenario");
          return true;
        }
        current = name;
        used.clear();
        res.writeHead(303, { Location: "/__dev/scenarios" }).end();
        return true;
      }
      if (url.pathname !== "/__dev/scenarios" || req.method !== "GET") return false;
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      res.end(`<!doctype html><html lang="en"><meta name="viewport" content="width=device-width"><title>Local test scenarios</title>
        <style>body{font:18px system-ui;max-width:45rem;margin:3rem auto;padding:1rem}button{font:inherit;margin:.3rem;padding:.5rem}a{margin-right:1rem}</style>
        <main><h1>Local test scenarios</h1><p>Current scenario: <strong>${current}</strong></p>
        <p>Synthetic data only. This setting affects every tab using this local server. Reset to normal when finished.</p>
        <p>Empty returns no members/contributions. Error fails the first request to each API and method, then permits retry.
        Offline drops API connections until reset to normal. Rate limit rejects the first seed POST. Slow delays API responses by six seconds.</p>
        ${scenarios.map((name) => `<form method="post" action="/__dev/scenario?name=${name}"><button>${name}</button></form>`).join("")}
        <p><a href="/map.html">Map</a><a href="/seeds.html">Plant a seed</a><a href="/learn.html#plant">Learn and plant</a></p></main></html>`);
      return true;
    },
    async respond(req, res, path) {
      const scenario = current;
      const key = `${req.method} ${path}`;
      if (scenario === "slow") await new Promise((resolve) => setTimeout(resolve, 6000));
      if (scenario === "empty" && req.method === "GET" && ["/api/members", "/api/contributions"].includes(path)) {
        res.writeHead(200, { "Content-Type": "application/json" }).end(JSON.stringify({ [path.split("/").at(-1)]: [] }));
        return true;
      }
      // Browsers may transparently retry a dropped connection. Keep dropping
      // until explicitly reset so this scenario actually exercises fetch failure.
      if (scenario === "offline") {
        res.destroy();
        return true;
      }
      if (used.has(key)) return false;
      if (scenario === "error-once") {
        used.add(key);
        res.writeHead(503, { "Content-Type": "application/json" }).end('{"error":"fixture_unavailable"}');
        return true;
      }
      if (scenario === "rate-limit-once" && key === "POST /api/seeds") {
        used.add(key);
        res.writeHead(429, { "Content-Type": "application/json" }).end('{"error":"rate_limited"}');
        return true;
      }
      return false;
    },
  };
}
