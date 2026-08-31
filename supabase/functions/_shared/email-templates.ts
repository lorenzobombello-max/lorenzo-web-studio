import { requestKindLabel } from "./request-kind.ts";
import type { ApplicationOutput } from "./application-output.ts";

interface AdminEmailData {
  requestId: string;
  createdAt: string;
  requestKind: "website" | "slimme_documentenflow";
  name: string;
  customerType: "individual" | "business" | null;
  company: string | null;
  enterpriseNumber: string | null;
  enterpriseValidationStatus: "format_valid_not_externally_verified" | "not_checked";
  vatNumber: string | null;
  vatValidationStatus: "valid" | "invalid" | "unavailable" | "not_checked";
  vatValidatedAt: string | null;
  billingAddress: string | null;
  billingPostalCode: string | null;
  billingCity: string | null;
  billingCountry: string | null;
  billingEmail: string | null;
  email: string;
  phone: string | null;
  websiteType: string | null;
  budget: string | null;
  timing: string | null;
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

export interface SdfRequestReceivedEmailData {
  customerName: string;
  supportReference: string;
}

export interface SdfQualificationInvitationEmailData {
  customerName: string;
  supportReference: string;
  intakeUrl: string;
}

export interface SdfQualificationMoreInformationEmailData {
  customerName: string;
  supportReference: string;
  moreInformationReason: string;
  intakeUrl: string;
}

export interface IntakeReminderEmailData {
  clientName: string;
  company: string | null;
  requestId: string;
  intakeUrl: string;
  progressStatus: "invited" | "in_progress";
  reminderPhase: "REMINDER_1" | "REMINDER_2";
  expiresAt: string;
}

interface SubmittedIntakeAdminEmailData {
  output: ApplicationOutput;
  adminUrl: string;
}

export interface QuotationEmailData {
  clientName: string;
  quotationNumber: string;
  quotationVersion: number;
  projectTitle: string;
  validUntil?: string;
  acceptanceUrl?: string;
  acceptedAt?: string;
  acceptingName?: string;
}

export type QuotationEmailTemplate =
  | "QUOTATION_DELIVERY_NL_BE_v1"
  | "ACCEPTANCE_CONFIRMATION_CUSTOMER_NL_BE_v1"
  | "ACCEPTANCE_CONFIRMATION_INTERNAL_NL_BE_v1";

const CUSTOMER_EMAIL_LOGO_URL = "https://lorenzowebsolutions.be/assets/images/branding/logo/lorenzo-web-solution-logo-transparent.png";

function buildSdfCustomerEmail(subject: string, heading: string, content: string, text: string, preheader = "") {
  const hiddenPreheader = preheader
    ? `<div aria-hidden="true" style="display:none!important;visibility:hidden;mso-hide:all;font-size:1px;line-height:1px;max-height:0;max-width:0;overflow:hidden;opacity:0;color:#f3f5f7;">${escapeHtml(preheader)}</div>`
    : "";
  return {
    subject,
    html: `<!doctype html>
<html lang="nl">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escapeHtml(subject)}</title></head>
<body bgcolor="#f3f5f7" style="margin:0!important;padding:0!important;background-color:#f3f5f7;color:#172033;font-family:Arial,Helvetica,sans-serif;">${hiddenPreheader}
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" bgcolor="#f3f5f7" style="width:100%;background-color:#f3f5f7;">
    <tr><td align="center" style="padding:24px 12px;">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;max-width:620px;background:#ffffff;border:1px solid #dfe4ea;border-top:4px solid #0ed8e6;">
        <tr><td style="padding:24px 32px 18px;border-bottom:1px solid #e8edf1;color:#172033;font-size:16px;font-weight:bold;">Lorenzo Web Solutions</td></tr>
        <tr><td style="padding:32px;color:#172033;font-size:16px;line-height:1.65;">
          <h1 style="margin:0 0 24px;color:#12346b;font-size:26px;line-height:1.25;">${escapeHtml(heading)}</h1>
          ${content}
        </td></tr>
        <tr><td style="padding:18px 32px;background:#f8fafb;color:#5a6475;font-size:12px;line-height:1.5;">Lorenzo Web Solutions<br><a href="https://lorenzowebsolutions.be" style="color:#12346b;">lorenzowebsolutions.be</a></td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`,
    text,
  };
}

export function buildSdfRequestReceivedEmail(data: SdfRequestReceivedEmailData) {
  const subject = `We hebben uw Slimme Documentenflow-aanvraag ontvangen — ${data.supportReference}`;
  const customerName = replaceAsciiControlRunsWithSpace(data.customerName).trim();
  const safeName = escapeHtml(customerName);
  const safeReference = escapeHtml(data.supportReference);
  return buildSdfCustomerEmail(subject, "Uw aanvraag voor Slimme Documentenflow is ontvangen", `
          <p style="margin:0 0 16px;">Beste ${safeName},</p>
          <p style="margin:0 0 20px;">We hebben uw aanvraag goed ontvangen.</p>
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin:0 0 24px;background:#f3f7f8;border-left:4px solid #0ed8e6;">
            <tr><td style="padding:14px 18px;color:#5a6475;font-size:13px;">Referentie<br><strong style="color:#172033;font-size:18px;">${safeReference}</strong></td></tr>
          </table>
          <p style="margin:0 0 16px;">We verwerken uw aanvraag automatisch. Als volgende stap ontvangt u uw persoonlijke SDF-intake.</p>
          <p style="margin:24px 0 0;">Met vriendelijke groet,<br><strong>Lorenzo Web Solutions</strong></p>`, [
    `Beste ${customerName},`,
    "",
    "We hebben uw aanvraag goed ontvangen.",
    "",
    `Referentie: ${data.supportReference}`,
    "",
    "We verwerken uw aanvraag automatisch. Als volgende stap ontvangt u uw persoonlijke SDF-intake.",
    "",
    "Met vriendelijke groet,",
    "Lorenzo Web Solutions",
  ].join("\n"));
}

export function buildSdfQualificationInvitationEmail(data: SdfQualificationInvitationEmailData) {
  const subject = `Uw SDF-intake staat klaar — ${data.supportReference}`;
  const customerName = replaceAsciiControlRunsWithSpace(data.customerName).trim();
  const safeName = escapeHtml(customerName);
  const safeReference = escapeHtml(data.supportReference);
  const safeUrl = escapeHtml(data.intakeUrl);
  return buildSdfCustomerEmail(subject, "Uw SDF-intake staat klaar", `
          <p style="margin:0 0 16px;">Beste ${safeName},</p>
          <p style="margin:0 0 20px;">Om uw aanvraag voor Slimme Documentenflow inhoudelijk te beoordelen, vragen we u de persoonlijke SDF-intake in te vullen.</p>
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin:0 0 24px;background:#f3f7f8;border-left:4px solid #0ed8e6;">
            <tr><td style="padding:14px 18px;color:#5a6475;font-size:13px;">Dossierreferentie<br><strong style="color:#172033;font-size:18px;">${safeReference}</strong></td></tr>
          </table>
          <table role="presentation" align="center" cellspacing="0" cellpadding="0" border="0" style="margin:0 auto 24px;">
            <tr><td align="center" bgcolor="#0ed8e6" style="border-radius:4px;background-color:#0ed8e6;"><a href="${safeUrl}" style="display:inline-block;padding:14px 22px;color:#0b1118;text-decoration:none;font-weight:bold;">OPEN UW SDF-INTAKE</a></td></tr>
          </table>
          <p style="margin:0 0 20px;color:#5a6475;font-size:13px;">Werkt de knop niet? Neem contact met ons op en vermeld dossier ${safeReference}.</p>
          <p style="margin:0 0 16px;color:#5a6475;font-size:14px;">De link is 14 dagen geldig en is uitsluitend voor u bestemd. Stuur hem niet door.</p>
          <p style="margin:0 0 16px;">Na ontvangst beoordelen we uw informatie. Het invullen van de intake leidt niet automatisch tot een offerte of prijsbevestiging.</p>
          <p style="margin:24px 0 0;">Met vriendelijke groet,<br><strong>Lorenzo Web Solutions</strong></p>`, [
    `Beste ${customerName},`, "",
    "Uw SDF-intake staat klaar.", "",
    `Dossierreferentie: ${data.supportReference}`, "",
    "Open uw beveiligde SDF-intake:", data.intakeUrl, "",
    "De link is 14 dagen geldig en is uitsluitend voor u bestemd. Stuur hem niet door.", "",
    "Na ontvangst beoordelen we uw informatie. Het invullen van de intake leidt niet automatisch tot een offerte of prijsbevestiging.", "",
    "Met vriendelijke groet,", "Lorenzo Web Solutions",
  ].join("\n"), `Uw persoonlijke SDF-intake voor dossier ${data.supportReference} staat klaar.`);
}

export function buildSdfQualificationMoreInformationEmail(data: SdfQualificationMoreInformationEmailData) {
  const subject = `Aanvullende informatie nodig voor uw Slimme Documentenflow — ${data.supportReference}`;
  const customerName = replaceAsciiControlRunsWithSpace(data.customerName).trim();
  const safeName = escapeHtml(customerName);
  const safeReference = escapeHtml(data.supportReference);
  const safeReason = escapeHtml(data.moreInformationReason).replace(/\n/g, "<br>");
  const safeUrl = escapeHtml(data.intakeUrl);
  return buildSdfCustomerEmail(subject, "Aanvullende informatie nodig", `
          <p style="margin:0 0 16px;">Beste ${safeName},</p>
          <p style="margin:0 0 16px;">We hebben uw SDF-intake beoordeeld. Om uw gewenste documentenflow verder te kunnen beoordelen, hebben we aanvullende informatie nodig:</p>
          <p style="margin:0 0 20px;color:#5a6475;font-size:13px;">Dossierreferentie<br><strong style="color:#172033;font-size:18px;">${safeReference}</strong></p>
          <p style="margin:0 0 20px;padding:14px 18px;background:#f3f7f8;border-left:4px solid #0ed8e6;">${safeReason}</p>
          <p style="margin:0 0 20px;overflow-wrap:anywhere;word-break:break-word;">Vul de informatie aan via uw persoonlijke intake-link:<br><a href="${safeUrl}" style="color:#12346b;">${safeUrl}</a></p>
          <p style="margin:0 0 16px;">Een offerte kan pas worden voorbereid nadat de intake opnieuw is ingediend en beoordeeld.</p>
          <p style="margin:24px 0 0;">Met vriendelijke groet,<br><strong>Lorenzo Web Solutions</strong></p>`, [
    `Beste ${customerName},`, "",
    "We hebben uw SDF-intake beoordeeld. Om uw gewenste documentenflow verder te kunnen beoordelen, hebben we aanvullende informatie nodig:", "",
    `Dossierreferentie: ${data.supportReference}`, "",
    data.moreInformationReason, "",
    "Vul de informatie aan via uw persoonlijke intake-link:", data.intakeUrl, "",
    "Een offerte kan pas worden voorbereid nadat de intake opnieuw is ingediend en beoordeeld.", "",
    "Met vriendelijke groet,", "Lorenzo Web Solutions",
  ].join("\n"));
}

export function buildAdminNotificationEmail(data: AdminEmailData) {
  const requestKindName = requestKindLabel(data.requestKind);
  const subject = data.requestKind === "slimme_documentenflow"
    ? `Nieuwe Slimme Documentenflow-aanvraag #${data.requestId.slice(0, 8)}`
    : `Nieuwe offerteaanvraag #${data.requestId.slice(0, 8)}`;
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
  const safeCustomerType = data.customerType === "business" ? "Onderneming / zelfstandige" : data.customerType === "individual" ? "Particulier" : "Niet opgegeven";
  const safeCompany = escapeHtml(data.company || "Niet ingevuld");
  const vatStatus = data.vatValidationStatus === "valid"
    ? `Geverifieerd${data.vatValidatedAt ? ` op ${new Date(data.vatValidatedAt).toLocaleDateString("nl-BE", { timeZone: "Europe/Brussels" })}` : ""}`
    : data.vatValidationStatus === "invalid"
    ? "Niet als geldig bevestigd"
    : data.vatValidationStatus === "unavailable"
    ? "Controle tijdelijk niet beschikbaar"
    : "Niet gecontroleerd";
  const businessLines = data.customerType === "business" ? [
    `Bedrijfsnaam: ${data.company || "Niet ingevuld"}`,
    `Ondernemingsnummer: ${data.enterpriseNumber || "Niet ingevuld"}`,
    ...(data.enterpriseValidationStatus === "format_valid_not_externally_verified" ? ["Ondernemingsnummerstatus: formaat geldig, niet extern geverifieerd"] : []),
    ...(data.vatNumber ? [`BTW-nummer: ${data.vatNumber}`] : []),
    ...(data.vatNumber ? [`BTW-validatiestatus: ${vatStatus}`] : []),
    ...(!data.vatNumber ? ["BTW-status: geen btw-nummer; handmatige controle vereist"] : []),
    `Facturatieadres: ${data.billingAddress || "Niet ingevuld"}, ${data.billingPostalCode || ""} ${data.billingCity || ""}, ${data.billingCountry || ""}`,
    ...(data.billingEmail ? [`Facturatie-e-mail: ${data.billingEmail}`] : []),
  ] : [];
  const safeBusinessSummary = businessLines.map((line) => escapeHtml(line)).join("<br>");
  const safeEmail = escapeHtml(data.email);
  const safePhone = escapeHtml(data.phone || "Niet ingevuld");
  const safeRequestKind = escapeHtml(requestKindName);
  const safeWebsiteType = escapeHtml(data.websiteType || "Niet van toepassing");
  const safeBudget = escapeHtml(data.budget || "Niet van toepassing");
  const safeTiming = escapeHtml(data.timing || "Niet van toepassing");
  const safeDescription = escapeHtml(data.description).replace(/\n/g, "<br>");
  const safeReviewUrl = escapeHtml(data.reviewUrl);

  const html = `<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(subject)}</title>
</head>
<body bgcolor="#0b1118" style="margin:0!important;padding:0!important;background-color:#0b1118;color:#ffffff;font-family:Arial,Helvetica,sans-serif;">
  <div aria-hidden="true" style="display:none!important;visibility:hidden;mso-hide:all;font-size:1px;line-height:1px;max-height:0;max-width:0;overflow:hidden;opacity:0;color:#0b1118;">Nieuwe ${safeRequestKind}-aanvraag van ${safeName}.</div>
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
              <h1 style="margin:0 0 12px;color:#ffffff;font-size:30px;line-height:1.18;font-weight:700;">Nieuwe ${safeRequestKind}-aanvraag</h1>
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
                    <p style="margin:0;color:#ffffff;font-size:14px;word-break:break-word;">${safeCompany}</p>
                  </td>
                </tr>
                <tr>
                  <td width="50%" valign="top" style="padding:14px 16px;border-right:1px solid #34424c;border-bottom:1px solid #34424c;">
                    <p style="margin:0 0 4px;color:#7e8b94;font-size:10px;font-weight:bold;letter-spacing:.7px;text-transform:uppercase;">Klanttype</p>
                    <p style="margin:0;color:#ffffff;font-size:14px;">${safeCustomerType}</p>
                  </td>
                  <td width="50%" valign="top" style="padding:14px 16px;border-bottom:1px solid #34424c;">
                    <p style="margin:0 0 4px;color:#7e8b94;font-size:10px;font-weight:bold;letter-spacing:.7px;text-transform:uppercase;">Facturatiegegevens</p>
                    <p style="margin:0;color:#ffffff;font-size:14px;word-break:break-word;">${safeBusinessSummary || "Niet van toepassing"}</p>
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
                    <p style="margin:0 0 4px;color:#7e8b94;font-size:10px;font-weight:bold;letter-spacing:.7px;text-transform:uppercase;">Aanvraagtype</p>
                    <p style="margin:0;color:#ffffff;font-size:14px;font-weight:bold;">${safeRequestKind}</p>
                  </td>
                  <td width="50%" valign="top" style="padding:14px 16px;border-bottom:1px solid #34424c;">
                    <p style="margin:0 0 4px;color:#7e8b94;font-size:10px;font-weight:bold;letter-spacing:.7px;text-transform:uppercase;">Type website</p>
                    <p style="margin:0;color:#ffffff;font-size:14px;">${safeWebsiteType}</p>
                  </td>
                </tr>
                <tr>
                  <td width="50%" valign="top" style="padding:14px 16px;border-right:1px solid #34424c;border-bottom:1px solid #34424c;">
                    <p style="margin:0 0 4px;color:#7e8b94;font-size:10px;font-weight:bold;letter-spacing:.7px;text-transform:uppercase;">Budgetindicatie</p>
                    <p style="margin:0;color:#ffffff;font-size:14px;">${safeBudget}</p>
                  </td>
                  <td width="50%" valign="top" style="padding:14px 16px;border-bottom:1px solid #34424c;">
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
    `Nieuwe ${requestKindName}-aanvraag`,
    `Aanvraagnummer: ${data.requestId}`,
    `Aanvraagtype: ${requestKindName}`,
    `Ontvangstdatum: ${new Date(data.createdAt).toLocaleString("nl-BE")}`,
    `Naam: ${data.name}`,
    `Klanttype: ${safeCustomerType}`,
    ...businessLines,
    `E-mailadres: ${data.email}`,
    `Telefoon: ${data.phone || "Niet ingevuld"}`,
    `Type website: ${data.websiteType || "Niet van toepassing"}`,
    `Budget: ${data.budget || "Niet van toepassing"}`,
    `Timing: ${data.timing || "Niet van toepassing"}`,
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
<body bgcolor="#f3f5f7" style="margin:0!important;padding:0!important;background-color:#f3f5f7;color:#172033;font-family:Arial,Helvetica,sans-serif;">
  <div aria-hidden="true" style="display:none!important;visibility:hidden;mso-hide:all;font-size:1px;line-height:1px;max-height:0;max-width:0;overflow:hidden;opacity:0;color:#f3f5f7;">Je aanvraag werd goedgekeurd voor verdere bespreking.</div>
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
<body bgcolor="#f3f5f7" style="margin:0!important;padding:0!important;background-color:#f3f5f7;color:#172033;font-family:Arial,Helvetica,sans-serif;">
  <div aria-hidden="true" style="display:none!important;visibility:hidden;mso-hide:all;font-size:1px;line-height:1px;max-height:0;max-width:0;overflow:hidden;opacity:0;color:#f3f5f7;">De volgende stap voor je website is klaar.</div>
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
                    Je persoonlijke link blijft 7 dagen geldig. Je kunt je concept tussentijds opslaan en later via dezelfde link verdergaan.
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
    "Je persoonlijke link blijft 7 dagen geldig.",
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

export function buildIntakeReminderEmail(data: IntakeReminderEmailData) {
  const isInProgress = data.progressStatus === "in_progress";
  const isFinalReminder = data.reminderPhase === "REMINDER_2";
  const subject = isFinalReminder
    ? "Uw persoonlijke websitebriefing vervalt binnenkort"
    : "Uw persoonlijke websitebriefing staat nog klaar";
  const requestReference = `#${data.requestId.slice(0, 8).toUpperCase()}`;
  const expiresAt = new Date(data.expiresAt).toLocaleString("nl-BE", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "Europe/Brussels",
  });
  const safeName = escapeHtml(data.clientName);
  const safeCompany = data.company ? escapeHtml(data.company) : null;
  const safeReference = escapeHtml(requestReference);
  const safeIntakeUrl = escapeHtml(data.intakeUrl);
  const safeExpiresAt = escapeHtml(expiresAt);
  const statusMessage = isInProgress
    ? "U bent al begonnen. U kunt verdergaan waar u stopte."
    : "Uw intake staat nog voor u klaar.";
  const ctaLabel = isInProgress ? "Intake verder invullen" : "Intake invullen";
  const expiryMessage = isFinalReminder
    ? `Uw persoonlijke intake blijft beschikbaar tot ${safeExpiresAt}.`
    : `Uw persoonlijke intake blijft beschikbaar tot ${safeExpiresAt}.`;

