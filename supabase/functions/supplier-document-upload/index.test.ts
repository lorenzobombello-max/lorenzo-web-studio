import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  isActiveOwnerIdentity,
  isStorageDuplicateError,
  resolveSupplierDocumentUploadServiceKey,
} from "./index.ts";

const serverKey = ["sb", "secret", "supplierDocumentUpload", "test"].join("_");

function environment(values: Record<string, string | undefined>) {
  return { get: (name: string) => values[name] };
}

Deno.test("supplier upload Phase A uses only the modern service binding", async () => {
  assertEquals(
    resolveSupplierDocumentUploadServiceKey(environment({
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: serverKey }),
    })),
    serverKey,
  );
  for (const serverBinding of [
    undefined,
    "not-json",
    JSON.stringify({ default: "legacy-service-key" }),
  ]) {
    assertEquals(
      resolveSupplierDocumentUploadServiceKey(environment({
        SUPABASE_SECRET_KEYS: serverBinding,
        SUPABASE_SERVICE_ROLE_KEY: "must-not-be-read",
      })),
      null,
    );
  }
  assertEquals(
    resolveSupplierDocumentUploadServiceKey(environment({
      SUPABASE_SERVICE_ROLE_KEY: "legacy-only-service-key",
    })),
    null,
  );

  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const config = await Deno.readTextFile(new URL("../../config.toml", import.meta.url));
  assert(source.includes('getSupabaseServerSecretKey("default"'));
  assert(!source.includes("SUPABASE_SERVICE_ROLE_KEY"));
  assert(source.includes('Deno.env.get("SUPABASE_ANON_KEY")'));
  assert(!source.includes("getSupabasePublishableKey"));
  assert(source.includes('code: "SERVER_CONFIGURATION_ERROR"'));
  assert(source.includes("status: 500"));
  assertEquals(source.match(/createClient\(/g)?.length, 2);
  assertEquals(source.match(/auth\.getUser\(jwt\)/g)?.length, 1);
  assertEquals(source.match(/\.rpc\(/g)?.length, 2);
  assertEquals(source.match(/storage\.from\(/g)?.length, 2);
  assertEquals(source.match(/(?<!storage)\.from\(/g)?.length ?? 0, 0);
  assert(source.includes('storage.from(input.bucket).upload('));
  assert(source.includes('storage.from(input.bucket).download('));
  assert(source.includes('upsert: input.upsert'));
  assert(source.includes('"get_current_operator_identity_v1"'));
  assert(source.includes('"finalize_supplier_document_upload_object_v1"'));
  assert(!source.match(/createSigned|signedUrl|\.move\(|\.copy\(|\.remove\(/));
  assert(/\[functions\.supplier-document-upload\]\r?\nverify_jwt = true/.test(config));
});

Deno.test("only ACTIVE owner identity is authorized", () => {
  assertEquals(
    isActiveOwnerIdentity({ role: "owner", status: "ACTIVE" }),
    true,
  );
  assertEquals(
    isActiveOwnerIdentity({ role: "admin", status: "ACTIVE" }),
    false,
  );
  assertEquals(
    isActiveOwnerIdentity({ role: "owner", status: "DISABLED" }),
    false,
  );
  assertEquals(
    isActiveOwnerIdentity({ role: "owner", status: "REVOKED" }),
    false,
  );
  assertEquals(isActiveOwnerIdentity(null), false);
});

Deno.test("Storage conflicts normalize to duplicate without broad error suppression", () => {
  assertEquals(
    isStorageDuplicateError({ statusCode: 409, message: "Conflict" }),
    true,
  );
  assertEquals(isStorageDuplicateError({ status: "409" }), true);
  assertEquals(
    isStorageDuplicateError({ message: "The resource already exists" }),
    true,
  );
  assertEquals(
    isStorageDuplicateError({
      statusCode: 500,
      message: "Storage unavailable",
    }),
    false,
  );
  assertEquals(isStorageDuplicateError(null), false);
});
