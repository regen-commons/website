// Explicit public files: never serve environment, repository, or tooling files.
export const pages = ["index.html", "learn.html", "map.html", "seeds.html", "join.html", "admin.html", "feedback.html"];
export const publicFiles = [...pages, "style.css", "theme-toggle.css", "design-tokens.css", "script.js", "canvas.js", "logo-canvas.js", "data-state.js", "seed-form.js", "admin/style.css", "admin/fonts.css", "admin/theme.js", "admin/app.js",
  "fonts.css", "favicon.svg", "feedback-contract.js", "feedback-form.js",
  "assets/fonts/fraunces-latin.woff2", "assets/fonts/fraunces-italic-latin.woff2",
  "assets/fonts/source-serif-4-latin.woff2", "assets/fonts/source-serif-4-italic-latin.woff2",
  "assets/fonts/space-grotesk-latin.woff2",
];

export function resolvePublicFile(path) {
  let file = path === "/" ? "index.html" : path.replace(/^\//, "").replace(/\/$/, "");
  if (!file.includes(".")) file += ".html";
  return publicFiles.includes(file) ? file : null;
}