  const html = `<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${subject}</title>
</head>
<body bgcolor="#f3f5f7" style="margin:0!important;padding:0!important;background-color:#f3f5f7;color:#172033;font-family:Arial,Helvetica,sans-serif;">
  <div aria-hidden="true" style="display:none!important;visibility:hidden;mso-hide:all;font-size:1px;line-height:1px;max-height:0;max-width:0;overflow:hidden;opacity:0;color:#f3f5f7;">${isFinalReminder ? "Uw persoonlijke intake vervalt binnenkort." : "Uw persoonlijke intake staat nog klaar."}</div>
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
              <h1 style="margin:0 0 24px;color:#12346b;font-size:28px;line-height:1.25;font-weight:700;">${isFinalReminder ? "Uw websitebriefing vervalt binnenkort" : "Uw websitebriefing staat nog klaar"}</h1>
              <p style="margin:0 0 16px;">Beste ${safeName},</p>
              <p style="margin:0 0 16px;">${statusMessage}</p>
              ${safeCompany ? `<p style="margin:0 0 16px;">Deze briefing hoort bij <strong>${safeCompany}</strong>.</p>` : ""}
              <p style="margin:0 0 24px;">${expiryMessage}</p>

              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;margin:0 0 24px;background-color:#f7f9fb;border:1px solid #dfe4ea;border-radius:6px;">
                <tr>
                  <td style="padding:18px 20px;">
                    <strong style="color:#172033;">Aanvraag ${safeReference}</strong><br>
                    Uw opgeslagen antwoorden blijven behouden. Gebruik dezelfde persoonlijke link om verder te gaan.
                  </td>
                </tr>
              </table>

              <table role="presentation" align="center" cellspacing="0" cellpadding="0" border="0" style="margin:0 auto 24px;">
                <tr>
                  <td align="center" bgcolor="#0ed8e6" style="border-radius:4px;background-color:#0ed8e6;">
                    <a href="${safeIntakeUrl}" style="display:inline-block;padding:14px 22px;color:#0b1118;text-decoration:none;font-weight:bold;">${ctaLabel}</a>
                  </td>
                </tr>
              </table>

              <p style="margin:0 0 16px;color:#5a6475;font-size:14px;"><strong>Persoonlijke link:</strong> stuur deze e-mail of link niet door. Wie de link bezit, kan uw briefing openen.</p>
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
    subject,
    "",
    `Beste ${data.clientName},`,
    "",
    statusMessage,
    ...(data.company ? [`Deze briefing hoort bij ${data.company}.`] : []),
    expiryMessage.replaceAll("&amp;", "&"),
    "",
    `Aanvraag ${requestReference}`,
    "Uw opgeslagen antwoorden blijven behouden. Gebruik dezelfde persoonlijke link om verder te gaan.",
    "",
    `${ctaLabel}:`,
    data.intakeUrl,
    "",
    "Stuur deze persoonlijke link niet door. Wie de link bezit, kan uw briefing openen.",
    "",
    "Met vriendelijke groet,",
    "Lorenzo Web Solutions",
    "",
    "Professionele websites voor zelfstandigen en kleine ondernemingen",
    "https://lorenzowebsolutions.be",
  ].join("\n");

  return { subject, html, text };
}

function replaceAsciiControlRunsWithSpace(value: string): string {
  let output = "";
  let replacingControlRun = false;
  for (const character of value) {
    const codePoint = character.codePointAt(0) ?? 0;
    const isControl = codePoint <= 0x1f || codePoint === 0x7f;
    if (isControl) {
      if (!replacingControlRun) output += " ";
    } else {
      output += character;
    }
    replacingControlRun = isControl;
  }
  return output;
}

const INTAKE_FEATURE_LABELS: Readonly<Record<string, string>> = Object.freeze({
  contact_form: "Contactformulier",
  quote_form: "Offerteformulier",
  google_maps: "Google Maps",
  social_links: "Social links",
  reviews: "Reviews",
  gallery: "Galerij",
  newsletter: "Nieuwsbrief",
  whatsapp: "WhatsApp",
  appointments: "Afspraken",
  reservations: "Reservaties",
  shop: "Webshop",
  online_payment: "Online betaling",
  online_payment_products: "Producten",
  online_payment_reservations: "Reservaties",
  online_payment_appointments: "Afspraken",
  online_payment_services: "Diensten",
  online_payment_registrations: "Inschrijvingen / activiteiten",
  online_payment_deposit: "Voorschot / reservatiebedrag",
  online_payment_other: "Andere online betaling",
  customer_login: "Klantlogin",
  downloads: "Downloads",
  search: "Zoeken",
  multilingual: "Meertalig",
  other: "Andere",
  unsure: "Nog niet zeker",
});

export function buildSubmittedIntakeAdminEmail(data: SubmittedIntakeAdminEmailData) {
  const output = data.output;
  const subjectLabel = replaceAsciiControlRunsWithSpace(output.customer.company || output.customer.name).trim();
  const referenceLabel = output.applicationReference || "Interne E2E-test";
  const subject = `Nieuwe aanvraag ${referenceLabel} — ${subjectLabel}`;
  const submittedAt = new Date(output.submittedAt).toLocaleString("nl-BE", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "Europe/Brussels",
  });
  const safeAdminUrl = escapeHtml(data.adminUrl);
  const money = (minor: number) => new Intl.NumberFormat("nl-BE", { style: "currency", currency: "EUR" }).format(minor / 100);
  const display = (value: unknown): string => {
    if (Array.isArray(value)) return value.map(display).filter(Boolean).join(", ");
    if (value && typeof value === "object") {
      return Object.entries(value as Record<string, unknown>)
        .filter(([, item]) => item !== null && item !== undefined && item !== "" && (!Array.isArray(item) || item.length))
        .map(([key, item]) => `${key.replaceAll("_", " ")}: ${display(item)}`).join("; ");
    }
    if (typeof value === "boolean") return value ? "Ja" : "Nee";
    return value === null || value === undefined || value === "" ? "" : String(value);
  };
  const section = (title: string, rows: Array<[string, unknown]>) => {
    const visibleRows = rows.filter(([, value]) => display(value));
    if (!visibleRows.length) return "";
    return `<h2 style="margin:24px 0 10px;color:#12346b;font-size:17px;">${escapeHtml(title)}</h2><table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;border-collapse:collapse;">${visibleRows.map(([label, value]) => `<tr><td style="width:34%;padding:6px 8px 6px 0;vertical-align:top;color:#5b6472;font-weight:bold;">${escapeHtml(label)}</td><td style="padding:6px 0;vertical-align:top;word-break:break-word;">${escapeHtml(display(value))}</td></tr>`).join("")}</table>`;
  };
  const recurringText = output.commercial.recurringServices.map((service) => `${service.label}: ${money(service.amountMinor)} per maand excl. btw`).join(" · ");
  const websiteFeatures = output.website.features.map((feature) => INTAKE_FEATURE_LABELS[feature] || feature);
  const sections = [
    section("Identiteit", [[output.applicationReference ? "Aanvraagnummer" : "Classificatie", referenceLabel], ["Ontvangen", submittedAt], ["Naam", output.customer.name], ["Bedrijf", output.customer.company], ["E-mail", output.customer.email], ["Telefoon", output.customer.phone]]),
    section("Commercieel", [["Pakket", output.commercial.packageLabel], ["Budget", output.commercial.budgetLabel], ["Indicatief projectminimum", `${money(output.commercial.knownMinimumMinor)} excl. btw`], ["Budget Guard", output.commercial.budgetStatus], ["Vervolgservice", recurringText]]),
    section("Project", [["Type website", output.project.websiteType], ["Bedrijfsomschrijving", output.project.businessDescription], ["Doelgroep", output.project.targetAudience], ["Bestaande website", output.project.hasExistingWebsite], ["Huidige website", output.project.currentWebsite], ["Te behouden", output.project.elementsToKeep], ["Verbeterpunten", output.project.improvementAreas], ["Domein", output.project.domain], ["Hosting", output.project.hostingStatus], ["Doelen", output.project.goals], ["Primaire conversie", output.project.primaryConversionGoal]]),
    section("Website", [["Pagina's", output.website.pages], ["Andere pagina's", output.website.otherPages], ["Functies", websiteFeatures], ["Paginascope-details", output.website.pageScopeDetails], ["Formulierdetails", output.website.quoteFormDetails], ["Webshop", output.website.webshop], ["Webshopdetails", output.website.webshopDetails], ["Boeking/reservatie", output.website.booking], ["Boekingsdetails", output.website.bookingDetails], ["Hoofdtaal", output.website.primaryLanguage], ["Extra talen", output.website.additionalLanguages], ["Meertaligheidsdetails", output.website.multilingualDetails], ["Downloaddetails", output.website.downloadDetails], ["Nieuwsbriefdetails", output.website.newsletterDetails], ["SEO", output.website.seoPriority], ["SEO-details", output.website.seoDetails], ["Integraties", output.website.integrations], ["Sociale kanalen", output.website.socialChannels]]),
    section("Branding & content", [["Huisstijl", output.brandingContent.brandStatus], ["Logo", output.brandingContent.logoStatus], ["Kleuren", output.brandingContent.brandColors], ["Ontwerpstijl", output.brandingContent.designStyles], ["Inspiratie", output.brandingContent.inspirationSites], ["Wat niet aanspreekt", output.brandingContent.dislikedStyles], ["Content", output.brandingContent.contentStatus], ["Beelden", output.brandingContent.imageStatus], ["Beeldondersteuning", output.brandingContent.imageSupport], ["Content/media-details", output.brandingContent.contentMediaDetails]]),
    section("Service & planning", [["Domeinstatus", output.servicePlanning.domainStatus], ["Onderhoud", output.servicePlanning.maintenanceInterest], ["Hostingondersteuning", output.servicePlanning.hostingSupport], ["Servicekeuzes", output.servicePlanning.hostingMaintenanceDetails], ["Timing", output.servicePlanning.timing], ["Deadline", output.servicePlanning.deadline], ["Reden deadline", output.servicePlanning.deadlineReason], ["Deadlinedetails", output.servicePlanning.deadlineDetails], ["Prioriteiten", output.servicePlanning.priorities], ["Budgetnotities", output.servicePlanning.budgetNotes], ["Opmerkingen", output.servicePlanning.notes]]),
  ].join("");

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
              <h1 style="margin:0 0 18px;color:#12346b;font-size:24px;line-height:1.3;">Nieuwe websiteaanvraag</h1>
              <p style="margin:0 0 20px;">De websitebriefing is definitief verzonden. Onderstaande prijs komt uit de opgeslagen, gezaghebbende pricing snapshot.</p>
              ${sections}
              <table role="presentation" cellspacing="0" cellpadding="0" border="0">
                <tr>
                  <td style="border-radius:6px;background-color:#b75d3b;">
                    <a href="${safeAdminUrl}" style="display:inline-block;padding:12px 18px;color:#ffffff;text-decoration:none;font-weight:bold;">Beveiligde briefing bekijken</a>
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
    "Nieuwe websiteaanvraag",
    "",
    `${output.applicationReference ? "Aanvraagnummer" : "Classificatie"}: ${referenceLabel}`,
    `Verzonden: ${submittedAt}`,
    `Naam: ${output.customer.name}`,
    ...(output.customer.company ? [`Bedrijf: ${output.customer.company}`] : []),
    `E-mail: ${output.customer.email}`,
    ...(output.customer.phone ? [`Telefoon: ${output.customer.phone}`] : []),
    "",
    `Pakket: ${output.commercial.packageLabel}`,
    `Budget: ${output.commercial.budgetLabel}`,
    `Indicatief projectminimum: ${money(output.commercial.knownMinimumMinor)} excl. btw`,
    `Budget Guard: ${output.commercial.budgetStatus}`,
    ...(recurringText ? [`Vervolgservice: ${recurringText}`] : []),
    "",
    ...["Project", "Website", "Branding & content", "Service & planning"].flatMap((title, index) => {
      const rows = index === 0
        ? [["Type website", output.project.websiteType], ["Bedrijfsomschrijving", output.project.businessDescription], ["Doelgroep", output.project.targetAudience], ["Bestaande website", output.project.hasExistingWebsite], ["Huidige website", output.project.currentWebsite], ["Te behouden", output.project.elementsToKeep], ["Verbeterpunten", output.project.improvementAreas], ["Domein", output.project.domain], ["Hosting", output.project.hostingStatus], ["Doelen", output.project.goals], ["Primaire conversie", output.project.primaryConversionGoal]]
        : index === 1
        ? [["Pagina's", output.website.pages], ["Andere pagina's", output.website.otherPages], ["Functies", websiteFeatures], ["Paginascope-details", output.website.pageScopeDetails], ["Formulierdetails", output.website.quoteFormDetails], ["Webshop", output.website.webshop], ["Webshopdetails", output.website.webshopDetails], ["Boeking/reservatie", output.website.booking], ["Boekingsdetails", output.website.bookingDetails], ["Hoofdtaal", output.website.primaryLanguage], ["Extra talen", output.website.additionalLanguages], ["Meertaligheidsdetails", output.website.multilingualDetails], ["Downloaddetails", output.website.downloadDetails], ["Nieuwsbriefdetails", output.website.newsletterDetails], ["SEO", output.website.seoPriority], ["SEO-details", output.website.seoDetails], ["Integraties", output.website.integrations], ["Sociale kanalen", output.website.socialChannels]]
        : index === 2
        ? [["Huisstijl", output.brandingContent.brandStatus], ["Logo", output.brandingContent.logoStatus], ["Kleuren", output.brandingContent.brandColors], ["Ontwerpstijl", output.brandingContent.designStyles], ["Inspiratie", output.brandingContent.inspirationSites], ["Wat niet aanspreekt", output.brandingContent.dislikedStyles], ["Content", output.brandingContent.contentStatus], ["Beelden", output.brandingContent.imageStatus], ["Beeldondersteuning", output.brandingContent.imageSupport], ["Content/media-details", output.brandingContent.contentMediaDetails]]
        : [["Domeinstatus", output.servicePlanning.domainStatus], ["Onderhoud", output.servicePlanning.maintenanceInterest], ["Hostingondersteuning", output.servicePlanning.hostingSupport], ["Servicekeuzes", output.servicePlanning.hostingMaintenanceDetails], ["Timing", output.servicePlanning.timing], ["Deadline", output.servicePlanning.deadline], ["Reden deadline", output.servicePlanning.deadlineReason], ["Deadlinedetails", output.servicePlanning.deadlineDetails], ["Prioriteiten", output.servicePlanning.priorities], ["Budgetnotities", output.servicePlanning.budgetNotes], ["Opmerkingen", output.servicePlanning.notes]];
      const lines = rows.filter(([, value]) => display(value)).map(([label, value]) => `${label}: ${display(value)}`);
      return lines.length ? [title.toUpperCase(), ...lines, ""] : [];
    }),
    "",
    `Beveiligde briefing bekijken: ${data.adminUrl}`,
  ].join("\n");

  return { subject, html, text };
}

