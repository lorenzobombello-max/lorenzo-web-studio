const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const PizZip = require("pizzip");
const { renderQuotationDocx } = require("./renderer.cjs");

const [inputPath, outputPath, evidencePath] = process.argv.slice(2);
if (!inputPath || !outputPath || !evidencePath) {
  throw new Error("USAGE: issue-render.integration.cjs input.json output.docx evidence.json");
}

const input = JSON.parse(fs.readFileSync(inputPath, "utf8"));
const payload = input.payload;
assert.equal(payload.mode, "ISSUE");
assert.match(payload.quotation.quotation_number, /^LWS-OFF-[0-9]{4}-[0-9]{4}$/);
assert.equal(typeof payload.quotation.issuance_id, "string");
assert.equal(payload.template.template_id, "LWS_QUOTATION_NL_BE");
assert.equal(payload.template.template_version, "1.0.0-technical");
assert.equal(payload.template.template_sha256, "3ad2faaaa6a0a06e566f462e1c65c631006019c0d2d462333b8c693eb11154de");

const rendererPackage = {
  mode: "ISSUE",
  is_authoritative: true,
  generation_payload: payload,
  generation_payload_sha256: input.payload_sha256,
  template: payload.template,
  locale: payload.locale,
  requested_output: "DOCX",
};
const templatePath = path.resolve(
  __dirname,
  "../../assets/docs/quotation/LWS_QUOTATION_NL_BE_TECHNICAL_v1.docx",
);
const first = renderQuotationDocx({ templatePath, outputPath, rendererPackage });
const deterministicPath = `${outputPath}.deterministic.docx`;
const second = renderQuotationDocx({ templatePath, outputPath: deterministicPath, rendererPackage });
assert.equal(first.sha256, second.sha256);
assert.deepEqual(first.buffer, second.buffer);
fs.rmSync(deterministicPath, { force: true });

const zip = new PizZip(first.buffer);
for (const part of [
  "[Content_Types].xml",
  "_rels/.rels",
  "word/document.xml",
  "word/styles.xml",
  "word/_rels/document.xml.rels",
]) assert.ok(zip.file(part), `MISSING_OPENXML_PART:${part}`);

const relationships = zip.file("word/_rels/document.xml.rels").asText();
for (const match of relationships.matchAll(/Target="([^"#]+)"/g)) {
  const target = match[1];
  if (/^[a-z]+:/i.test(target)) continue;
  const resolved = path.posix.normalize(path.posix.join("word", target));
  assert.ok(resolved.startsWith("word/"), `RELATIONSHIP_TRAVERSAL:${target}`);
  assert.ok(zip.file(resolved), `BROKEN_RELATIONSHIP:${target}`);
}

const text = Object.keys(zip.files)
  .filter((name) => /^word\/(document|header\d*|footer\d*)\.xml$/.test(name))
  .map((name) => zip.file(name).asText().replace(/<[^>]+>/g, " "))
  .join(" ")
  .replace(/&amp;/g, "&")
  .replace(/\s+/g, " ");

for (const expected of [
  payload.quotation.quotation_number,
  payload.seller.legal_name,
  payload.customer.legal_name,
  payload.project.project_title,
  payload.lines[0].description,
  "21%",
  payload.payment_schedule.milestones[0].label,
  payload.legal_references.terms_reference,
]) assert.ok(text.includes(expected), `MISSING_RENDERED_CONTENT:${expected}`);
assert.doesNotMatch(text, /CONCEPT — NIET GELDIG ALS OFFERTE|Geen officieel offertenummer/);
assert.doesNotMatch(text, /\{[#/]?[^}]+\}|\bnull\b|\bundefined\b/i);
assert.doesNotMatch(text, /(capability|integrity_mac|hmac|service_role|[a-f0-9]{64})/i);

const templateSha256 = crypto
  .createHash("sha256")
  .update(fs.readFileSync(templatePath))
  .digest("hex");
assert.equal(templateSha256, payload.template.template_sha256);

fs.writeFileSync(evidencePath, JSON.stringify({
  docx_sha256: first.sha256,
  docx_bytes: first.buffer.length,
  generation_payload_sha256: input.payload_sha256,
  issuance_input_sha256: input.issuance_input_sha256,
  issuance_id: input.issuance_id,
  quotation_number: payload.quotation.quotation_number,
  template_id: payload.template.template_id,
  template_version: payload.template.template_version,
  template_sha256: payload.template.template_sha256,
}, null, 2));

process.stdout.write(JSON.stringify({
  quotation_number: payload.quotation.quotation_number,
  generation_payload_sha256: input.payload_sha256,
  docx_sha256: first.sha256,
  docx_bytes: first.buffer.length,
  openxml: "PASS",
  content: "PASS",
  leakage: "PASS",
  deterministic: "PASS",
}) + "\n");