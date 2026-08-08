interface AdminEmailData {
  requestId: string;
  createdAt: string;
  name: string;
  company: string | null;
  email: string;
  phone: string | null;
  websiteType: string;
  budget: string;
  timing: string;
  description: string;
  reviewUrl: string;
}

interface ApprovedConfirmationEmailData {
  clientName: string;
  requestId: string;
  createdAt: string;
  websiteType: string;
}

const CUSTOMER_EMAIL_LOGO_URL = "https://lorenzowebsolutions.be/assets/images/hero/lorenzo-web-solution-logo-transparent.png";

export function buildAdminNotificationEmail(data: AdminEmailData) {
  const subject = `Nieuwe offerteaanvraag #${data.requestId.slice(0, 8)}`;

  const html = `
    <h2>Nieuwe offerteaanvraag</h2>
    <p><strong>Aanvraagnummer:</strong> ${data.requestId}</p>
    <p><strong>Ontvangstdatum:</strong> ${new Date(data.createdAt).toLocaleString("nl-BE")}</p>
    <p><strong>Naam:</strong> ${escapeHtml(data.name)}</p>
    <p><strong>Bedrijfsnaam:</strong> ${escapeHtml(data.company || "Niet ingevuld")}</p>
    <p><strong>E-mailadres:</strong> ${escapeHtml(data.email)}</p>
    <p><strong>Telefoon:</strong> ${escapeHtml(data.phone || "Niet ingevuld")}</p>
    <p><strong>Type website:</strong> ${escapeHtml(data.websiteType)}</p>
    <p><strong>Budget:</strong> ${escapeHtml(data.budget)}</p>
    <p><strong>Timing:</strong> ${escapeHtml(data.timing)}</p>
    <p><strong>Projectomschrijving:</strong><br/>${escapeHtml(data.description).replace(/\n/g, "<br/>")}</p>
    <p style="margin-top:20px;">
      <a href="${data.reviewUrl}" style="display:inline-block;padding:10px 16px;border-radius:6px;background:#b75d3b;color:#ffffff;text-decoration:none;">
        Aanvraag beoordelen
      </a>
    </p>
  `;

  const text = [
    "Nieuwe offerteaanvraag",
    `Aanvraagnummer: ${data.requestId}`,
    `Ontvangstdatum: ${new Date(data.createdAt).toLocaleString("nl-BE")}`,
    `Naam: ${data.name}`,
    `Bedrijfsnaam: ${data.company || "Niet ingevuld"}`,
    `E-mailadres: ${data.email}`,
    `Telefoon: ${data.phone || "Niet ingevuld"}`,
    `Type website: ${data.websiteType}`,
    `Budget: ${data.budget}`,
    `Timing: ${data.timing}`,
    `Projectomschrijving: ${data.description}`,
    `Aanvraag beoordelen: ${data.reviewUrl}`,
  ].join("\n");

  return { subject, html, text };
}

