import { contactPayload } from "./contact-contract.js";

const form = document.getElementById("contact-form");
const status = document.getElementById("contact-status");
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
    payload = contactPayload(Object.fromEntries(new FormData(form)));
  } catch {
    status.textContent =
      "Add your name, a valid email, a subject and a message of 3–5,000 characters.";
    return;
  }
  const serialized = JSON.stringify({
    ...payload,
    website_confirm: form.elements.website_confirm.value,
  });
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
    status.textContent =
      "Your message was saved for the steward council. Thank you for reaching out.";
  } catch (error) {
    status.textContent =
      error.message === "rate_limited"
        ? "Too many messages from this connection. Please try again later, or use the email link above."
        : "We couldn’t confirm the save. Your message is still here; please try again.";
  } finally {
    busy = false;
    controls.forEach((control) => (control.disabled = false));
    submit.disabled = saved;
    form.removeAttribute("aria-busy");
  }
});
