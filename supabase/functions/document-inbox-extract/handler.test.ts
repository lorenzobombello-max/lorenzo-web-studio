import { assertEquals } from "jsr:@std/assert@1";
import {
  type DocumentInboxExtractDependencies,
  DocumentInboxExtractError,
  handleDocumentInboxExtract,
} from "./handler.ts";

const ORIGIN = "https://lorenzowebsolutions.be";
const ITEM_ID = "fa020000-0000-4000-8000-000000000001";
const PDF = new TextEncoder().encode("%PDF-1.7 extraction fixture");

type RecordInput = Parameters<
  DocumentInboxExtractDependencies["recordExtraction"]
>[1];

function request(
  input: unknown = { document_inbox_item_id: ITEM_ID, expected_revision: 7 },
  authenticated = true,
): Request {
  return new Request(
    "https://project.supabase.co/functions/v1/document-inbox-extract",
    {
      method: "POST",
      headers: {
        origin: ORIGIN,
        "content-type": "application/json",
        ...(authenticated ? { authorization: "Bearer owner-jwt" } : {}),
      },
      body: JSON.stringify(input),
    },
  );
}

function dependencies(
  overrides: Partial<DocumentInboxExtractDependencies> = {},
) {
  const records: RecordInput[] = [];
  const providerInputs: unknown[] = [];
  const value: DocumentInboxExtractDependencies = {
    verifyUser: () => Promise.resolve(true),
    authorizeOwner: () => Promise.resolve(true),
    getInboxItem: () =>
      Promise.resolve({
        id: ITEM_ID,
        revision: 7,
        lifecycle_status: "RECEIVED",
        storage_bucket_id: "supplier-documents",
        storage_object_path: "documents/fixture.pdf",
        mime_type: "application/pdf",
      }),
    readBinary: () => Promise.resolve(PDF),
    provider: {
      name: "deterministic-test-provider",
      version: "contract-v1",
      extract: (input) => {
        providerInputs.push(input);
        return Promise.resolve({
          outcome: "success",
          candidates: {
            supplier_name: {
              value: " Supplier BV ",
              confidence: 0.91,
              evidence: " page:1 ",
            },
            invoice_number: {
              value: "INV-7",
              confidence: 0.88,
              evidence: "page:1",
            },
            invoice_date: {
              value: "2026-08-29",
              confidence: 0.86,
              evidence: "page:1",
            },
            document_type: {
              value: "INVOICE",
              confidence: 0.8,
              evidence: "page:1",
            },
            amount: { value: 121, confidence: 0.84, evidence: "page:1" },
            currency: { value: "EUR", confidence: 0.99, evidence: "page:1" },
          },
        });
      },
    },
    recordExtraction: (_jwt, input) => {
      records.push(input);
      return Promise.resolve({
        id: ITEM_ID,
        status: "REVIEW_REQUIRED",
        revision: 8,
      });
    },
    ...overrides,
  };
  return { value, records, providerInputs };
}

async function payload(response: Response): Promise<Record<string, unknown>> {
  return await response.json();
}

Deno.test("unauthenticated and unauthorized requests are rejected before item or storage access", async () => {
  let itemReads = 0;
  let binaryReads = 0;
  const deps = dependencies({
    getInboxItem: () => {
      itemReads++;
      return Promise.resolve(null);
    },
    readBinary: () => {
      binaryReads++;
      return Promise.resolve(PDF);
    },
  });
  assertEquals(
    (await handleDocumentInboxExtract(request({}, false), deps.value)).status,
    401,
  );
  deps.value = { ...deps.value, authorizeOwner: () => Promise.resolve(false) };
  assertEquals(
    (await handleDocumentInboxExtract(request(), deps.value)).status,
    403,
  );
  assertEquals(itemReads, 0);
  assertEquals(binaryReads, 0);
});

Deno.test("invalid and unknown inbox items are rejected", async () => {
  const invalid = dependencies();
  const invalidResponse = await handleDocumentInboxExtract(
    request({ document_inbox_item_id: "invalid", expected_revision: 7 }),
    invalid.value,
  );
  assertEquals(invalidResponse.status, 400);
  assertEquals(
    (await payload(invalidResponse)).code,
    "INVALID_DOCUMENT_INBOX_ITEM_ID",
  );

  const unknown = dependencies({ getInboxItem: () => Promise.resolve(null) });
  const unknownResponse = await handleDocumentInboxExtract(
    request(),
    unknown.value,
  );
  assertEquals(unknownResponse.status, 404);
  assertEquals(
    (await payload(unknownResponse)).code,
    "DOCUMENT_INBOX_ITEM_NOT_FOUND",
  );
});

Deno.test("unsupported state and stale revision stop before binary read", async () => {
  let binaryReads = 0;
  const readBinary = () => {
    binaryReads++;
    return Promise.resolve(PDF);
  };
  const terminal = dependencies({
    readBinary,
    getInboxItem: async () => ({
      id: ITEM_ID,
      revision: 7,
      lifecycle_status: "APPROVED",
      storage_bucket_id: "supplier-documents",
      storage_object_path: "documents/fixture.pdf",
      mime_type: "application/pdf",
    }),
  });
  assertEquals(
    (await handleDocumentInboxExtract(request(), terminal.value)).status,
    409,
  );
  const stale = dependencies({ readBinary });
  assertEquals(
    (await handleDocumentInboxExtract(
      request({ document_inbox_item_id: ITEM_ID, expected_revision: 6 }),
      stale.value,
    )).status,
    409,
  );
  assertEquals(binaryReads, 0);
});

