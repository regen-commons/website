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
export function membershipReceipt(name) {
  const greeting = name?.trim() ? `Thank you, ${name.trim()}.` : "Thank you for reaching out.";
  const saved = "Your membership request has been saved. A steward can now review what you shared.";
  const review = "This email confirms receipt of your request. Membership is still subject to steward review.";
  const help = "If you need to add or correct anything, reply to this email.";
  const subject = "We received your membership request — Regen Commons";
  return {
    subject,
    text: `REGEN COMMONS\n\nYour request is in.\n\n${greeting}\n\n${saved}\n\n${review}\n\n${help}\n\nExplore the commons: https://regencommons.com/map\n\nRegen Commons\nA living network, tended together.\nhttps://regencommons.com`,
    html: `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light">
  <title>${escapeHtml(subject)}</title>
</head>
<body style="margin:0;padding:0;background-color:#E0D6C0;color:#1A1408;-webkit-text-size-adjust:100%;">
  <div style="display:none;font-size:1px;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;mso-hide:all;">Your request is saved and ready for steward review.</div>
  <table role="presentation" width="100%" border="0" cellpadding="0" cellspacing="0" bgcolor="#E0D6C0" style="width:100%;border-collapse:collapse;background-color:#E0D6C0;">
    <tr><td align="center" style="padding:32px 16px;">
      <!--[if mso]><table role="presentation" width="580" cellpadding="0" cellspacing="0"><tr><td><![endif]-->
      <table role="presentation" width="100%" border="0" cellpadding="0" cellspacing="0" bgcolor="#EDE5D4" style="width:100%;max-width:580px;border:1px solid #D2C5AA;border-collapse:collapse;background-color:#EDE5D4;">
        <tr><td style="padding:28px 28px 24px;border-bottom:1px solid #D2C5AA;font-family:Arial,sans-serif;font-size:11px;line-height:18px;letter-spacing:3px;color:#1E3A10;">
          <a href="https://regencommons.com" style="color:#1E3A10;text-decoration:none;">REGEN COMMONS</a>
        </td></tr>
        <tr><td style="padding:28px;font-family:Georgia,'Times New Roman',serif;font-size:17px;line-height:28px;color:#4A3E2C;overflow-wrap:break-word;word-break:break-word;">
          <p style="margin:0 0 14px;font-family:Arial,sans-serif;font-size:10px;line-height:18px;letter-spacing:2px;color:#1E3A10;">MEMBERSHIP REQUEST RECEIVED</p>
          <h1 style="margin:0 0 24px;font-family:Georgia,'Times New Roman',serif;font-size:36px;font-weight:400;line-height:42px;color:#1A1408;">Your request is in.</h1>
          <p style="margin:0 0 18px;">${escapeHtml(greeting)}</p>
          <p style="margin:0 0 24px;">${saved}</p>
          <table role="presentation" width="100%" border="0" cellpadding="0" cellspacing="0" bgcolor="#E0D6C0" style="width:100%;border-collapse:collapse;background-color:#E0D6C0;">
            <tr><td style="padding:18px 20px;font-family:Arial,sans-serif;font-size:14px;line-height:23px;color:#4A3E2C;">${review}</td></tr>
          </table>
          <p style="margin:24px 0;">${help}</p>
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
