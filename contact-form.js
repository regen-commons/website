import { contactPayload } from "./contact-contract.js";
import { attachContactForm } from "./contact-submit.js";

const form = document.getElementById("contact-form");
attachContactForm({
  form,
  status: document.getElementById("contact-status"),
  readPayload: () => contactPayload(Object.fromEntries(new FormData(form))),
  messages: {
    invalid:
      "Add your name, a valid email, a subject and a message of 3–5,000 characters.",
    saved:
      "Your message was saved for the steward council. Thank you for reaching out.",
    rateLimited:
      "Too many messages from this connection. Please try again later, or use the email link above.",
  },
});
