// Fixture mode deliberately strips all inherited provider credentials.
for (const key of Object.keys(process.env)) {
  if (
    /^(NOTION_|SUPABASE_|RESEND_|NOTIFY_|STEWARD_NOTIFY_|ADMIN_ORIGIN$)/.test(
      key,
    )
  )
    delete process.env[key];
}
import { createWebsiteHandler } from "../../api/_lib/public-data.js";
export function createFixtureHandlers(provider) {
  return Object.fromEntries(
    ["members", "contributions", "seeds", "apply", "feedback"].map((name) => [
      `/api/${name}`,
      createWebsiteHandler(name, { provider: () => provider }),
    ]),
  );
}
