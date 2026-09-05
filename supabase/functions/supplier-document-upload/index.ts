import { createClient } from "npm:@supabase/supabase-js@2";
import {
  getSupabasePublishableKey,
  getSupabaseServerSecretKey,
  type SupabaseKeyBindingEnvironment,
} from "../_shared/supabase-key-bindings.ts";
import {
  handleSupplierDocumentUpload,
  type SupplierDocumentUploadResult,
} from "./handler.ts";

type StorageError = Readonly<{
  message?: string;
  status?: number | string;
  statusCode?: number | string;
}>;

export function isStorageDuplicateError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const storageError = error as StorageError;
  const status = Number(storageError.statusCode ?? storageError.status);
  return status === 409 ||
    /already exists|duplicate/i.test(storageError.message || "");
}

export function isActiveOwnerIdentity(data: unknown): boolean {
  if (!data || typeof data !== "object" || Array.isArray(data)) return false;
  const identity = data as Record<string, unknown>;
  return identity.role === "owner" && identity.status === "ACTIVE";
}

export function resolveSupplierDocumentUploadServiceKey(
  environment: SupabaseKeyBindingEnvironment = Deno.env,
): string | null {
  try {
    return getSupabaseServerSecretKey("default", environment);
  } catch {
    return null;
  }
}

export function resolveSupplierDocumentUploadPublishableKey(
  environment: SupabaseKeyBindingEnvironment = Deno.env,
): string | null {
  try {
    return getSupabasePublishableKey("default", environment);
  } catch {
    return null;
  }
}

async function sha256(bytes: Uint8Array): Promise<string> {
  const ownedBytes = new Uint8Array(bytes);
  const digest = await crypto.subtle.digest("SHA-256", ownedBytes.buffer);
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

if (import.meta.main) {
  Deno.serve((request) => {
    const url = Deno.env.get("SUPABASE_URL");
    const publishableKey = resolveSupplierDocumentUploadPublishableKey();
    const serviceRoleKey = resolveSupplierDocumentUploadServiceKey();
    if (!url || !publishableKey || !serviceRoleKey) {
      return new Response(
        JSON.stringify({ ok: false, code: "SERVER_CONFIGURATION_ERROR" }),
        {
          status: 500,
          headers: {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
          },
        },
      );
    }

    const clientFor = (jwt: string) =>
      createClient(url, publishableKey, {
        global: { headers: { Authorization: `Bearer ${jwt}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
    const serviceClient = createClient(url, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const storage = serviceClient.storage;

    return handleSupplierDocumentUpload(request, {
      verifyUser: async (jwt) => {
        const { data, error } = await clientFor(jwt).auth.getUser(jwt);
        return !error && Boolean(data.user);
      },
      authorizeOwner: async (jwt) => {
        const { data, error } = await clientFor(jwt).rpc(
          "get_current_operator_identity_v1",
        );
        return !error && isActiveOwnerIdentity(data);
      },
      putObject: async (input): Promise<SupplierDocumentUploadResult> => {
        const { error } = await storage.from(input.bucket).upload(
          input.objectPath,
          input.bytes,
          {
            contentType: input.mimeType,
            upsert: input.upsert,
          },
        );
        if (!error) return "stored";
        if (isStorageDuplicateError(error)) {
          const existing = await storage.from(input.bucket).download(
            input.objectPath,
          );
          if (existing.error || !existing.data) {
            throw existing.error || new Error("DUPLICATE_OBJECT_NOT_READABLE");
          }
          const existingBytes = new Uint8Array(
            await existing.data.arrayBuffer(),
          );
          if (
            existingBytes.byteLength !== input.bytes.byteLength ||
            await sha256(existingBytes) !== await sha256(input.bytes)
          ) {
            throw new Error("DUPLICATE_OBJECT_INTEGRITY_MISMATCH");
          }
          return "duplicate";
        }
        throw error;
      },
      finalizeObjectMetadata: async (input) => {
        const { data, error } = await serviceClient.rpc(
          "finalize_supplier_document_upload_object_v1",
          {
            p_storage_object_path: input.objectPath,
            p_sha256: input.sha256,
            p_mime_type: input.mimeType,
            p_byte_count: input.byteCount,
          },
        );
        if (error || data !== true) {
          throw error || new Error("STORAGE_METADATA_FINALIZATION_FAILED");
        }
      },
    });
  });
}
