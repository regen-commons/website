// Explicit public files: never serve environment, repository, or tooling files.
export const pages = ["index.html", "learn.html", "map.html", "seeds.html", "join.html", "about.html", "constitution.html", "council.html", "feedback.html", "podcast.html"];
export const publicFiles = [...pages, "style.css", "theme-toggle.css", "design-tokens.css", "script.js", "canvas.js", "logo-canvas.js", "data-state.js", "seed-form.js", "admin/style.css", "admin/fonts.css", "admin/theme.js", "admin/app.js", "admin/membership.js",
  "fonts.css", "favicon.svg", "favicon-32.png", "apple-touch-icon.png", "robots.txt", "sitemap.xml",
  "feedback-contract.js", "feedback-form.js", "contact-contract.js", "contact-form.js",
  "contact-submit.js", "podcast-contract.js", "podcast-form.js",
  "assets/share/home.png", "assets/share/learn.png", "assets/share/map.png",
  "assets/share/join.png", "assets/share/seeds.png", "assets/share/about.png", "assets/share/constitution.png",
  "assets/council/afolabi.webp", "assets/council/ellie.webp", "assets/council/eve.webp",
  "assets/council/gregory.webp", "assets/council/monty.webp",
  "assets/fonts/fraunces-latin.woff2", "assets/fonts/fraunces-italic-latin.woff2",
  "assets/fonts/source-serif-4-latin.woff2", "assets/fonts/source-serif-4-italic-latin.woff2",
  "assets/fonts/space-grotesk-latin.woff2",
];

export function resolvePublicFile(path) {
  let file = path === "/" ? "index.html" : path.replace(/^\//, "").replace(/\/$/, "");
  if (!file.includes(".")) file += ".html";
  return publicFiles.includes(file) ? file : null;
}
