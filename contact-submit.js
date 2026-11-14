// Saves one private message for the steward council through /api/contact.
// The About and Podcast forms share this, so the retry identity, the kept
// draft and the saved state behave the same wherever a visitor writes in.
export function attachContactForm({ form, status, readPayload, messages }) {
  const submit = form.querySelector('button[type="submit"]');
  let busy = false,
    saved = false,
    lastPayload = "",
    requestId;
  form.addEventListener("input", () => {
    if (!busy && saved) {
      saved = false;
      submit.disabled = false;
      status.textContent = "";
    }
  });
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (busy || saved) return;
    let payload;
    try {
      payload = readPayload();
    } catch {
      status.textContent = messages.invalid;
      return;
    }
    const serialized = JSON.stringify({
      ...payload,
      website_confirm: form.elements.website_confirm.value,
    });
    // Unchanged text keeps its identity, so a retry cannot save it twice.
    if (serialized !== lastPayload) {
      requestId = crypto.randomUUID();
      lastPayload = serialized;
    }
    busy = true;
    const controls = [...form.querySelectorAll("input,textarea,button")];
    controls.forEach((control) => (control.disabled = true));
    form.setAttribute("aria-busy", "true");
    status.textContent = "Sending your message…";
    try {
      const response = await fetch("/api/contact", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": requestId,
        },
        body: serialized,
        signal: AbortSignal.timeout(15000),
      });
      const result = await response.json();
      if (!response.ok || result.ok !== true)
        throw new Error(result.error || "unconfirmed_save");
      saved = true;
      status.textContent = messages.saved;
    } catch (error) {
      status.textContent =
        error.message === "rate_limited"
          ? messages.rateLimited
          : "We couldn’t confirm the save. Your message is still here; please try again.";
    } finally {
      busy = false;
      controls.forEach((control) => (control.disabled = false));
      submit.disabled = saved;
      form.removeAttribute("aria-busy");
    }
  });
}
