interface PrivacyRequestNotificationData {
  requestId: string;
  createdAt: string;
  name: string;
  email: string | null;
  phone: string | null;
  message: string;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

export function buildPrivacyRequestNotificationEmail(data: PrivacyRequestNotificationData) {
  const reference = `#${data.requestId.slice(0, 8).toUpperCase()}`;
  const receivedAt = new Date(data.createdAt).toLocaleString("nl-BE", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "Europe/Brussels",
  });
  const subject = `Nieuw privacyverzoek ${reference}`;
  const safeReference = escapeHtml(reference);
  const safeReceivedAt = escapeHtml(receivedAt);
  const safeName = escapeHtml(data.name);
  const safeEmail = escapeHtml(data.email || "Niet ingevuld");
  const safePhone = escapeHtml(data.phone || "Niet ingevuld");
  const safeMessage = escapeHtml(data.message).replace(/\n/g, "<br>");

  const html = `<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(subject)}</title>
</head>
<body style="margin:0;padding:24px;background:#f4f7f8;color:#17212b;font-family:Arial,Helvetica,sans-serif;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:640px;margin:0 auto;background:#ffffff;border:1px solid #d8e0e4;">
    <tr><td style="padding:24px;border-top:4px solid #0b7285;"><h1 style="margin:0 0 8px;font-size:24px;">Nieuw privacyverzoek</h1><p style="margin:0;color:#52616b;">Referentie ${safeReference} · ontvangen ${safeReceivedAt}</p></td></tr>
    <tr><td style="padding:0 24px 20px;"><p><strong>Naam:</strong> ${safeName}</p><p><strong>E-mail:</strong> ${safeEmail}</p><p><strong>Telefoon:</strong> ${safePhone}</p></td></tr>
    <tr><td style="padding:20px 24px;background:#eef4f5;border-top:1px solid #d8e0e4;"><p style="margin:0 0 8px;font-weight:bold;">Bericht</p><p style="margin:0;line-height:1.6;">${safeMessage}</p></td></tr>
  </table>
</body>
</html>`;

  const text = [
    "Nieuw privacyverzoek",
    `Referentie: ${reference}`,
    `Ontvangen: ${receivedAt}`,
    `Naam: ${data.name}`,
    `E-mail: ${data.email || "Niet ingevuld"}`,
    `Telefoon: ${data.phone || "Niet ingevuld"}`,
    "",
    data.message,
  ].join("\n");

  return { subject, html, text };
}