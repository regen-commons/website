// Explicit public files: never serve environment, repository, or tooling files.
export const pages = ["index.html", "learn.html", "map.html", "seeds.html", "join.html", "admin.html"];
export const publicFiles = [...pages, "style.css", "script.js", "canvas.js", "logo-canvas.js", "data-state.js", "seed-form.js", "admin/style.css", "admin/app.js"];
