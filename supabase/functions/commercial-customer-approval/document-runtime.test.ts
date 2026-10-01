import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { serveCustomerDeliveryDocument } from "./index.ts";

const PROJECT_ID = "ca200000-0000-4000-8000-000000000001";
const SESSION_DIGEST = "e".repeat(64);
const PDF_BYTES = new TextEncoder().encode("%PDF-1.7 exact customer bytes");
const PDF_SHA256 = "05d2b1bddd95863968d8493f0d5f4fca6d58396b606bef1d595de1e6e0634159";

function runtime(pdfSha256 = PDF_SHA256) {
  const events: string[] = [];
  const client = {
    rpc: async (name: string, input: Record<string, unknown>) => {
      events.push(name);
      if (name === "resolve_customer_website_delivery_document_view_v1") {
        assertEquals(input, { p_session_digest: SESSION_DIGEST, p_project_id: PROJECT_ID });
        return { data: {
          preview_session_id: "ca210000-0000-4000-8000-000000000001",
          view_derivative_id: "ca220000-0000-4000-8000-000000000001",
          artifact_id: "ca230000-0000-4000-8000-000000000001",
          project_id: PROJECT_ID,
          preview_version_id: "ca300000-0000-4000-8000-000000000001",
          document_version: 3,
          source_docx_sha256: "b".repeat(64),
          storage_bucket_id: "website-delivery-document-views",
          storage_object_path: "private/exact.pdf",
          content_type: "application/pdf",
          pdf_sha256: pdfSha256,
          pdf_bytes: PDF_BYTES.length,
        }, error: null };
      }
      if (name === "register_website_delivery_document_access_receipt_v1") {
        assertEquals(input.p_viewer_kind, "CUSTOMER");
        assertEquals(input.p_preview_session_id, "ca210000-0000-4000-8000-000000000001");
        assertEquals(input.p_served_pdf_sha256, PDF_SHA256);
        events.push("receipt-written");
        return { data: { access_receipt_id: "ca240000-0000-4000-8000-000000000001" }, error: null };
      }
      throw new Error(`unexpected rpc ${name}`);
    },
    storage: {
      from: (bucket: string) => ({
        download: async (path: string) => {
          events.push(`download:${bucket}:${path}`);
          return { data: new Blob([PDF_BYTES], { type: "application/pdf" }), error: null };
        },
      }),
    },
  };
  return { client, events };
}

Deno.test("customer document runtime verifies exact bytes before writing a retrieval receipt", async () => {
  const { client, events } = runtime();
  const response = await serveCustomerDeliveryDocument(
    { sessionDigest: SESSION_DIGEST, projectId: PROJECT_ID },
    client as never,
  );

  assertEquals(response.status, 200);
  assertEquals(new Uint8Array(await response.arrayBuffer()), PDF_BYTES);
  assertEquals(response.headers.get("content-type"), "application/pdf");
  assertEquals(response.headers.get("cache-control"), "private, no-store");
  assertEquals(response.headers.get("x-lws-document-version"), "3");
  assertEquals(response.headers.get("x-lws-document-sha256"), PDF_SHA256);
  assertEquals(events, [
    "resolve_customer_website_delivery_document_view_v1",
    "download:website-delivery-document-views:private/exact.pdf",
    "register_website_delivery_document_access_receipt_v1",
    "receipt-written",
  ]);
});

Deno.test("customer document runtime rejects a stored-byte hash mismatch without a receipt", async () => {
  const { client, events } = runtime("f".repeat(64));

  await assertRejects(
    () => serveCustomerDeliveryDocument(
      { sessionDigest: SESSION_DIGEST, projectId: PROJECT_ID },
      client as never,
    ),
    Error,
    "WEBSITE_DELIVERY_VIEW_HASH_MISMATCH",
  );
  assertEquals(events.includes("register_website_delivery_document_access_receipt_v1"), false);
});