import { createClient } from "npm:@supabase/supabase-js@2";
import {
  type DocumentExtractionProvider,
  DocumentInboxExtractError,
  type DocumentInboxExtractionItem,
  handleDocumentInboxExtract,
} from "./handler.ts";

type RpcError = Readonly<{ code?: string; message?: string }>;

export function isActiveOwnerIdentity(data: unknown): boolean {
  if (!data || typeof data !== "object" || Array.isArray(data)) return false;
  const identity = data as Record<string, unknown>;
  return identity.role === "owner" && identity.status === "ACTIVE";
}

export function selectInboxItem(
  data: unknown,
  itemId: string,
): DocumentInboxExtractionItem | null {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new DocumentInboxExtractError(503, "INVALID_DOCUMENT_INBOX_RESPONSE");
  }
  const items = (data as Record<string, unknown>).items;
  if (!Array.isArray(items)) {
    throw new DocumentInboxExtractError(503, "INVALID_DOCUMENT_INBOX_RESPONSE");
  }
  const item = items.find((candidate) =>
    candidate && typeof candidate === "object" &&
    (candidate as Record<string, unknown>).id === itemId
  );
  if (!item) return null;
  const value = item as Record<string, unknown>;
  if (
    typeof value.id !== "string" || !Number.isSafeInteger(value.revision) ||
    typeof value.lifecycle_status !== "string" ||
    typeof value.storage_bucket_id !== "string" ||
    typeof value.storage_object_path !== "string" ||
    typeof value.mime_type !== "string"
  ) {
    throw new DocumentInboxExtractError(503, "INVALID_DOCUMENT_INBOX_ITEM");
  }
  return {
    id: value.id,
    revision: Number(value.revision),
    lifecycle_status: value.lifecycle_status,
    storage_bucket_id: value.storage_bucket_id,
    storage_object_path: value.storage_object_path,
    mime_type: value.mime_type,
  };
}

export function extractionRpcError(error: RpcError): DocumentInboxExtractError {
  if (
    error.code === "40001" ||
    /DOCUMENT_INBOX_REVISION_CONFLICT/.test(error.message || "")
  ) {
    return new DocumentInboxExtractError(
      409,
      "DOCUMENT_INBOX_REVISION_CONFLICT",
    );
  }
  if (
    error.code === "P0001" ||
    /DOCUMENT_INBOX_ITEM_NOT_FOUND/.test(error.message || "")
  ) {
    return new DocumentInboxExtractError(404, "DOCUMENT_INBOX_ITEM_NOT_FOUND");
  }
  if (
    error.code === "23514" ||
    /DOCUMENT_INBOX_NOT_REVIEWABLE/.test(error.message || "")
  ) {
    return new DocumentInboxExtractError(409, "DOCUMENT_INBOX_NOT_REVIEWABLE");
  }
  return new DocumentInboxExtractError(
    503,
    "DOCUMENT_INBOX_EXTRACTION_WRITE_FAILED",
  );
}

const coreOnlyProvider: DocumentExtractionProvider = {
  name: "sdf-core-only",
  version: "sdf-2a-v1",
  extract: () =>
    Promise.resolve({
      outcome: "error",
      candidates: {},
      errorCode: "EXTRACTION_PROVIDER_NOT_CONFIGURED",
    }),
};

if (import.meta.main) {
  Deno.serve((request) => {
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceRoleKey) {
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
      createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${jwt}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
    const serviceClient = createClient(url, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    return handleDocumentInboxExtract(request, {
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
      getInboxItem: async (jwt, itemId) => {
        const { data, error } = await clientFor(jwt).rpc(
          "get_document_inbox_v1",
          { p_lifecycle_status: null, p_record_classification: "production" },
        );
        if (error) {
          throw new DocumentInboxExtractError(
            503,
            "DOCUMENT_INBOX_READ_FAILED",
          );
        }
        return selectInboxItem(data, itemId);
      },
      readBinary: async (input) => {
        const { data, error } = await serviceClient.storage.from(input.bucket)
          .download(input.objectPath);
        if (error || !data) {
          throw error || new Error("DOCUMENT_BINARY_NOT_FOUND");
        }
        return new Uint8Array(await data.arrayBuffer());
      },
      provider: coreOnlyProvider,
      recordExtraction: async (jwt, input) => {
        const { data, error } = await clientFor(jwt).rpc(
          "record_document_inbox_extraction_v1",
          {
            p_inbox_item_id: input.inboxItemId,
            p_expected_revision: input.expectedRevision,
            p_extraction_status: input.status,
            p_provider: input.provider,
            p_version: input.version,
            p_candidates: input.candidates,
            p_error_code: input.errorCode,
          },
        );
        if (error) throw extractionRpcError(error);
        if (!data || typeof data !== "object" || Array.isArray(data)) {
          throw new DocumentInboxExtractError(
            503,
            "INVALID_EXTRACTION_WRITE_RESPONSE",
          );
        }
        const result = data as Record<string, unknown>;
        if (
          typeof result.id !== "string" || typeof result.status !== "string" ||
          !Number.isSafeInteger(result.revision)
        ) {
          throw new DocumentInboxExtractError(
            503,
            "INVALID_EXTRACTION_WRITE_RESPONSE",
          );
        }
        return {
          id: result.id,
          status: result.status,
          revision: Number(result.revision),
        };
      },
    });
  });
}
