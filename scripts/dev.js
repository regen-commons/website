import { createLocalServer } from "./lib/local-server.js";

const port = Number(process.env.PORT || 3501);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("PORT must be an integer between 1 and 65535");
}
const server = createLocalServer();
server.on("error", (error) => {
  console.error(error.code === "EADDRINUSE"
    ? `Port ${port} is occupied. Reuse the existing server or choose PORT; no process was stopped.`
    : error.message);
  process.exitCode = 1;
});
server.listen(port, "127.0.0.1", () => {
  console.log(`Regen Commons: http://127.0.0.1:${port}`);
  console.log("Fixture mode: synthetic data, in-memory submissions, no Notion/email/Telegram calls.");
  console.log("Refresh after frontend edits. Restart after API/tooling edits. Ctrl-C stops the server.");
});
for (const signal of ["SIGINT", "SIGTERM"]) {
  process.once(signal, () => {
    server.close();
    server.closeAllConnections();
  });
}
