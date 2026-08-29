import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  extractionRpcError,
  isActiveOwnerIdentity,
  selectInboxItem,
} from "./index.ts";

const ITEM_ID = "fa020000-0000-4000-8000-000000000001";

Deno.test("only ACTIVE owner identity is authorized", () => {
  assertEquals(
    isActiveOwnerIdentity({ role: "owner", status: "ACTIVE" }),
    true,
  );
  for (
    const identity of [
      null,
      { role: "admin", status: "ACTIVE" },
      { role: "owner", status: "DISABLED" },
      { role: "owner", status: "REVOKED" },
    ]
  ) assertEquals(isActiveOwnerIdentity(identity), false);
});

Deno.test("inbox response selection returns only bounded extraction metadata", () => {
  const selected = selectInboxItem({
    scope: "document_inbox",
    items: [{
      id: ITEM_ID,
      revision: 7,
      lifecycle_status: "RECEIVED",
      storage_bucket_id: "supplier-documents",
      storage_object_path: "documents/fixture.pdf",
      mime_type: "application/pdf",
      confirmed_supplier_name: "must not cross provider boundary",
    }],
  }, ITEM_ID);
  assertEquals(selected, {
    id: ITEM_ID,
    revision: 7,
    lifecycle_status: "RECEIVED",
    storage_bucket_id: "supplier-documents",
    storage_object_path: "documents/fixture.pdf",
    mime_type: "application/pdf",
  });
  assertEquals(selectInboxItem({ items: [] }, ITEM_ID), null);
  assertThrows(() => selectInboxItem({ items: [{ id: ITEM_ID }] }, ITEM_ID));
});

Deno.test("RPC conflicts and state failures map without retry", () => {
  assertEquals(extractionRpcError({ code: "40001" }).status, 409);
  assertEquals(
    extractionRpcError({ code: "40001" }).code,
    "DOCUMENT_INBOX_REVISION_CONFLICT",
  );
  assertEquals(extractionRpcError({ code: "P0001" }).status, 404);
  assertEquals(extractionRpcError({ code: "23514" }).status, 409);
  assertEquals(extractionRpcError({ code: "XX000" }).status, 503);
});

Deno.test("runtime adapter exposes no forbidden authority", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assertEquals(source.includes("record_document_inbox_extraction_v1"), true);
  for (
    const forbidden of [
      "confirm_document_inbox_values_v1",
      "approve_document_inbox_item_v1",
      "process_document_inbox_item_v1",
      "business_expenses",
      "supplier_documents",
      "business_expense_documents",
      "createSignedUrl",
      "fetch(",
    ]
  ) assertEquals(source.includes(forbidden), false);
});
