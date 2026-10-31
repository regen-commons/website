const escapeHtml = (value) =>
  String(value).replace(
    /[&<>"']/g,
    (char) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        char
      ],
  );

// Email clients need inline styles and system fonts. These colors are the
// website's light palette from design-tokens.css; the wordmark works with images off.
function membershipEmail({
  subject,
  preheader,
  eyebrow,
  title,
  greeting,
  saved,
  review,
  help,
  message = "",
}) {
  return {
    subject,
    text: `REGEN COMMONS\n\n${title}\n\n${greeting}\n\n${saved}\n\n${review}${message ? `\n\nA message from the stewards:\n${message}` : ""}\n\n${help}\n\nExplore the commons: https://regencommons.com/map\n\nRegen Commons\nA living network, tended together.\nhttps://regencommons.com`,
    html: `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light">
  <title>${escapeHtml(subject)}</title>
</head>
<body style="margin:0;padding:0;background-color:#E0D6C0;color:#1A1408;-webkit-text-size-adjust:100%;">
  <div style="display:none;font-size:1px;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;mso-hide:all;">${escapeHtml(preheader)}</div>
  <table role="presentation" width="100%" border="0" cellpadding="0" cellspacing="0" bgcolor="#E0D6C0" style="width:100%;border-collapse:collapse;background-color:#E0D6C0;">
    <tr><td align="center" style="padding:32px 16px;">
      <!--[if mso]><table role="presentation" width="580" cellpadding="0" cellspacing="0"><tr><td><![endif]-->
      <table role="presentation" width="100%" border="0" cellpadding="0" cellspacing="0" bgcolor="#EDE5D4" style="width:100%;max-width:580px;border:1px solid #D2C5AA;border-collapse:collapse;background-color:#EDE5D4;">
        <tr><td style="padding:28px 28px 24px;border-bottom:1px solid #D2C5AA;font-family:Arial,sans-serif;font-size:11px;line-height:18px;letter-spacing:3px;color:#1E3A10;">
          <a href="https://regencommons.com" style="color:#1E3A10;text-decoration:none;">REGEN COMMONS</a>
        </td></tr>
        <tr><td style="padding:28px;font-family:Georgia,'Times New Roman',serif;font-size:17px;line-height:28px;color:#4A3E2C;overflow-wrap:break-word;word-break:break-word;">
          <p style="margin:0 0 14px;font-family:Arial,sans-serif;font-size:10px;line-height:18px;letter-spacing:2px;color:#1E3A10;">${escapeHtml(eyebrow)}</p>
          <h1 style="margin:0 0 24px;font-family:Georgia,'Times New Roman',serif;font-size:36px;font-weight:400;line-height:42px;color:#1A1408;">${escapeHtml(title)}</h1>
          <p style="margin:0 0 18px;">${escapeHtml(greeting)}</p>
          <p style="margin:0 0 24px;">${escapeHtml(saved)}</p>
          <table role="presentation" width="100%" border="0" cellpadding="0" cellspacing="0" bgcolor="#E0D6C0" style="width:100%;border-collapse:collapse;background-color:#E0D6C0;">
            <tr><td style="padding:18px 20px;font-family:Arial,sans-serif;font-size:14px;line-height:23px;color:#4A3E2C;">${escapeHtml(review)}</td></tr>
          </table>
          ${message ? `<h2 style="margin:24px 0 10px;font-family:Arial,sans-serif;font-size:14px;line-height:23px;font-weight:600;color:#1E3A10;">A message from the stewards</h2><p style="margin:0 0 24px;">${escapeHtml(message).replace(/\r?\n/g, "<br>")}</p>` : ""}
          <p style="margin:24px 0;">${escapeHtml(help)}</p>
          <table role="presentation" border="0" cellpadding="0" cellspacing="0" style="border-collapse:collapse;">
            <tr><td bgcolor="#1E3A10" style="background-color:#1E3A10;padding:14px 20px;">
              <a href="https://regencommons.com/map" style="display:inline-block;font-family:Arial,sans-serif;font-size:14px;font-weight:600;line-height:22px;color:#EDE5D4;text-decoration:none;">Explore the commons &rarr;</a>
            </td></tr>
          </table>
        </td></tr>
        <tr><td style="padding:22px 28px;border-top:1px solid #D2C5AA;font-family:Arial,sans-serif;font-size:12px;line-height:21px;color:#4A3E2C;">
          Regen Commons<br>A living network, tended together.<br>
          <a href="https://regencommons.com" style="color:#1E3A10;">regencommons.com</a>
        </td></tr>
      </table>
      <!--[if mso]></td></tr></table><![endif]-->
    </td></tr>
  </table>
</body>
</html>`,
  };
}

export function membershipReceipt(name) {
  return membershipEmail({
    subject: "We received your membership request — Regen Commons",
    preheader: "Your request is saved and ready for steward review.",
    eyebrow: "MEMBERSHIP REQUEST RECEIVED",
    title: "Your request is in.",
    greeting: name?.trim()
      ? `Thank you, ${name.trim()}.`
      : "Thank you for reaching out.",
    saved:
      "Your membership request has been saved. A steward can now review what you shared.",
    review:
      "This email confirms receipt of your request. Membership is still subject to steward review.",
    help: "If you need to add or correct anything, reply to this email.",
  });
}

// Version 1 stays stable for outbox retries within Resend's idempotency window.
export function membershipDecision({ name, state, message, version = 1 }) {
  const decisions = {
    approved: {
      subject: "Your application is approved — Regen Commons",
      preheader: "A steward has approved your application to Regen Commons.",
      eyebrow: "APPLICATION APPROVED",
      title: "Your application is approved.",
      saved: "Your application to Regen Commons has been approved.",
      review:
        "A steward will follow up about next steps. We look forward to finding ways to contribute together.",
    },
    declined: {
      subject: "An update on your application — Regen Commons",
      preheader:
        "A steward has an update on your application to Regen Commons.",
      eyebrow: "APPLICATION UPDATE",
      title: "An update on your application.",
      saved:
        "After reviewing your application, we’re unable to approve it at this time.",
      review:
        "Thank you for the time and care you put into sharing your work with the commons.",
    },
    changes_requested: {
      subject: "A little more information for your application — Regen Commons",
      preheader:
        "Please reply with a little more information so we can continue your review.",
      eyebrow: "MORE INFORMATION NEEDED",
      title: "A little more to share.",
      saved:
        "Before we can complete our review, we need a little more information.",
      review:
        "Reply to this email with the details requested below so a steward can continue your review.",
    },
  };
  if (
    version !== 1 ||
    !Object.hasOwn(decisions, state) ||
    typeof message !== "string" ||
    message.length > 4000 ||
    (state === "changes_requested" && !message.trim())
  )
    throw new Error("invalid_decision_email");
  return membershipEmail({
    ...decisions[state],
    greeting: name?.trim() ? `Hello, ${name.trim()}.` : "Hello,",
    help: "If you have questions, reply to this email.",
    message: message.trim(),
  });
}
