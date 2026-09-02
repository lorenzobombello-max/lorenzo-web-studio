import assert from "node:assert/strict";
import test from "node:test";
import {
  dossierSubstanceRequest,
  validateDossierSubstance,
  websiteSubstanceSections,
} from "../assets/js/operator-dossiers.mjs";

const quoteRequestId = "a1800000-0000-4000-8000-000000000001";

function websiteSubstance(overrides = {}) {
  return {
    quote_request_id: quoteRequestId,
    request_kind: "website",
    request: {
      reference: "#A1800000",
      original_text: "<script>exact customer text</script>",
      requested_service: "Website op maat",
      requested_at: "2099-01-01T10:00:00Z",
    },
    customer: {
      name: "Customer",
      company: "Customer BV",
      email: "customer@example.test",
      phone: null,
    },
    intake: {
      intake_id: "a1800000-0000-4000-8000-000000000002",
      status: "in_progress",
      invitation_state: "ACTIVATED",
      invited_at: "2099-01-01T10:01:00Z",
      started_at: "2099-01-01T10:02:00Z",
      submitted_at: null,
      structured_answers: {
        business_description: "Exact business context",
        requested_features: ["contact_form"],
        shop_required: true,
        shop_details: {
          approx_product_count: 12,
          online_payments: true,
          forbidden_secret: "must not render",
        },
        unknown_root: "must not render",
      },
    },
    documents: { customer_request_count: 1, uploaded_document_count: 2 },
    ...overrides,
  };
}

test("dossier substance request is bound to one quote request UUID", () => {
  assert.deepEqual(dossierSubstanceRequest({ quote_request_id: quoteRequestId }), {
    action: "get_dossier_substance",
    quote_request_id: quoteRequestId,
  });
  assert.deepEqual(dossierSubstanceRequest({ raw: { quote_request_id: quoteRequestId } }), {
    action: "get_dossier_substance",
    quote_request_id: quoteRequestId,
  });
  assert.throws(() => dossierSubstanceRequest({ quote_request_id: "invalid" }), /INVALID_DOSSIER_SUBSTANCE_REQUEST/);
});

test("dossier substance accepts the exact record binding and rejects drift", () => {
  const value = websiteSubstance();
  assert.equal(validateDossierSubstance(value, quoteRequestId), value);
  assert.throws(() => validateDossierSubstance({ ...value, secret: "drift" }, quoteRequestId), /INVALID_DOSSIER_SUBSTANCE/);
  assert.throws(() => validateDossierSubstance(value, "a1800000-0000-4000-8000-000000000099"), /INVALID_DOSSIER_SUBSTANCE/);
});

test("Website presentation uses approved labels and never traverses unknown JSON keys", () => {
  const value = websiteSubstance();
  const sections = websiteSubstanceSections(value.intake.structured_answers);
  const rows = sections.flatMap((section) => section.rows);
  assert.deepEqual(rows.find((row) => row.label === "Bedrijfsomschrijving"), {
    label: "Bedrijfsomschrijving",
    value: "Exact business context",
  });
  assert.deepEqual(rows.find((row) => row.label === "Online betalingen"), {
    label: "Online betalingen",
    value: "Ja",
  });
  assert.equal(JSON.stringify(sections).includes("forbidden_secret"), false);
  assert.equal(JSON.stringify(sections).includes("unknown_root"), false);
  assert.equal(value.request.original_text, "<script>exact customer text</script>");
});
