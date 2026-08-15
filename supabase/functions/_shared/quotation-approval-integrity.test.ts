import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  createQuotationApprovalIntegrity,
  verifyQuotationApprovalIntegrity,
} from "./quotation-approval-integrity.ts";

const secret = "quotation-approval-integrity-test-secret-material-v1";
const root = {
  approvalId: "d3e25000-0000-4000-8000-000000000001",
  contractVersion: 1,
  intakeId: "d3e21000-0000-4000-8000-000000000001",
  integrityRootVersion: 1 as const,
  payloadSha256: "a".repeat(64),
  pricingSnapshotId: "d3e22000-0000-4000-8000-000000000001",
  quoteRequestId: "d3e20000-0000-4000-8000-000000000001",
};

Deno.test("quotation approval integrity is deterministic and verifies", async () => {
  const integrity = await createQuotationApprovalIntegrity(root, "v1", secret);
  assert(await verifyQuotationApprovalIntegrity(integrity, secret));
  assertEquals(
    await createQuotationApprovalIntegrity(root, "v1", secret),
    integrity,
  );
});

Deno.test("quotation approval integrity binds every root identity", async () => {
  const integrity = await createQuotationApprovalIntegrity(root, "v1", secret);
  for (const [key, value] of Object.entries({
    approvalId: "d3e25000-0000-4000-8000-000000000002",
    contractVersion: 2,
    intakeId: "d3e21000-0000-4000-8000-000000000002",
    integrityRootVersion: 2,
    payloadSha256: "b".repeat(64),
    pricingSnapshotId: "d3e22000-0000-4000-8000-000000000002",
    quoteRequestId: "d3e20000-0000-4000-8000-000000000002",
  })) {
    const changed = structuredClone(integrity);
    (changed.root as unknown as Record<string, unknown>)[key] = value;
    assertEquals(
      await verifyQuotationApprovalIntegrity(changed, secret),
      false,
      key,
    );
  }
});

Deno.test("quotation approval proof cannot be transplanted or forged", async () => {
  const integrity = await createQuotationApprovalIntegrity(root, "v1", secret);
  assertEquals(
    await verifyQuotationApprovalIntegrity(integrity, `${secret}-wrong`),
    false,
  );
  assertEquals(
    await verifyQuotationApprovalIntegrity({ ...integrity, mac: "0".repeat(64) }, secret),
    false,
  );
});

Deno.test("quotation approval integrity rejects weak producer inputs", async () => {
  await assertRejects(
    () => createQuotationApprovalIntegrity(root, "v0", secret),
    TypeError,
    "INVALID_QUOTATION_APPROVAL_INTEGRITY_KEY_ID",
  );
  await assertRejects(
    () => createQuotationApprovalIntegrity(root, "v1", "short"),
    TypeError,
    "INVALID_QUOTATION_APPROVAL_INTEGRITY_SECRET",
  );
});