Deno.test("missing and failed private binary reads are contained", async () => {
  const missing = dependencies({ readBinary: () => Promise.resolve(null) });
  const missingResponse = await handleDocumentInboxExtract(
    request(),
    missing.value,
  );
  assertEquals(missingResponse.status, 404);
  assertEquals(missing.records.length, 0);

  const failed = dependencies({
    readBinary: () => Promise.reject(new Error("private storage unavailable")),
  });
  const failedResponse = await handleDocumentInboxExtract(
    request(),
    failed.value,
  );
  assertEquals(failedResponse.status, 503);
  assertEquals(
    (await payload(failedResponse)).code,
    "DOCUMENT_BINARY_READ_FAILED",
  );
  assertEquals(failed.records.length, 0);
});

Deno.test("provider success is normalized and recorded with caller revision", async () => {
  const deps = dependencies();
  const result = await handleDocumentInboxExtract(request(), deps.value);
  const body = await payload(result);
  assertEquals(result.status, 200);
  assertEquals(body.extraction_status, "SUCCEEDED");
  assertEquals(deps.records.length, 1);
  assertEquals(deps.records[0].expectedRevision, 7);
  assertEquals(deps.records[0].provider, "deterministic-test-provider");
  assertEquals(deps.records[0].version, "contract-v1");
  assertEquals(deps.records[0].candidates.supplier_name, {
    value: "Supplier BV",
    confidence: 0.91,
    evidence: "page:1",
  });
  assertEquals(deps.records[0].candidates.document_reference.value, "INV-7");
  assertEquals(deps.records[0].candidates.document_date.value, "2026-08-29");
  assertEquals(Object.keys(deps.providerInputs[0] as object).sort(), [
    "bytes",
    "mimeType",
  ]);
});

Deno.test("provider partial and empty success deterministically map to PARTIAL", async () => {
  for (const outcome of ["partial", "success"] as const) {
    const deps = dependencies({
      provider: {
        name: "deterministic-test-provider",
        version: "contract-v1",
        extract: () => Promise.resolve({ outcome, candidates: {} }),
      },
    });
    const result = await handleDocumentInboxExtract(request(), deps.value);
    assertEquals(result.status, 200);
    assertEquals(deps.records[0].status, "PARTIAL");
  }
});

Deno.test("provider error and exception are recorded as extraction ERROR", async () => {
  const declared = dependencies({
    provider: {
      name: "deterministic-test-provider",
      version: "contract-v1",
      extract: () =>
        Promise.resolve({
          outcome: "error",
          candidates: {},
          errorCode: "NO_TEXT_FOUND",
        }),
    },
  });
  assertEquals(
    (await handleDocumentInboxExtract(request(), declared.value)).status,
    200,
  );
  assertEquals(declared.records[0].status, "ERROR");
  assertEquals(declared.records[0].errorCode, "NO_TEXT_FOUND");

  const thrown = dependencies({
    provider: {
      name: "must-not-leak",
      version: "must-not-leak",
      extract: () => Promise.reject(new Error("vendor detail")),
    },
  });
  assertEquals(
    (await handleDocumentInboxExtract(request(), thrown.value)).status,
    200,
  );
  assertEquals(thrown.records[0].status, "ERROR");
  assertEquals(thrown.records[0].errorCode, "PROVIDER_EXECUTION_ERROR");
  assertEquals(thrown.records[0].provider, null);
  assertEquals(thrown.records[0].version, null);
});

Deno.test("recording revision conflict is surfaced without retry", async () => {
  let writes = 0;
  const deps = dependencies({
    recordExtraction: () => {
      writes++;
      throw new DocumentInboxExtractError(
        409,
        "DOCUMENT_INBOX_REVISION_CONFLICT",
      );
    },
  });
  const result = await handleDocumentInboxExtract(request(), deps.value);
  assertEquals(result.status, 409);
  assertEquals(
    (await payload(result)).code,
    "DOCUMENT_INBOX_REVISION_CONFLICT",
  );
  assertEquals(writes, 1);
});

Deno.test("same-revision replay stops before a second provider call or extraction write", async () => {
  let revision = 7;
  let providerCalls = 0;
  let writes = 0;
  const deps = dependencies({
    getInboxItem: async () => ({
      id: ITEM_ID,
      revision,
      lifecycle_status: "REVIEW_REQUIRED",
      storage_bucket_id: "supplier-documents",
      storage_object_path: "documents/fixture.pdf",
      mime_type: "application/pdf",
    }),
    provider: {
      name: "deterministic-test-provider",
      version: "contract-v1",
      extract: () => {
        providerCalls++;
        return Promise.resolve({ outcome: "partial", candidates: {} });
      },
    },
    recordExtraction: (_jwt, input) => {
      writes++;
      revision++;
      return Promise.resolve({
        id: input.inboxItemId,
        status: "REVIEW_REQUIRED",
        revision,
      });
    },
  });
  assertEquals(
    (await handleDocumentInboxExtract(request(), deps.value)).status,
    200,
  );
  const replay = await handleDocumentInboxExtract(request(), deps.value);
  assertEquals(replay.status, 409);
  assertEquals(
    (await payload(replay)).code,
    "DOCUMENT_INBOX_REVISION_CONFLICT",
  );
  assertEquals(providerCalls, 1);
  assertEquals(writes, 1);
});

Deno.test("orchestrator source contains only extraction authority", async () => {
  const handler = await Deno.readTextFile(
    new URL("./handler.ts", import.meta.url),
  );
  assertEquals(handler.includes("recordExtraction"), true);
  for (
    const forbidden of [
      "confirm_document_inbox_values_v1",
      "approve_document_inbox_item_v1",
      "process_document_inbox_item_v1",
      "business_expenses",
      "supplier_documents",
      "business_expense_documents",
      "SUPABASE_SERVICE_ROLE_KEY",
    ]
  ) assertEquals(handler.includes(forbidden), false);
});
