const fs = require("node:fs");
const path = require("node:path");
const PizZip = require("pizzip");
const {
  AlignmentType,
  BorderStyle,
  Document,
  Footer,
  Header,
  HeadingLevel,
  Packer,
  PageBreak,
  Paragraph,
  Table,
  TableCell,
  TableRow,
  TextRun,
  WidthType,
} = require("docx");

const outputPath = path.resolve(
  __dirname,
  "../../assets/docs/quotation/LWS_QUOTATION_NL_BE_TECHNICAL_v1.docx",
);

const text = (value, options = {}) =>
  new Paragraph({ children: [new TextRun({ text: value, ...options })] });
const heading = (value) =>
  new Paragraph({ text: value, heading: HeadingLevel.HEADING_2 });
const cell = (value, bold = false) =>
  new TableCell({
    children: [text(value, { bold })],
    margins: { top: 80, bottom: 80, left: 100, right: 100 },
  });
const borders = {
  top: { style: BorderStyle.SINGLE, size: 1, color: "B7BDC8" },
  bottom: { style: BorderStyle.SINGLE, size: 1, color: "B7BDC8" },
  left: { style: BorderStyle.SINGLE, size: 1, color: "B7BDC8" },
  right: { style: BorderStyle.SINGLE, size: 1, color: "B7BDC8" },
  insideHorizontal: { style: BorderStyle.SINGLE, size: 1, color: "D8DCE3" },
  insideVertical: { style: BorderStyle.SINGLE, size: 1, color: "D8DCE3" },
};

