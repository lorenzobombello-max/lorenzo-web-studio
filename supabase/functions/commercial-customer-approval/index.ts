import { createClient } from "npm:@supabase/supabase-js@2";
import {
  getSupabaseServerSecretKey,
  type SupabaseKeyBindingEnvironment,
} from "../_shared/supabase-key-bindings.ts";
import { handleCommercialCustomerApproval } from "./handler.ts";

type RedemptionRpcResult = Readonly<{
  project_id: string;
  preview_access_id: string;
  preview_version_id: string;
  expires_at: string;
}>;

type ApprovalContextRpcResult = Readonly<{
  project_id: string;
  current_state: string;
  revision: number;
  preview_access_id: string;
  preview_version_id: string;
  preview_version_number: number;
  preview_content_reference: string;
  preview_content_sha256: string;
  statement_version: string;
  statement_sha256: string;
  statement_text: string;
  statement_section: string;
  source_filename: string;
  source_drive_id: string;
  source_byte_length: number;
  approval_replay_available: boolean;
  approval_expected_state: string;
  approval_expected_revision: number;
  session_expires_at: string;
  delivery_document: Readonly<{
    view_derivative_id: string;
    document_version: number;
    pdf_sha256: string;
    source_docx_sha256: string;
    pdf_bytes: number;
  }> | null;
  delivery_document_viewed: boolean;
  acceptance: Readonly<{
    accepted_at: string;
    document_version: number;
    pdf_sha256: string;
    statement_version: string;
  }> | null;
}>;

type ApprovalRpcResult = Readonly<{
  project_id: string;
  resulting_state: string;
  revision: number;
  command_type: string;
}>;

type CustomerDocumentClient = Readonly<{
  rpc(name: string, input: Record<string, unknown>): PromiseLike<Readonly<{
    data: unknown;
    error: Readonly<{ message: string }> | null;
  }>>;
  storage: Readonly<{
    from(bucket: string): Readonly<{
      download(path: string): PromiseLike<Readonly<{
        data: Blob | null;
        error: Readonly<{ message: string }> | null;
      }>>;
    }>;
  }>;
}>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/;

function documentRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("INVALID_WEBSITE_DELIVERY_VIEW_RESPONSE");
  }
  return value as Record<string, unknown>;
}

async function documentSha256(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes).buffer);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function serveCustomerDeliveryDocument(
  input: Readonly<{ sessionDigest: string; projectId: string }>,
  client: CustomerDocumentClient,
): Promise<Response> {
  const resolvedResponse = await client.rpc(
    "resolve_customer_website_delivery_document_view_v1",
    { p_session_digest: input.sessionDigest, p_project_id: input.projectId },
  );
  if (resolvedResponse.error || !resolvedResponse.data) {
    throw new Error(resolvedResponse.error?.message || "WEBSITE_DELIVERY_VIEW_NOT_FOUND");
  }
  const view = documentRecord(resolvedResponse.data);
  if (
    !UUID.test(String(view.preview_session_id || "")) ||
    !UUID.test(String(view.view_derivative_id || "")) ||
    view.project_id !== input.projectId ||
    !Number.isSafeInteger(view.document_version) || Number(view.document_version) < 1 ||
    view.storage_bucket_id !== "website-delivery-document-views" ||
    typeof view.storage_object_path !== "string" || !view.storage_object_path ||
    view.content_type !== "application/pdf" ||
    !SHA256.test(String(view.source_docx_sha256 || "")) ||
    !SHA256.test(String(view.pdf_sha256 || "")) ||
    !Number.isSafeInteger(view.pdf_bytes) || Number(view.pdf_bytes) < 1
  ) throw new Error("INVALID_WEBSITE_DELIVERY_VIEW_RESPONSE");

  const downloaded = await client.storage.from(String(view.storage_bucket_id))
    .download(String(view.storage_object_path));
  if (downloaded.error || !downloaded.data) {
    throw new Error(downloaded.error?.message || "WEBSITE_DELIVERY_VIEW_DOWNLOAD_FAILED");
  }
  const bytes = new Uint8Array(await downloaded.data.arrayBuffer());
  const actualSha256 = await documentSha256(bytes);
  if (bytes.byteLength !== view.pdf_bytes || actualSha256 !== view.pdf_sha256) {
    throw new Error("WEBSITE_DELIVERY_VIEW_HASH_MISMATCH");
  }

  const receiptResponse = await client.rpc(
    "register_website_delivery_document_access_receipt_v1",
    {
      p_view_derivative_id: view.view_derivative_id,
      p_viewer_kind: "CUSTOMER",
      p_operator_auth_user_id: null,
      p_preview_session_id: view.preview_session_id,
      p_served_pdf_sha256: actualSha256,
      p_served_pdf_bytes: bytes.byteLength,
      p_served_by: "commercial-customer-approval",
    },
  );
  if (receiptResponse.error || !receiptResponse.data) {
    throw new Error(receiptResponse.error?.message || "WEBSITE_DELIVERY_VIEW_RECEIPT_FAILED");
  }

  return new Response(bytes, {
    status: 200,
    headers: {
      "cache-control": "private, no-store",
      "content-disposition": `inline; filename="opleverdocument-v${view.document_version}.pdf"`,
      "content-length": String(bytes.byteLength),
      "content-type": "application/pdf",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      "x-lws-document-sha256": actualSha256,
      "x-lws-document-version": String(view.document_version),
      "x-lws-source-docx-sha256": String(view.source_docx_sha256),
    },
  });
}

