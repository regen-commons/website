(function () {
  "use strict";

  function createSaver(render, dependencies) {
    var state = "idle";
    return async function save(value, honeypot) {
      if (state === "saving" || state === "saved") return;
      var text = value.trim();
      if (text.length < 3 || text.length > 240) {
        render({ status: "invalid", message: "Please write between 3 and 240 characters." });
        return;
      }
      state = "saving";
      render({ status: state, message: "Saving your seed…" });
      try {
        var data = await RegenData.requestJson("/api/seeds", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ text: text, website_confirm: honeypot || "" }),
        }, dependencies);
        if (!data || data.ok !== true) throw new Error("invalid_response");
      } catch (error) {
        state = "error";
        var message = error.status === 429
          ? "Too many seeds have been sent from this connection. Your words are still here. Please wait and try again later."
          : error.status === 400
          ? "Please write between 3 and 240 characters, then try again."
          : error.status >= 500
          ? "The commons is temporarily unavailable. We couldn't confirm your save. Your words are still here; please try again shortly."
          : "We couldn't confirm that your seed was saved. Your words are still here. Check your connection before trying again.";
        render({ status: state, message: message });
        return;
      }
      // Once acknowledged, an animation/navigation failure must not invite another write.
      state = "saved";
      render({ status: state, message: "Your seed has been saved to the commons.", text: text });
    };
  }

  function bind(form, onSaved) {
    var input = form.querySelector("textarea");
    var button = form.querySelector('button[type="submit"]');
    var label = button.querySelector(".btn-label");
    var message = form.querySelector('[role="status"]');
    var honeypot = form.querySelector('[name="website_confirm"]');
    var save = createSaver(function (result) {
      var locked = result.status === "saving" || result.status === "saved";
      form.setAttribute("aria-busy", String(result.status === "saving"));
      button.disabled = locked;
      input.readOnly = locked;
      message.textContent = result.message;
      input.setAttribute("aria-invalid", String(result.status === "invalid"));
      label.textContent = result.status === "saving" ? "Saving…"
        : result.status === "saved" ? "Saved"
        : result.status === "error" ? "Try again" : "Plant this seed";
      if (result.status === "invalid") input.focus();
      if (result.status === "saved") {
        try {
          localStorage.setItem("regen_vision", result.text);
          localStorage.setItem("regen_vision_time", Date.now().toString());
          localStorage.removeItem("regen_seed_draft");
        } catch (_) {}
        onSaved(result.text);
      }
    });
    try { input.value = localStorage.getItem("regen_seed_draft") || ""; } catch (_) {}
    input.addEventListener("input", function () {
      input.removeAttribute("aria-invalid");
      message.textContent = "";
      try { localStorage.setItem("regen_seed_draft", input.value); } catch (_) {}
    });
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      save(input.value, honeypot && honeypot.value);
    });
  }

  globalThis.RegenSeeds = { createSaver: createSaver, bind: bind };
})();
