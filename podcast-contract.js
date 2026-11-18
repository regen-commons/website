import { contactPayload } from "./contact-contract.js";

// Ways a visitor can take part in the podcast. `label` is what they select on
// the page; `subject` is the short form a steward scans in the council inbox.
export const podcastInterests = [
  {
    value: "guest",
    label: "Join a conversation as a guest",
    subject: "guest",
  },
  {
    value: "suggest-guest",
    label: "Suggest someone we should invite",
    subject: "guest suggestion",
  },
  {
    value: "question",
    label: "Suggest a question or topic",
    subject: "question",
  },
  {
    value: "production",
    label: "Help with editing and publishing",
    subject: "production help",
  },
  {
    value: "synthesis",
    label: "Help turn conversations into shared knowledge",
    subject: "synthesis help",
  },
  {
    value: "updates",
    label: "Hear when the first episode is out",
    subject: "episode updates",
  },
];

// Leaves room for every interest label inside the 5,000-character contact message.
export const podcastNoteLimit = 4500;

// Nothing selected and nothing written gives the council nothing to answer.
export const isEmptyPodcastMessage = (interests, note) =>
  !interests.length && note.trim().length < 3;

// A podcast message is saved as a contact message, so the council reads it in
// the same private inbox and replies by email. The subject carries the chosen
// interests; the message spells them out and adds the visitor's note.
export function podcastMessage(input) {
  if (!input || typeof input !== "object" || Array.isArray(input))
    throw new Error("invalid_podcast_message");
  const chosen = input.interests ?? [];
  const note = input.note ?? "";
  if (
    !Array.isArray(chosen) ||
    typeof note !== "string" ||
    note.trim().length > podcastNoteLimit ||
    chosen.some(
      (value) => !podcastInterests.some((interest) => interest.value === value),
    )
  )
    throw new Error("invalid_podcast_message");
  const interests = podcastInterests.filter((interest) =>
    chosen.includes(interest.value),
  );
  if (isEmptyPodcastMessage(chosen, note))
    throw new Error("empty_podcast_message");
  return contactPayload({
    name: input.name,
    email: input.email,
    subject:
      "Podcast: " +
      (interests.map((interest) => interest.subject).join(", ") || "note"),
    message: [
      interests.length &&
        "Ways to take part: " +
          interests.map((interest) => interest.label).join("; "),
      note.trim(),
    ]
      .filter(Boolean)
      .join("\n\n"),
  });
}
