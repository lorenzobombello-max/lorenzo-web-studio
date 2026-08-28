import type { EmailDeliveryResult } from "../_shared/email-delivery.ts";
import type {
  QuotationOrchestrationContext,
  QuotationOrchestrationDependencies,
} from "./quotation-orchestrator.ts";

const DOCX_CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
const SHA256 = /^[0-9a-f]{64}$/;

type RpcResult = Readonly<{
  data: unknown;
  error: Readonly<{ message: string }> | null;
}>;

type StorageResult = Readonly<{
  data: unknown;
  error: Readonly<{ message: string }> | null;
}>;

export type QuotationRuntimeServiceClient = Readonly<{
  rpc(name: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
  storage: Readonly<{
    from(bucket: string): Readonly<{
      upload(
        path: string,
        bytes: Uint8Array,
        options: Readonly<{ contentType: string; upsert: false }>,
      ): PromiseLike<StorageResult>;
      download(path: string): PromiseLike<StorageResult>;
    }>;
  }>;
}>;

type RenderDocx = (input: Readonly<{
  templateBytes: Uint8Array;
  rendererPackage: Readonly<{
    generation_payload: Record<string, unknown>;
    display_markers: null;
  }>;
}>)=>PromiseLike<Readonly<{ buffer: Uint8Array; sha256: string }>>
  | Readonly<{ buffer: Uint8Array; sha256: string }>;

type Delivery = (input: Readonly<{
  issuanceId: string;
  requestedExpiresAt: null;
  capabilityIdempotencyKey: string;
  deliveryIdempotencyKey: string;
  adminAccessTokenHash: string;
  createdBy: string;
  from: string;
  resendApiKey: string;
}>)=>PromiseLike<EmailDeliveryResult>;

export type QuotationRuntimeOptions = Readonly<{
  actorAuthUserId: string;
  serviceClient: QuotationRuntimeServiceClient;
  templateBytes: Uint8Array;
  renderDocx: RenderDocx;
  deliver: Delivery;
  email: Readonly<{ from: string; resendApiKey: string }>;
}>;

function object(value: unknown, code: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(code);
  return value as Record<string, unknown>;
}

function row(value: unknown, code: string): Record<string, unknown> {
  if (!Array.isArray(value) || value.length !== 1) throw new Error(code);
  return object(value[0], code);
}

async function call(
  client: QuotationRuntimeServiceClient,
  name: string,
  args: Record<string, unknown>,
  code: string,
): Promise<unknown> {
  const result = await client.rpc(name, args);
  if (result.error) throw new Error(result.error.message);
  if (result.data === null || result.data === undefined) throw new Error(code);
  return result.data;
}

async function hashBytes(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest(
    "SHA-256",
    new Uint8Array(bytes).buffer,
  ));
  return [...digest].map((byte)=>byte.toString(16).padStart(2, "0")).join("");
}

async function bytesFromStorage(value: unknown): Promise<Uint8Array | null> {
  if (value instanceof Blob) return new Uint8Array(await value.arrayBuffer());
  if (value instanceof Uint8Array) return value;
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  return null;
}

