import { websiteHandler } from "./_lib/public-data.js";
export default websiteHandler("feedback");
export const config = { api: { bodyParser: { sizeLimit: "32kb" } } };
