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

export function buildApprovedConfirmationEmail(clientName: string) {
  const subject = "Je aanvraag bij Lorenzo Web Solutions is ontvangen";

  const safeName = escapeHtml(clientName);

  const html = `
    <p>Beste ${safeName},</p>
    <p>Bedankt voor je aanvraag bij <strong>Lorenzo Web Solutions</strong>.</p>
    <p>Je aanvraag werd nagekeken en goedgekeurd voor verdere bespreking. Lorenzo neemt persoonlijk contact met je op om de volgende stappen te bespreken.</p>
    <p>Met vriendelijke groet,<br/>Lorenzo Web Solutions<br/><a href="https://lorenzowebsolutions.be">https://lorenzowebsolutions.be</a></p>
  `;

  const text = [
    `Beste ${clientName},`,
    "",
    "Bedankt voor je aanvraag bij Lorenzo Web Solutions.",
    "Je aanvraag werd nagekeken en goedgekeurd voor verdere bespreking.",
    "Lorenzo neemt persoonlijk contact met je op om de volgende stappen te bespreken.",
    "",
    "Met vriendelijke groet,",
    "Lorenzo Web Solutions",
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