export function createQuotationRuntimeDependencies(
  options: QuotationRuntimeOptions,
): QuotationOrchestrationDependencies {
  const actor = `operator:${options.actorAuthUserId}`;
  const client = options.serviceClient;
  let approvedTemplateSha256: string | null = null;

  return {
    resolveContext: async (actorAuthUserId, quoteRequestId)=>{
      if (actorAuthUserId !== options.actorAuthUserId) throw new Error("QUOTATION_ORCHESTRATION_ACTOR_MISMATCH");
      const data = object(await call(client, "resolve_first_customer_quotation_orchestration_v1", {
        p_actor_auth_user_id: actorAuthUserId,
        p_quote_request_id: quoteRequestId,
      }, "QUOTATION_ORCHESTRATION_CONTEXT_INVALID"), "QUOTATION_ORCHESTRATION_CONTEXT_INVALID");
      const templateData = object(data.template, "QUOTATION_ORCHESTRATION_CONTEXT_INVALID");
      const template: QuotationOrchestrationContext["template"] = {
        template_id: String(templateData.template_id || ""),
        template_version: String(templateData.template_version || ""),
        template_sha256: String(templateData.template_sha256 || ""),
        authority_status: String(templateData.authority_status || "") as "APPROVED",
      };
      approvedTemplateSha256 = template.template_sha256;
      if (!SHA256.test(approvedTemplateSha256)
        || await hashBytes(options.templateBytes) !== approvedTemplateSha256) {
        throw new Error("QUOTATION_TEMPLATE_HASH_INVALID");
      }
      return {
        approvalId: String(data.approval_id || ""),
        adminAccessTokenHash: String(data.admin_access_token_hash || ""),
        issueYear: Number(data.issue_year),
        issuanceInputSha256: String(data.issuance_input_sha256 || ""),
        template,
        seller: object(data.seller, "QUOTATION_ORCHESTRATION_CONTEXT_INVALID"),
      };
    },
    prepareIssuance: async (context, idempotencyKey)=>{
      const data = row(await call(client, "prepare_quotation_issuance_v2", {
        p_approval_id: context.approvalId,
        p_issue_year: context.issueYear,
        p_generation_contract_version: 1,
        p_issuance_input_sha256: context.issuanceInputSha256,
        p_idempotency_key: idempotencyKey,
        p_admin_access_token_hash: context.adminAccessTokenHash,
        p_prepared_by: actor,
      }, "QUOTATION_ISSUANCE_PREPARATION_INVALID"), "QUOTATION_ISSUANCE_PREPARATION_INVALID");
      return {
        issuanceId: String(data.issuance_id || ""),
        quotationNumber: String(data.quotation_number || ""),
        quotationVersion: Number(data.quotation_version),
      };
    },
    buildIssuePayload: async (context, issuance)=>{
      const data = row(await call(client, "build_quotation_issue_payload_v1", {
        p_issuance_id: issuance.issuanceId,
        p_template: context.template,
        p_seller: context.seller,
        p_admin_access_token_hash: context.adminAccessTokenHash,
      }, "QUOTATION_ISSUE_PAYLOAD_INVALID"), "QUOTATION_ISSUE_PAYLOAD_INVALID");
      return {
        payload: object(data.payload, "QUOTATION_ISSUE_PAYLOAD_INVALID"),
        payloadSha256: String(data.payload_sha256 || ""),
      };
    },
    renderDocx: async (issuePayload)=>{
      const observedTemplateHash = await hashBytes(options.templateBytes);
      if (!SHA256.test(observedTemplateHash) || observedTemplateHash !== approvedTemplateSha256) {
        throw new Error("QUOTATION_TEMPLATE_HASH_INVALID");
      }
      const result = await options.renderDocx({
        templateBytes: options.templateBytes,
        rendererPackage: {
          generation_payload: issuePayload.payload,
          display_markers: null,
        },
      });
      return { bytes: new Uint8Array(result.buffer), sha256: result.sha256 };
    },
    sha256: hashBytes,
    commitIssuance: async (context, issuance, payload, artifact, idempotencyKey)=>{
      const data = row(await call(client, "commit_quotation_issuance_v2", {
        p_issuance_id: issuance.issuanceId,
        p_commit_idempotency_key: idempotencyKey,
        p_issuance_input_sha256: context.issuanceInputSha256,
        p_generation_payload_sha256: payload.payloadSha256,
        p_template_id: context.template.template_id,
        p_template_version: context.template.template_version,
        p_template_sha256: context.template.template_sha256,
        p_generation_contract_version: 1,
        p_docx_sha256: artifact.sha256,
        p_docx_bytes: artifact.bytes,
        p_pdf_sha256: null,
        p_pdf_bytes: null,
        p_issued_by: actor,
        p_admin_access_token_hash: context.adminAccessTokenHash,
      }, "QUOTATION_ARTIFACT_COMMIT_INVALID"), "QUOTATION_ARTIFACT_COMMIT_INVALID");
      return { status: String(data.status) as "ISSUED", issuedAt: String(data.issued_at || "") };
    },
    archiveArtifact: async (issuance, artifact, idempotencyKey)=>{
      const path = `issuances/${issuance.issuanceId}/docx/${artifact.sha256}.docx`;
      const bucket = client.storage.from("quotation-artifacts");
      const uploaded = await bucket.upload(path, artifact.bytes, {
        contentType: DOCX_CONTENT_TYPE,
        upsert: false,
      });
      if (uploaded.error) {
        const existing = await bucket.download(path);
        const existingBytes = existing.error ? null : await bytesFromStorage(existing.data);
        if (!existingBytes || existingBytes.byteLength !== artifact.bytes.byteLength
          || await hashBytes(existingBytes) !== artifact.sha256) {
          throw new Error("QUOTATION_ARTIFACT_UPLOAD_FAILED");
        }
      }
      const data = row(await call(client, "register_quotation_artifact_v1", {
        p_issuance_id: issuance.issuanceId,
        p_artifact_type: "DOCX",
        p_observed_sha256: artifact.sha256,
        p_observed_bytes: artifact.bytes.byteLength,
        p_content_type: DOCX_CONTENT_TYPE,
        p_idempotency_key: idempotencyKey,
        p_actor: actor,
      }, "QUOTATION_ARTIFACT_ARCHIVE_INVALID"), "QUOTATION_ARTIFACT_ARCHIVE_INVALID");
      if (data.storage_object_path !== path) throw new Error("QUOTATION_ARTIFACT_ARCHIVE_INVALID");
      return { status: "ARCHIVED" };
    },
    deliverIssuance: async (context, issuance, idempotencyKeys)=>{
      try {
        return await options.deliver({
          issuanceId: issuance.issuanceId,
          requestedExpiresAt: null,
          capabilityIdempotencyKey: idempotencyKeys.capability,
          deliveryIdempotencyKey: idempotencyKeys.delivery,
          adminAccessTokenHash: context.adminAccessTokenHash,
          createdBy: actor,
          from: options.email.from,
          resendApiKey: options.email.resendApiKey,
        });
      } catch {
        throw new Error("QUOTATION_DELIVERY_FAILED");
      }
    },
  };
}