export function buildApprovedConfirmationEmail(data: ApprovedConfirmationEmailData) {
  const subject = "Je aanvraag is goedgekeurd";
  const requestReference = `#${data.requestId.slice(0, 8).toUpperCase()}`;
  const requestDate = new Date(data.createdAt).toLocaleDateString("nl-BE", {
    day: "2-digit",
    month: "long",
    year: "numeric",
    timeZone: "Europe/Brussels",
  });
  const safeName = escapeHtml(data.clientName);
  const safeRequestReference = escapeHtml(requestReference);
  const safeRequestDate = escapeHtml(requestDate);
  const safeWebsiteType = escapeHtml(data.websiteType);

  const html = `<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${subject}</title>
</head>
<body style="margin:0;padding:0;background-color:#f3f5f7;color:#172033;font-family:Arial,Helvetica,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">Je aanvraag werd goedgekeurd voor verdere bespreking.</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;background-color:#f3f5f7;">
    <tr>
      <td align="center" style="padding:24px 12px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;max-width:600px;background-color:#ffffff;border:1px solid #dfe4ea;border-radius:8px;">
          <tr>
            <td align="center" style="padding:24px 32px 12px;border-top:4px solid #12346b;">
              <img src="${CUSTOMER_EMAIL_LOGO_URL}" width="200" alt="Lorenzo Web Solutions" style="display:block;width:200px;max-width:100%;height:auto;border:0;color:#12346b;font-size:18px;font-weight:bold;line-height:24px;">
            </td>
          </tr>
          <tr>
            <td style="padding:8px 32px 32px;font-size:16px;line-height:1.65;">
              <h1 style="margin:0 0 24px;color:#12346b;font-size:28px;line-height:1.25;font-weight:700;">Je aanvraag is goedgekeurd</h1>
              <p style="margin:0 0 16px;">Beste ${safeName},</p>
              <p style="margin:0 0 16px;">Bedankt voor je aanvraag bij <strong>Lorenzo Web Solutions</strong>.</p>
              <p style="margin:0 0 24px;">Je aanvraag werd nagekeken en is goedgekeurd voor verdere bespreking. Lorenzo neemt persoonlijk contact met je op om je wensen, planning en volgende stappen samen door te nemen.</p>

              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;margin:0 0 28px;background-color:#f7f9fb;border:1px solid #dfe4ea;border-radius:6px;">
                <tr>
                  <td style="padding:18px 20px;">
                    <h2 style="margin:0 0 12px;color:#172033;font-size:18px;line-height:1.35;">Aanvraaggegevens</h2>
                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;font-size:14px;line-height:1.5;">
                      <tr><td style="padding:4px 12px 4px 0;color:#5a6475;">Aanvraagnummer</td><td style="padding:4px 0;color:#172033;font-weight:bold;">${safeRequestReference}</td></tr>
                      <tr><td style="padding:4px 12px 4px 0;color:#5a6475;">Datum aanvraag</td><td style="padding:4px 0;color:#172033;">${safeRequestDate}</td></tr>
                      <tr><td style="padding:4px 12px 4px 0;color:#5a6475;">Type website</td><td style="padding:4px 0;color:#172033;">${safeWebsiteType}</td></tr>
                    </table>
                  </td>
                </tr>
              </table>

              <h2 style="margin:0 0 14px;color:#172033;font-size:20px;line-height:1.35;">Wat gebeurt er nu?</h2>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;margin:0 0 24px;font-size:16px;line-height:1.55;">
                <tr><td valign="top" style="padding:0 10px 10px 0;color:#249fd7;font-weight:bold;">&bull;</td><td style="padding:0 0 10px;">Je aanvraag en projectomschrijving worden verder bekeken.</td></tr>
                <tr><td valign="top" style="padding:0 10px 10px 0;color:#249fd7;font-weight:bold;">&bull;</td><td style="padding:0 0 10px;">We bespreken je verwachtingen en eventuele technische of visuele voorkeuren.</td></tr>
                <tr><td valign="top" style="padding:0 10px 0 0;color:#249fd7;font-weight:bold;">&bull;</td><td>Daarna ontvang je een duidelijk voorstel voor de verdere aanpak.</td></tr>
              </table>

              <p style="margin:0 0 24px;"><strong>Je hoeft op dit moment niets te doen.</strong><br>Ik neem zelf contact met je op.</p>
              <p style="margin:0;">Met vriendelijke groet,<br><strong>Lorenzo Web Solutions</strong></p>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:22px 32px;background-color:#eef2f6;border-top:1px solid #dfe4ea;color:#5a6475;font-size:13px;line-height:1.6;">
              <strong style="color:#172033;">Lorenzo Web Solutions</strong><br>
              Professionele websites voor zelfstandigen en kleine ondernemingen<br>
              <a href="https://lorenzowebsolutions.be" style="color:#12346b;text-decoration:underline;">https://lorenzowebsolutions.be</a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

  const text = [
    "Je aanvraag is goedgekeurd",
    "",
    `Beste ${data.clientName},`,
    "",
    "Bedankt voor je aanvraag bij Lorenzo Web Solutions.",
    "",
    "Je aanvraag werd nagekeken en is goedgekeurd voor verdere bespreking.",
    "Lorenzo neemt persoonlijk contact met je op om je wensen, planning en volgende stappen samen door te nemen.",
    "",
    "Aanvraaggegevens",
    `Aanvraagnummer: ${requestReference}`,
    `Datum aanvraag: ${requestDate}`,
    `Type website: ${data.websiteType}`,
    "",
    "Wat gebeurt er nu?",
    "",
    "- Je aanvraag en projectomschrijving worden verder bekeken.",
    "- We bespreken je verwachtingen en eventuele technische of visuele voorkeuren.",
    "- Daarna ontvang je een duidelijk voorstel voor de verdere aanpak.",
    "",
    "Je hoeft op dit moment niets te doen.",
    "Ik neem zelf contact met je op.",
    "",
    "Met vriendelijke groet,",
    "Lorenzo Web Solutions",
    "",
    "Professionele websites voor zelfstandigen en kleine ondernemingen",
    "https://lorenzowebsolutions.be",
  ].join("\n");

  return { subject, html, text };
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