const document = new Document({
  creator: "Lorenzo Web Solutions",
  title: "LWS quotation technical master v1",
  description: "CANDIDATE automation master; not production template authority",
  styles: {
    default: { document: { run: { font: "Aptos", size: 20 } } },
    paragraphStyles: [
      {
        id: "Title",
        name: "Title",
        basedOn: "Normal",
        next: "Normal",
        run: { size: 34, bold: true, color: "17324D" },
        paragraph: { spacing: { after: 220 } },
      },
    ],
  },
  sections: [
    {
      properties: {
        page: { margin: { top: 900, right: 900, bottom: 900, left: 900 } },
      },
      headers: {
        default: new Header({
          children: [
            new Paragraph({
              alignment: AlignmentType.RIGHT,
              children: [new TextRun({ text: "Lorenzo Web Solutions | Technische offertemaster", color: "526273" })],
            }),
          ],
        }),
      },
      footers: {
        default: new Footer({
          children: [
            new Paragraph({
              alignment: AlignmentType.CENTER,
              children: [new TextRun({ text: "CANDIDATE | FINAL_DOCUMENT_PRESENTATION_PHASE DEFERRED", size: 16, color: "6B7280" })],
            }),
          ],
        }),
      },
      children: [
        new Paragraph({ text: "OFFERTE", style: "Title" }),
        text("{#preview_markers}", { bold: true, color: "B42318", size: 28 }),
        text("{primary}", { bold: true, color: "B42318", size: 28 }),
        text("{secondary}", { italic: true, color: "B42318" }),
        text("{/preview_markers}"),
        text("{#issue_identity}"),
        text("Offertenummer: {quotation_number}", { bold: true }),
        text("Versie: {quotation_version} | Status: {status}"),
        text("{/issue_identity}"),
        heading("Opdrachtgever"),
        text("{customer.legal_name}", { bold: true }),
        text("{#customer.contact_name_block}{value}{/customer.contact_name_block}"),
        text("{customer.address_line_1}"),
        text("{#customer.address_line_2_block}{value}{/customer.address_line_2_block}"),
        text("{customer.postal_code} {customer.city} ({customer.country_code})"),
        text("{customer.email}"),
        text("{#customer.enterprise_number_block}Ondernemingsnummer: {value}{/customer.enterprise_number_block}"),
        text("{#customer.vat_number_block}Btw-nummer: {value}{/customer.vat_number_block}"),
        heading("Project"),
        text("{project.project_title}", { bold: true }),
        text("Type: {project.project_type}"),
        text("{project.scope_summary}"),
        text("Talen: {project.requested_languages_text}"),
        text("Aantal inbegrepen pagina's: {project.included_page_count}"),
        text("{#project.indicative_timing_block}Indicatieve timing: {value}{/project.indicative_timing_block}"),
        text("{#features_section}"),
        text("Functies", { bold: true }),
        text("{#items}• {value}{/items}"),
        text("{/features_section}"),
        text("{#exclusions_section}"),
        text("Uitsluitingen", { bold: true }),
        text("{#items}• {value}{/items}"),
        text("{/exclusions_section}"),
        text("{#assumptions_section}"),
        text("Aannames", { bold: true }),
        text("{#items}• {value}{/items}"),
        text("{/assumptions_section}"),
        heading("Prijsopbouw"),
        new Table({
          width: { size: 100, type: WidthType.PERCENTAGE },
          borders,
          rows: [
            new TableRow({ children: [cell("Omschrijving", true), cell("Aantal", true), cell("Eenheid", true), cell("Prijs", true), cell("Korting", true), cell("Btw", true), cell("Netto", true)] }),
            new TableRow({ children: [cell("{#lines}{description}"), cell("{quantity}"), cell("{unit}"), cell("{unit_price}"), cell("{discount}"), cell("{vat}"), cell("{line_net_amount}{/lines}")] }),
          ],
        }),
        text("{#recurring_section}"),
        text("Terugkerende kosten zijn afzonderlijk opgenomen in de prijslijnen en totalen.", { italic: true }),
        text("{/recurring_section}"),
        heading("Totalen"),
        new Table({
          width: { size: 70, type: WidthType.PERCENTAGE },
          borders,
          rows: [
            new TableRow({ children: [cell("Eenmalig netto"), cell("{totals.one_time_subtotal}")] }),
            new TableRow({ children: [cell("Terugkerend netto"), cell("{totals.recurring_subtotal}")] }),
            new TableRow({ children: [cell("Korting"), cell("{totals.discount_total}")] }),
            new TableRow({ children: [cell("Btw-basis"), cell("{totals.vat_base}")] }),
            new TableRow({ children: [cell("Btw ({vat.rate_display})"), cell("{totals.vat_amount}")] }),
            new TableRow({ children: [cell("Totaal incl. btw", true), cell("{totals.total_gross}", true)] }),
          ],
        }),
        heading("Betalingsschema"),
        new Table({
          width: { size: 100, type: WidthType.PERCENTAGE },
          borders,
          rows: [
            new TableRow({ children: [cell("Moment", true), cell("Verdeling", true), cell("Trigger", true), cell("Termijn", true)] }),
            new TableRow({ children: [cell("{#payment_milestones}{label}"), cell("{allocation}"), cell("{trigger}"), cell("{due_terms}{/payment_milestones}")] }),
          ],
        }),
        heading("Geldigheid"),
        text("Geldig van {validity.valid_from} tot en met {validity.valid_until} ({validity.validity_days} dagen)."),
        heading("Voorwaarden"),
        text("Algemene voorwaarden: {legal.terms_reference}, versie {legal.terms_version}."),
        text("{#legal.agreement_block}Aanvullende overeenkomst: {reference}, versie {version}.{/legal.agreement_block}"),
        heading("Aanvaarding"),
        text("{acceptance_instruction}"),
        new Paragraph({ children: [new PageBreak()] }),
        heading("Dienstverlener"),
        text("{seller.legal_name}", { bold: true }),
        text("{seller.address_line_1}"),
        text("{#seller.address_line_2_block}{value}{/seller.address_line_2_block}"),
        text("{seller.postal_code} {seller.city} ({seller.country_code})"),
        text("Ondernemingsnummer: {seller.enterprise_number}"),
        text("Btw-nummer: {seller.vat_number}"),
        text("{seller.email} | {seller.website}"),
        text("{#seller.contact_name_block}Contact: {value}{/seller.contact_name_block}"),
      ],
    },
  ],
});

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
Packer.toBuffer(document).then((buffer) => {
  const zip = new PizZip(buffer);
  const fixedDate = new Date("2000-01-01T00:00:00.000Z");
  const core = zip.file("docProps/core.xml").asText()
    .replace(/<dcterms:created[^>]*>[^<]*<\/dcterms:created>/, '<dcterms:created xsi:type="dcterms:W3CDTF">2000-01-01T00:00:00.000Z</dcterms:created>')
    .replace(/<dcterms:modified[^>]*>[^<]*<\/dcterms:modified>/, '<dcterms:modified xsi:type="dcterms:W3CDTF">2000-01-01T00:00:00.000Z</dcterms:modified>');
  zip.file("docProps/core.xml", core, { date: fixedDate });
  for (const entry of Object.values(zip.files)) entry.date = fixedDate;
  const normalized = zip.generate({ type: "nodebuffer", compression: "DEFLATE" });
  fs.writeFileSync(outputPath, normalized);
  process.stdout.write(`${outputPath}\n`);
});