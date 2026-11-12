import { websiteHandler } from "./_lib/public-data.js";
export default websiteHandler("contact");
export const config = { api: { bodyParser: { sizeLimit: "32kb" } } };
