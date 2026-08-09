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

interface IntakeInvitationEmailData {
  clientName: string;
  company: string | null;
  requestId: string;
  intakeUrl: string;
}

interface SubmittedIntakeAdminEmailData {
  clientName: string;
  company: string | null;
  requestId: string;
  submittedAt: string;
  adminUrl: string;
}

const CUSTOMER_EMAIL_LOGO_URL = "https://lorenzowebsolutions.be/assets/images/hero/lorenzo-web-solution-logo-transparent.png";

export function buildAdminNotificationEmail(data: AdminEmailData) {
  const subject = `Nieuwe offerteaanvraag #${data.requestId.slice(0, 8)}`;
  const requestReference = `#${data.requestId.slice(0, 8).toUpperCase()}`;
  const receivedAt = new Date(data.createdAt).toLocaleString("nl-BE", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "Europe/Brussels",
  });
  const safeRequestId = escapeHtml(data.requestId);
  const safeRequestReference = escapeHtml(requestReference);
  const safeReceivedAt = escapeHtml(receivedAt);
  const safeName = escapeHtml(data.name);
  const safeCompany = escapeHtml(data.company || "Niet ingevuld");
  const safeEmail = escapeHtml(data.email);
  const safePhone = escapeHtml(data.phone || "Niet ingevuld");
  const safeWebsiteType = escapeHtml(data.websiteType);
  const safeBudget = escapeHtml(data.budget);
  const safeTiming = escapeHtml(data.timing);
  const safeDescription = escapeHtml(data.description).replace(/\n/g, "<br>");
  const safeReviewUrl = escapeHtml(data.reviewUrl);

  const html = `<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(subject)}</title>
</head>
<body style="margin:0;padding:0;background-color:#0b1118;color:#ffffff;font-family:Arial,Helvetica,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">Nieuwe offerteaanvraag van ${safeName} — ${safeWebsiteType}.</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;background-color:#0b1118;">
    <tr>
      <td align="center" style="padding:28px 12px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;max-width:640px;border:1px solid #34424c;border-radius:8px;background-color:#17212b;">
          <tr>
            <td style="padding:22px 28px;border-bottom:1px solid #34424c;border-top:4px solid #0ed8e6;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
                <tr>
                  <td valign="middle">
                    <span style="display:inline-block;padding:8px 12px;border-radius:6px;background-color:#ffffff;">
                      <img src="${CUSTOMER_EMAIL_LOGO_URL}" width="148" alt="Lorenzo Web Solutions" style="display:block;width:148px;max-width:100%;height:auto;border:0;color:#0b1118;font-size:16px;font-weight:bold;">
                    </span>
                  </td>
                  <td align="right" valign="middle" style="padding-left:16px;color:#0ed8e6;font-size:11px;line-height:1.4;font-weight:bold;letter-spacing:1.2px;text-transform:uppercase;">Nieuwe aanvraag</td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:30px 28px 10px;font-size:16px;line-height:1.6;">
              <p style="margin:0 0 8px;color:#0ed8e6;font-size:11px;font-weight:bold;letter-spacing:1.2px;text-transform:uppercase;">Interne opvolging</p>
              <h1 style="margin:0 0 12px;color:#ffffff;font-size:30px;line-height:1.18;font-weight:700;">Nieuwe offerteaanvraag</h1>
              <p style="margin:0;color:#aeb9c0;">Er is een nieuwe aanvraag binnengekomen. Controleer de gegevens en bepaal de volgende stap.</p>
            </td>
          </tr>
          <tr>
            <td style="padding:22px 28px 8px;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;border:1px solid #34424c;border-radius:6px;background-color:#101820;">
                <tr>
                  <td width="50%" valign="top" style="padding:14px 16px;border-right:1px solid #34424c;border-bottom:1px solid #34424c;">
                    <p style="margin:0 0 4px;color:#7e8b94;font-size:10px;font-weight:bold;letter-spacing:.7px;text-transform:uppercase;">Aanvraag</p>
                    <p style="margin:0;color:#ffffff;font-size:14px;font-weight:bold;">${safeRequestReference}</p>
                  </td>
                  <td width="50%" valign="top" style="padding:14px 16px;border-bottom:1px solid #34424c;">
                    <p style="margin:0 0 4px;color:#7e8b94;font-size:10px;font-weight:bold;letter-spacing:.7px;text-transform:uppercase;">Ontvangen</p>
                    <p style="margin:0;color:#ffffff;font-size:14px;">${safeReceivedAt}</p>
                  </td>
                </tr>
                <tr>
                  <td width="50%" valign="top" style="padding:14px 16px;border-right:1px solid #34424c;border-bottom:1px solid #34424c;">
                    <p style="margin:0 0 4px;color:#7e8b94;font-size:10px;font-weight:bold;letter-spacing:.7px;text-transform:uppercase;">Naam</p>
                    <p style="margin:0;color:#ffffff;font-size:14px;">${safeName}</p>
                  </td>
                  <td width="50%" valign="top" style="padding:14px 16px;border-bottom:1px solid #34424c;">
                    <p style="margin:0 0 4px;color:#7e8b94;font-size:10px;font-weight:bold;letter-spacing:.7px;text-transform:uppercase;">Bedrijf</p>
                    <p style="margin:0;color:#ffffff;font-size:14px;">${safeCompany}</p>
                  </td>
                </tr>
                <tr>
                  <td width="50%" valign="top" style="padding:14px 16px;border-right:1px solid #34424c;border-bottom:1px solid #34424c;">
                    <p style="margin:0 0 4px;color:#7e8b94;font-size:10px;font-weight:bold;letter-spacing:.7px;text-transform:uppercase;">E-mailadres</p>
                    <p style="margin:0;font-size:14px;word-break:break-word;"><a href="mailto:${safeEmail}" style="color:#0ed8e6;text-decoration:underline;">${safeEmail}</a></p>
                  </td>
                  <td width="50%" valign="top" style="padding:14px 16px;border-bottom:1px solid #34424c;">
                    <p style="margin:0 0 4px;color:#7e8b94;font-size:10px;font-weight:bold;letter-spacing:.7px;text-transform:uppercase;">Telefoon</p>
                    <p style="margin:0;color:#ffffff;font-size:14px;">${safePhone}</p>
                  </td>
                </tr>
                <tr>
                  <td width="50%" valign="top" style="padding:14px 16px;border-right:1px solid #34424c;border-bottom:1px solid #34424c;">
                    <p style="margin:0 0 4px;color:#7e8b94;font-size:10px;font-weight:bold;letter-spacing:.7px;text-transform:uppercase;">Type website</p>
                    <p style="margin:0;color:#ffffff;font-size:14px;">${safeWebsiteType}</p>
                  </td>
                  <td width="50%" valign="top" style="padding:14px 16px;border-bottom:1px solid #34424c;">
                    <p style="margin:0 0 4px;color:#7e8b94;font-size:10px;font-weight:bold;letter-spacing:.7px;text-transform:uppercase;">Budgetindicatie</p>
                    <p style="margin:0;color:#ffffff;font-size:14px;">${safeBudget}</p>
                  </td>
                </tr>
                <tr>
                  <td colspan="2" valign="top" style="padding:14px 16px;">
                    <p style="margin:0 0 4px;color:#7e8b94;font-size:10px;font-weight:bold;letter-spacing:.7px;text-transform:uppercase;">Timing</p>
                    <p style="margin:0;color:#ffffff;font-size:14px;">${safeTiming}</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:14px 28px 8px;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;border-left:3px solid #0ed8e6;background-color:#101820;">
                <tr>
                  <td style="padding:16px 18px;">
                    <p style="margin:0 0 7px;color:#0ed8e6;font-size:10px;font-weight:bold;letter-spacing:.8px;text-transform:uppercase;">Projectomschrijving</p>
                    <p style="margin:0;color:#dce4e8;font-size:14px;line-height:1.65;">${safeDescription}</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:20px 28px 32px;">
              <table role="presentation" cellspacing="0" cellpadding="0" border="0">
                <tr>
                  <td style="border-radius:4px;background-color:#0ed8e6;">
                    <a href="${safeReviewUrl}" style="display:inline-block;padding:14px 20px;color:#0b1118;text-decoration:none;font-size:15px;font-weight:bold;">Aanvraag beoordelen&nbsp;&nbsp;&rarr;</a>
                  </td>
                </tr>
              </table>
              <p style="margin:18px 0 0;color:#7e8b94;font-size:11px;line-height:1.5;">Beveiligde beoordelingslink voor intern gebruik. Aanvraag-ID: ${safeRequestId}</p>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:18px 28px;color:#7e8b94;border-top:1px solid #34424c;background-color:#101820;font-size:12px;line-height:1.6;">
              <strong style="color:#ffffff;">Lorenzo Web Solutions</strong><br>
              Professionele websites voor zelfstandigen en kleine ondernemingen<br>
              <a href="https://lorenzowebsolutions.be" style="color:#0ed8e6;text-decoration:none;">lorenzowebsolutions.be</a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

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

export function buildIntakeInvitationEmail(data: IntakeInvitationEmailData) {
  const subject = "Jouw persoonlijke websitebriefing";
  const requestReference = `#${data.requestId.slice(0, 8).toUpperCase()}`;
  const safeName = escapeHtml(data.clientName);
  const safeCompany = data.company ? escapeHtml(data.company) : null;
  const safeReference = escapeHtml(requestReference);
  const safeIntakeUrl = escapeHtml(data.intakeUrl);

  const html = `<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${subject}</title>
</head>
<body style="margin:0;padding:0;background-color:#f3f5f7;color:#172033;font-family:Arial,Helvetica,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">De volgende stap voor je website is klaar.</div>
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
              <h1 style="margin:0 0 24px;color:#12346b;font-size:28px;line-height:1.25;font-weight:700;">Vertel ons wat je website nodig heeft</h1>
              <p style="margin:0 0 16px;">Beste ${safeName},</p>
              <p style="margin:0 0 16px;">Je aanvraag${safeCompany ? ` voor <strong>${safeCompany}</strong>` : ""} werd bekeken en is klaar voor verdere uitwerking.</p>
              <p style="margin:0 0 24px;">De volgende stap is een korte maar grondige websitebriefing. Daarmee brengen we je doelen, gewenste inhoud, stijl en praktische verwachtingen helder in kaart.</p>

              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;margin:0 0 24px;background-color:#f7f9fb;border:1px solid #dfe4ea;border-radius:6px;">
                <tr>
                  <td style="padding:18px 20px;">
                    <strong style="color:#172033;">Aanvraag ${safeReference}</strong><br>
                    Je persoonlijke link blijft 14 dagen geldig. Je kunt je concept tussentijds opslaan en later via dezelfde link verdergaan.
                  </td>
                </tr>
              </table>

              <table role="presentation" align="center" cellspacing="0" cellpadding="0" border="0" style="margin:0 auto 24px;">
                <tr>
                  <td align="center" bgcolor="#0ed8e6" style="border-radius:4px;background-color:#0ed8e6;">
                    <a href="${safeIntakeUrl}" style="display:inline-block;padding:14px 22px;color:#0b1118;text-decoration:none;font-weight:bold;">Mijn websitebriefing invullen</a>
                  </td>
                </tr>
              </table>

              <p style="margin:0 0 16px;color:#5a6475;font-size:14px;"><strong>Persoonlijke link:</strong> stuur deze e-mail of link niet door. Wie de link bezit, kan je briefing openen.</p>
              <p style="margin:0 0 24px;color:#5a6475;font-size:13px;word-break:break-all;">Werkt de knop niet? Open dan:<br><a href="${safeIntakeUrl}" style="color:#12346b;text-decoration:underline;">${safeIntakeUrl}</a></p>
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
    "Jouw persoonlijke websitebriefing",
    "",
    `Beste ${data.clientName},`,
    "",
    `Je aanvraag${data.company ? ` voor ${data.company}` : ""} werd bekeken en is klaar voor verdere uitwerking.`,
    "",
    "De volgende stap is een korte maar grondige websitebriefing. Daarmee brengen we je doelen, gewenste inhoud, stijl en praktische verwachtingen helder in kaart.",
    "",
    `Aanvraag ${requestReference}`,
    "Je persoonlijke link blijft 14 dagen geldig.",
    "Je kunt je concept tussentijds opslaan en later via dezelfde link verdergaan.",
    "",
    "Mijn websitebriefing invullen:",
    data.intakeUrl,
    "",
    "Stuur deze persoonlijke link niet door. Wie de link bezit, kan je briefing openen.",
    "",
    "Met vriendelijke groet,",
    "Lorenzo Web Solutions",
    "",
    "Professionele websites voor zelfstandigen en kleine ondernemingen",
    "https://lorenzowebsolutions.be",
  ].join("\n");

  return { subject, html, text };
}

export function buildSubmittedIntakeAdminEmail(data: SubmittedIntakeAdminEmailData) {
  const subjectLabel = (data.company || data.clientName).replace(/[\u0000-\u001f\u007f]+/g, " ").trim();
  const subject = `Nieuwe websitebriefing ontvangen — ${subjectLabel}`;
  const requestReference = `#${data.requestId.slice(0, 8).toUpperCase()}`;
  const submittedAt = new Date(data.submittedAt).toLocaleString("nl-BE", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "Europe/Brussels",
  });
  const safeName = escapeHtml(data.clientName);
  const safeCompany = data.company ? escapeHtml(data.company) : null;
  const safeReference = escapeHtml(requestReference);
  const safeSubmittedAt = escapeHtml(submittedAt);
  const safeAdminUrl = escapeHtml(data.adminUrl);

  const html = `<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(subject)}</title>
</head>
<body style="margin:0;padding:0;background-color:#f3f5f7;color:#172033;font-family:Arial,Helvetica,sans-serif;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;background-color:#f3f5f7;">
    <tr>
      <td align="center" style="padding:24px 12px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;max-width:600px;background-color:#ffffff;border:1px solid #dfe4ea;border-radius:8px;">
          <tr>
            <td style="padding:28px 32px;border-top:4px solid #12346b;font-size:16px;line-height:1.6;">
              <h1 style="margin:0 0 18px;color:#12346b;font-size:24px;line-height:1.3;">Nieuwe websitebriefing ontvangen</h1>
              <p style="margin:0 0 20px;">Een klant heeft de websitebriefing definitief verzonden.</p>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;margin:0 0 24px;background-color:#f7f9fb;border:1px solid #dfe4ea;border-radius:6px;">
                <tr>
                  <td style="padding:16px 18px;">
                    <strong>Klant:</strong> ${safeName}<br>
                    ${safeCompany ? `<strong>Bedrijf:</strong> ${safeCompany}<br>` : ""}
                    <strong>Aanvraag:</strong> ${safeReference}<br>
                    <strong>Verzonden:</strong> ${safeSubmittedAt}
                  </td>
                </tr>
              </table>
              <table role="presentation" cellspacing="0" cellpadding="0" border="0">
                <tr>
                  <td style="border-radius:6px;background-color:#b75d3b;">
                    <a href="${safeAdminUrl}" style="display:inline-block;padding:12px 18px;color:#ffffff;text-decoration:none;font-weight:bold;">Briefing bekijken</a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

  const text = [
    "Nieuwe websitebriefing ontvangen",
    "",
    "Een klant heeft de websitebriefing definitief verzonden.",
    `Klant: ${data.clientName}`,
    ...(data.company ? [`Bedrijf: ${data.company}`] : []),
    `Aanvraag: ${requestReference}`,
    `Verzonden: ${submittedAt}`,
    "",
    `Briefing bekijken: ${data.adminUrl}`,
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
