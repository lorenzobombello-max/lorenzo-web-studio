import { assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { buildAuthoritativeSubmitData } from "./authoritative-intake.ts";
import {
  buildPricingSnapshotV2,
  resolveBudgetEvidence,
} from "./pricing-engine.ts";

Deno.test("complete authoritative submit data defeats sparse concurrent draft divergence", async () => {
  const storedDraftA = {
    requested_pages: ["home", "quote_request"],
    requested_features: ["quote_form"],
    quote_form_details: {
      structure_scope: "basic_single_section",
      file_uploads: false,
      form_count: 1,
    },
    content_media_details: {
      copywriting_scope: "light",
      image_work_scope: "standard",
      paid_stock_handling: false,
    },
  };
  const sparseSubmit = { confirmation: true };
  const authoritativeDataA = buildAuthoritativeSubmitData(
    storedDraftA,
    sparseSubmit,
  );
  const snapshotA = await buildPricingSnapshotV2(
    authoritativeDataA,
    resolveBudgetEvidence(
      "EUR 3.200 t/m EUR 6.000",
      "budget_guard_v1",
      "3200_to_6000_inclusive",
    ),
  );

  const concurrentDraftB = {
    ...storedDraftA,
    quote_form_details: {
      structure_scope: "extended_standard_structure",
      file_uploads: true,
      form_count: 2,
    },
  };
  const divergentSparseResult = buildAuthoritativeSubmitData(
    concurrentDraftB,
    sparseSubmit,
  );
  const divergentSnapshot = await buildPricingSnapshotV2(
    divergentSparseResult,
    resolveBudgetEvidence(
      "EUR 3.200 t/m EUR 6.000",
      "budget_guard_v1",
      "3200_to_6000_inclusive",
    ),
  );
  const submittedData = buildAuthoritativeSubmitData(
    concurrentDraftB,
    authoritativeDataA,
  );
  const submittedSnapshot = await buildPricingSnapshotV2(
    submittedData,
    resolveBudgetEvidence(
      "EUR 3.200 t/m EUR 6.000",
      "budget_guard_v1",
      "3200_to_6000_inclusive",
    ),
  );

  assertNotEquals(divergentSnapshot.normalizedScope, snapshotA.normalizedScope);
  assertNotEquals(divergentSnapshot.calculation, snapshotA.calculation);
  assertEquals(submittedData, authoritativeDataA);
  assertEquals(submittedSnapshot.normalizedScope, snapshotA.normalizedScope);
  assertEquals(submittedSnapshot.calculation, snapshotA.calculation);
});
