import {
  isEmptyPodcastMessage,
  podcastInterests,
  podcastMessage,
  podcastNoteLimit,
} from "./podcast-contract.js";
import { attachContactForm } from "./contact-submit.js";

const form = document.getElementById("podcast-form");
const list = document.getElementById("podcast-interests");
for (const interest of podcastInterests) {
  const label = document.createElement("label");
  const checkbox = document.createElement("input");
  const text = document.createElement("span");
  label.className = "join-check";
  checkbox.type = "checkbox";
  checkbox.name = "interests";
  checkbox.value = interest.value;
  text.textContent = interest.label;
  label.append(checkbox, text);
  list.append(label);
}
// The contract owns the note limit; the textarea only mirrors it.
form.elements.note.maxLength = podcastNoteLimit;

// The browser reports this on submit, next to the first checkbox, the same way
// it reports a missing name or email.
const firstInterest = list.querySelector("input");
function checkForContent() {
  firstInterest.setCustomValidity(
    isEmptyPodcastMessage(
      new FormData(form).getAll("interests"),
      form.elements.note.value,
    )
      ? "Choose a way to take part, or write a note below."
      : "",
  );
}
form.addEventListener("input", checkForContent);
checkForContent();

attachContactForm({
  form,
  status: document.getElementById("podcast-status"),
  readPayload() {
    const values = new FormData(form);
    return podcastMessage({
      name: values.get("name"),
      email: values.get("email"),
      interests: values.getAll("interests"),
      note: values.get("note"),
    });
  },
  messages: {
    invalid:
      "Check your name and email address, then choose a way to take part or write a note.",
    saved:
      "Your message was saved for the steward council. Thank you. We’ll reply by email.",
    rateLimited:
      "Too many messages from this connection. Please try again later.",
  },
});
