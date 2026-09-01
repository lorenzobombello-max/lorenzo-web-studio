const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const PizZip = require("pizzip");

const templatePath = path.resolve(
  __dirname,
  "../../assets/docs/quotation/LWS_SDF_QUOTATION_NL_BE_OFFICIAL_v1.docx",
);
const expectedSha256 = "33da6dbbeef02876d0624d28fb17a16787cb1e7d0bde8ee74026664ba7739c1d";

test("official SDF template has the registered bytes and authority content", () => {
  const buffer = fs.readFileSync(templatePath);
  assert.equal(buffer.length, 178977);
  assert.equal(crypto.createHash("sha256").update(buffer).digest("hex"), expectedSha256);

  const zip = new PizZip(buffer);
  for (const part of ["[Content_Types].xml", "_rels/.rels", "word/document.xml"]) {
    assert.ok(zip.file(part), `missing required DOCX part ${part}`);
  }

  const documentXml = zip.file("word/document.xml").asText();
  const text = documentXml
    .replace(/<w:tab\/>/g, "\t")
    .replace(/<w:br\/>/g, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ");

  for (const expected of [
    "START",
    "GROEI",
    "PRO",
    "MAATWERK",
    "40%",
    "20%",
    "Geen vaste pakketprijs",
    "TE BESLISSEN",
  ]) {
    assert.ok(text.includes(expected), `missing official SDF content: ${expected}`);
  }
});
