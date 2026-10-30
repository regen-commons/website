(() => {
  "use strict";
  const root = document.documentElement;
  let theme = "dark";
  try {
    const saved = localStorage.getItem("rc-theme");
    if (["light", "dark"].includes(saved)) theme = saved;
  } catch {
    /* Theme preferences are optional; auth never uses browser storage. */
  }
  root.setAttribute("data-theme", theme);

  document.addEventListener("DOMContentLoaded", () => {
    const toggle = document.getElementById("theme-toggle");
    function render(value) {
      theme = value;
      root.setAttribute("data-theme", theme);
      window.dispatchEvent(new CustomEvent("theme-change", { detail: { theme } }));
      const next = theme === "dark" ? "light" : "dark";
      toggle.textContent = `${next === "light" ? "Light" : "Dark"} theme`;
      toggle.setAttribute("aria-label", `Switch to ${next} theme`);
    }
    render(theme);
    toggle.addEventListener("click", () => {
      render(theme === "dark" ? "light" : "dark");
      try {
        localStorage.setItem("rc-theme", theme);
      } catch {
        /* Optional preference. */
      }
    });
    window.addEventListener("storage", (event) => {
      if (
        event.key === "rc-theme" &&
        ["light", "dark"].includes(event.newValue)
      )
        render(event.newValue);
    });
  });
})();
