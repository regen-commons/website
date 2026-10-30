import { createPublicProvider } from "../api/_lib/public-data.js";
try {
  const provider = createPublicProvider({
    url: process.env.SUPABASE_URL,
    key: process.env.SUPABASE_PUBLISHABLE_KEY,
    secret: process.env.SUPABASE_INTAKE_SECRET,
  });
  await provider.drain();
  console.log(
    "Notification batch completed. Delivery details remain in Supabase.",
  );
} catch {
  console.error(
    "Notification batch failed; inspect private.notification_jobs before retrying.",
  );
  process.exitCode = 1;
}
