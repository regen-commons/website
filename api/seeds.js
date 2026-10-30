import { websiteHandler } from "./_lib/public-data.js";
export default websiteHandler("seeds");
export const config = { api: { bodyParser: { sizeLimit: "8kb" } } };