export function buildQuotationEmail(template: QuotationEmailTemplate, data: QuotationEmailData) {
  const isDelivery = template === "QUOTATION_DELIVERY_NL_BE_v1";
  if (isDelivery && (!data.acceptanceUrl || !data.validUntil)) throw new Error("Quotation delivery data incomplete");
  if (!isDelivery && (!data.acceptedAt || !data.acceptingName)) throw new Error("Acceptance confirmation data incomplete");

  const reference = `${data.quotationNumber} (versie ${data.quotationVersion})`;
  const acceptedAt = data.acceptedAt ? new Date(data.acceptedAt).toLocaleString("nl-BE", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "Europe/Brussels",
  }) : null;
  const subject = isDelivery ? `Offerte ${reference}` : `Aanvaarding geregistreerd voor offerte ${reference}`;
  const heading = isDelivery ? "Je offerte is klaar" : "Aanvaarding geregistreerd";
  const body = isDelivery
    ? `Bekijk de offerte voor ${data.projectTitle} en registreer je beslissing uiterlijk op ${data.validUntil}.`
    : `${data.acceptingName} heeft de aanvaarding voor ${data.projectTitle} geregistreerd op ${acceptedAt}. Dit bericht is geen factuur of betalingsbewijs.`;
  const action = isDelivery
    ? `<p style="margin:24px 0;"><a href="${escapeHtml(data.acceptanceUrl!)}" style="display:inline-block;padding:13px 18px;background:#12346b;color:#fff;text-decoration:none;border-radius:4px;font-weight:bold;">Offerte bekijken</a></p><p style="color:#5a6475;font-size:13px;word-break:break-all;">Deze persoonlijke link niet doorsturen. Werkt de knop niet? Open:<br><a href="${escapeHtml(data.acceptanceUrl!)}">${escapeHtml(data.acceptanceUrl!)}</a></p>`
    : "";
  const html = `<!doctype html><html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(subject)}</title></head><body style="margin:0;padding:24px 12px;background:#f3f5f7;color:#172033;font-family:Arial,Helvetica,sans-serif;"><main style="max-width:600px;margin:auto;padding:28px 32px;background:#fff;border:1px solid #dfe4ea;border-top:4px solid #12346b;"><h1 style="margin:0 0 20px;color:#12346b;font-size:25px;">${heading}</h1><p>Beste ${escapeHtml(data.clientName)},</p><p>${escapeHtml(body)}</p><p><strong>Offerte:</strong> ${escapeHtml(reference)}</p>${action}<p style="margin-top:24px;">Met vriendelijke groet,<br><strong>Lorenzo Web Solutions</strong></p></main></body></html>`;
  const text = [heading, "", `Beste ${data.clientName},`, "", body, `Offerte: ${reference}`, ...(isDelivery ? ["", "Offerte bekijken:", data.acceptanceUrl!, "", "Stuur deze persoonlijke link niet door."] : []), "", "Met vriendelijke groet,", "Lorenzo Web Solutions"].join("\n");
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