export function createCommercialCustomerApprovalRuntime(
  environment: SupabaseKeyBindingEnvironment = Deno.env,
) {
  const url = environment.get("SUPABASE_URL") ?? "";
  const publicOrigin = environment.get("LWS_COMMERCIAL_CUSTOMER_APPROVAL_ORIGIN") ?? "";
  if (!url || !publicOrigin) throw new Error("SERVER_CONFIGURATION_ERROR");

  const client = createClient(url, getSupabaseServerSecretKey("default", environment), {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return Object.freeze({
    publicOrigin: new URL(publicOrigin).origin,
    randomBytes: () => crypto.getRandomValues(new Uint8Array(32)),
    redeemAccess: async (input: Readonly<{
      accessTokenDigest: string;
      projectId: string;
      sessionDigest: string;
    }>) => {
      const { data, error } = await client.rpc("redeem_customer_preview_access_v1", {
        p_token_digest: input.accessTokenDigest,
        p_project_id: input.projectId,
        p_session_digest: input.sessionDigest,
      });
      if (error || !data) throw new Error(error?.message || "ACCESS_DENIED");
      const result = data as RedemptionRpcResult;
      return {
        projectId: result.project_id,
        previewAccessId: result.preview_access_id,
        previewVersionId: result.preview_version_id,
        expiresAt: result.expires_at,
      };
    },
    resolveContext: async (input: Readonly<{ sessionDigest: string; projectId: string }>) => {
      const { data, error } = await client.rpc("resolve_customer_approval_context_v1", {
        p_session_digest: input.sessionDigest,
        p_project_id: input.projectId,
      });
      if (error || !data) throw new Error(error?.message || "ACCESS_DENIED");
      const result = data as ApprovalContextRpcResult;
      return {
        projectId: result.project_id,
        currentState: result.current_state,
        revision: result.revision,
        previewAccessId: result.preview_access_id,
        previewVersionId: result.preview_version_id,
        previewVersionNumber: result.preview_version_number,
        previewContentReference: result.preview_content_reference,
        previewContentSha256: result.preview_content_sha256,
        statementVersion: result.statement_version,
        statementSha256: result.statement_sha256,
        statementText: result.statement_text,
        statementSection: result.statement_section,
        sourceFilename: result.source_filename,
        sourceDriveId: result.source_drive_id,
        sourceByteLength: result.source_byte_length,
        approvalReplayAvailable: result.approval_replay_available,
        approvalExpectedState: result.approval_expected_state,
        approvalExpectedRevision: result.approval_expected_revision,
        sessionExpiresAt: result.session_expires_at,
        deliveryDocument: result.delivery_document
          ? {
            viewDerivativeId: result.delivery_document.view_derivative_id,
            documentVersion: result.delivery_document.document_version,
            pdfSha256: result.delivery_document.pdf_sha256,
            sourceDocxSha256: result.delivery_document.source_docx_sha256,
            pdfBytes: result.delivery_document.pdf_bytes,
          }
          : null,
        deliveryDocumentViewed: result.delivery_document_viewed === true,
        acceptance: result.acceptance
          ? {
            acceptedAt: result.acceptance.accepted_at,
            documentVersion: result.acceptance.document_version,
            pdfSha256: result.acceptance.pdf_sha256,
            statementVersion: result.acceptance.statement_version,
          }
          : null,
      };
    },
    serveDocument: async (input: Readonly<{ sessionDigest: string; projectId: string }>) =>
      await serveCustomerDeliveryDocument(input, client),
    submitApproval: async (input: Readonly<{
      sessionDigest: string;
      projectId: string;
      expectedState: string;
      expectedRevision: number;
      idempotencyKey: string;
      previewVersionId: string;
      statementVersion: string;
      statementSha256: string;
      viewedDocumentVersion: number;
      viewedPdfSha256: string;
    }>) => {
      const { data, error } = await client.rpc("execute_customer_commercial_command_v1", {
        p_session_digest: input.sessionDigest,
        p_project_id: input.projectId,
        p_command_type: "submit_customer_approval",
        p_expected_state: input.expectedState,
        p_expected_revision: input.expectedRevision,
        p_idempotency_key: input.idempotencyKey,
        p_payload: {
          preview_version_id: input.previewVersionId,
          statement_version: input.statementVersion,
          statement_sha256: input.statementSha256,
          viewed_document_version: input.viewedDocumentVersion,
          viewed_pdf_sha256: input.viewedPdfSha256,
        },
      });
      if (error || !data) throw new Error(error?.message || "APPROVAL_NOT_AVAILABLE");
      const result = data as ApprovalRpcResult;
      return {
        projectId: result.project_id,
        resultingState: result.resulting_state,
        revision: result.revision,
        commandType: result.command_type,
      };
    },
  });
}

if (import.meta.main) {
  const service = createCommercialCustomerApprovalRuntime();
  Deno.serve((request) => handleCommercialCustomerApproval(request, service));
}