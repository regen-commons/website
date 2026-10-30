import { feedbackCategories, feedbackPayload } from "./feedback-contract.js";

const form = document.getElementById("feedback-form");
const categories = document.getElementById("feedback-categories");
const status = document.getElementById("feedback-status");
const submit = form.querySelector('button[type="submit"]');
const source = new URLSearchParams(location.search).get("from") || "/";
form.elements.page_path.value = /^\/(?!\/)[^\s?#\\]{0,499}$/.test(source)
  ? source
  : "/";
document.getElementById("feedback-context").textContent =
  `Page: ${form.elements.page_path.value}`;
for (const category of feedbackCategories) {
  const label = document.createElement("label");
  const checkbox = document.createElement("input");
  checkbox.type = "checkbox";
  checkbox.name = "categories";
  checkbox.value = category;
  label.append(checkbox, document.createTextNode(category));
  categories.append(label);
}
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
    const values = new FormData(form);
    payload = feedbackPayload({
      message: values.get("message"),
      categories: values.getAll("categories"),
      page_path: values.get("page_path"),
    });
  } catch {
    status.textContent =
      "Write between 3 and 5,000 characters, then try again.";
    form.elements.message.focus();
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
  const controls = [...form.querySelectorAll("input,textarea,button")].map(
    (element) => ({ element, disabled: element.disabled }),
  );
  controls.forEach(({ element }) => (element.disabled = true));
  form.setAttribute("aria-busy", "true");
  status.textContent = "Saving your feedback…";
  try {
    const response = await fetch("/api/feedback", {
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
    status.textContent = "Your feedback was saved. Thank you.";
  } catch (error) {
    status.textContent =
      error.message === "rate_limited"
        ? "Too many submissions from this connection. Please try again later."
        : "We couldn’t confirm the save. Your feedback is still here; please try again.";
  } finally {
    busy = false;
    controls.forEach(({ element, disabled }) => (element.disabled = disabled));
    submit.disabled = saved;
    form.removeAttribute("aria-busy");
  }
});
