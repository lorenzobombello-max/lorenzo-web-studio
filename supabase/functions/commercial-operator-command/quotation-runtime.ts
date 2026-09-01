import type { EmailDeliveryResult } from "../_shared/email-delivery.ts";
import {
  createQuotationAcceptanceCapabilityToken,
  hashQuotationAcceptanceCapabilityToken,
} from "../_shared/quotation-acceptance-capability.ts";
import { encryptQuotationDeliveryToken } from "../_shared/security.ts";
import type {
  QuotationOrchestrationContext,
  QuotationOrchestrationDependencies,
} from "./quotation-orchestrator.ts";

const DOCX_CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
const SHA256 = /^[0-9a-f]{64}$/;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type RpcResult = Readonly<{
  data: unknown;
  error: Readonly<{ message: string }> | null;
}>;

type StorageResult = Readonly<{
  data: unknown;
  error: Readonly<{ message: string }> | null;
}>;

type RpcClient = Readonly<{
  rpc(name: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
}>;

export type SdfQuotationDeliveryPreparationAuthority = Readonly<{
  businessDraftId: string;
  approvalId: string;
  approvalVersion: number;
  approvalSha256: string;
  issuanceId: string;
  artifactId: string;
  artifactSha256: string;
  artifactBytes: number;
}>;

export type SdfQuotationDeliveryPreparationDependencies = Readonly<{
  client: RpcClient;
  createToken?: () => string;
  hashToken?: (token: string) => PromiseLike<string>;
  encryptToken?: (token: string, digest: string) => PromiseLike<string>;
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
  route?: "LEGACY" | "SDF";
  sdfAuthority?: Readonly<{
    businessDraftId: string;
    approvalId: string;
    approvalVersion: number;
    approvalSha256: string;
    generationContractVersion: number;
  }>;
  deliver?: Delivery;
  email?: Readonly<{ from: string; resendApiKey: string }>;
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
  client: RpcClient,
  name: string,
  args: Record<string, unknown>,
  code: string,
): Promise<unknown> {
  const result = await client.rpc(name, args);
  if (result.error) throw new Error(result.error.message);
  if (result.data === null || result.data === undefined) throw new Error(code);
  return result.data;
}

export async function prepareSdfQuotationDelivery(
  authority: SdfQuotationDeliveryPreparationAuthority,
  dependencies: SdfQuotationDeliveryPreparationDependencies,
): Promise<Readonly<Record<string, unknown>>> {
  const token = (dependencies.createToken ??
    createQuotationAcceptanceCapabilityToken)();
  const tokenDigest = await (dependencies.hashToken ??
    hashQuotationAcceptanceCapabilityToken)(token);
  const encryptedToken = await (dependencies.encryptToken ??
    encryptQuotationDeliveryToken)(token, tokenDigest);
  const data = row(await call(
    dependencies.client,
    "prepare_sdf_issued_quotation_delivery_v1",
    {
      p_business_draft_id: authority.businessDraftId,
      p_approval_id: authority.approvalId,
      p_expected_approval_version: authority.approvalVersion,
      p_expected_approval_sha256: authority.approvalSha256,
      p_issuance_id: authority.issuanceId,
      p_artifact_id: authority.artifactId,
      p_expected_artifact_sha256: authority.artifactSha256,
      p_expected_artifact_bytes: authority.artifactBytes,
      p_token_digest: tokenDigest,
      p_encrypted_token: encryptedToken,
      p_requested_expires_at: null,
    },
    "SDF_DELIVERY_PREPARATION_INVALID",
  ), "SDF_DELIVERY_PREPARATION_INVALID");
  const orchestrationId = String(data.orchestration_id || "");
  const emailJobId = String(data.email_job_id || "");
  const capabilityId = String(data.capability_id || "");
  const artifactId = String(data.artifact_id || "");
  const artifactSha256 = String(data.artifact_sha256 || "");
  const artifactBytes = Number(data.artifact_bytes);
  if (
    !UUID.test(orchestrationId) || !UUID.test(emailJobId) ||
    !UUID.test(capabilityId) || artifactId !== authority.artifactId ||
    artifactSha256 !== authority.artifactSha256 ||
    artifactBytes !== authority.artifactBytes || data.job_status !== "pending" ||
    typeof data.capability_was_created !== "boolean" ||
    typeof data.delivery_was_created !== "boolean"
  ) {
    throw new Error("SDF_DELIVERY_PREPARATION_INVALID");
  }
  return {
    delivery_preparation_status: "PREPARED",
    issuance_id: authority.issuanceId,
    artifact: {
      artifact_id: artifactId,
      artifact_sha256: artifactSha256,
      artifact_bytes: artifactBytes,
      reuse_status: "REUSED",
    },
    acceptance_capability: {
      capability_id: capabilityId,
      preparation_status: data.capability_was_created ? "PREPARED" : "REUSED",
    },
    delivery_job: {
      orchestration_id: orchestrationId,
      email_job_id: emailJobId,
      preparation_status: data.delivery_was_created ? "PREPARED" : "REUSED",
    },
    mail_delivery_status: "NOT_STARTED",
    delivery_attempted: false,
  };
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
  const route = options.route ?? "LEGACY";
  let approvedTemplateSha256: string | null = null;

  return {
    resolveContext: async (actorAuthUserId, quoteRequestId)=>{
      if (actorAuthUserId !== options.actorAuthUserId) throw new Error("QUOTATION_ORCHESTRATION_ACTOR_MISMATCH");
      if (route === "SDF") {
        if (!options.sdfAuthority) throw new Error("QUOTATION_ORCHESTRATION_CONTEXT_INVALID");
        return { route, ...options.sdfAuthority };
      }
      const data = object(await call(client, "resolve_first_customer_quotation_orchestration_v1", {
        p_actor_auth_user_id: actorAuthUserId,
        p_quote_request_id: quoteRequestId,
      }, "QUOTATION_ORCHESTRATION_CONTEXT_INVALID"), "QUOTATION_ORCHESTRATION_CONTEXT_INVALID");
      const templateData = object(data.template, "QUOTATION_ORCHESTRATION_CONTEXT_INVALID");
      const template = {
        template_id: String(templateData.template_id || ""),
        template_version: String(templateData.template_version || ""),
        template_sha256: String(templateData.template_sha256 || ""),
        authority_status: String(templateData.authority_status || "") as "APPROVED",
      };
      const templateSha256 = template.template_sha256;
      approvedTemplateSha256 = templateSha256;
      if (!SHA256.test(templateSha256)
        || await hashBytes(options.templateBytes) !== templateSha256) {
        throw new Error("QUOTATION_TEMPLATE_HASH_INVALID");
      }
      return {
        route,
        approvalId: String(data.approval_id || ""),
        adminAccessTokenHash: String(data.admin_access_token_hash || ""),
        issueYear: Number(data.issue_year),
        issuanceInputSha256: String(data.issuance_input_sha256 || ""),
        template,
        seller: object(data.seller, "QUOTATION_ORCHESTRATION_CONTEXT_INVALID"),
      };
    },
    prepareIssuance: async (context, idempotencyKey)=>{
      if (context.route === "SDF") {
        const data = row(await call(client, "prepare_sdf_quotation_issuance_v1", {
          p_business_draft_id: context.businessDraftId,
          p_approval_id: context.approvalId,
          p_expected_approval_version: context.approvalVersion,
          p_expected_approval_sha256: context.approvalSha256,
          p_generation_contract_version: context.generationContractVersion,
          p_idempotency_key: idempotencyKey,
        }, "QUOTATION_ISSUANCE_PREPARATION_INVALID"), "QUOTATION_ISSUANCE_PREPARATION_INVALID");
        return {
          issuanceId: String(data.issuance_id || ""),
          quotationNumber: String(data.quotation_number || ""),
          quotationVersion: Number(data.quotation_version),
        };
      }
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
      if (context.route === "SDF") {
        const data = row(await call(client, "build_sdf_quotation_issue_payload_v1", {
          p_business_draft_id: context.businessDraftId,
          p_approval_id: context.approvalId,
          p_expected_approval_version: context.approvalVersion,
          p_expected_approval_sha256: context.approvalSha256,
          p_issuance_id: issuance.issuanceId,
        }, "QUOTATION_ISSUE_PAYLOAD_INVALID"), "QUOTATION_ISSUE_PAYLOAD_INVALID");
        return {
          payload: object(data.payload, "QUOTATION_ISSUE_PAYLOAD_INVALID"),
          payloadSha256: String(data.payload_sha256 || ""),
        };
      }
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
      const payloadTemplate = issuePayload.payload.template;
      const expectedTemplateHash = route === "SDF"
        ? String(object(payloadTemplate, "QUOTATION_TEMPLATE_HASH_INVALID").template_sha256 || "")
        : approvedTemplateSha256;
      const observedTemplateHash = await hashBytes(options.templateBytes);
      if (!expectedTemplateHash || !SHA256.test(expectedTemplateHash)
        || !SHA256.test(observedTemplateHash) || observedTemplateHash !== expectedTemplateHash) {
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
      if (context.route === "SDF") {
        const template = object(payload.payload.template, "QUOTATION_TEMPLATE_HASH_INVALID");
        const data = row(await call(client, "commit_sdf_quotation_issuance_v1", {
          p_business_draft_id: context.businessDraftId,
          p_approval_id: context.approvalId,
          p_expected_approval_version: context.approvalVersion,
          p_expected_approval_sha256: context.approvalSha256,
          p_issuance_id: issuance.issuanceId,
          p_commit_idempotency_key: idempotencyKey,
          p_generation_payload_sha256: payload.payloadSha256,
          p_template_id: String(template.template_id || ""),
          p_template_version: String(template.template_version || ""),
          p_template_sha256: String(template.template_sha256 || ""),
          p_generation_contract_version: context.generationContractVersion,
          p_docx_sha256: artifact.sha256,
          p_docx_bytes: artifact.bytes,
          p_pdf_sha256: null,
          p_pdf_bytes: null,
        }, "QUOTATION_ARTIFACT_COMMIT_INVALID"), "QUOTATION_ARTIFACT_COMMIT_INVALID");
        return { status: String(data.status) as "ISSUED", issuedAt: String(data.issued_at || "") };
      }
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
    deliverIssuance: route === "LEGACY" ? async (context, issuance, idempotencyKeys)=>{
      if (context.route === "SDF" || !options.deliver || !options.email) {
        throw new Error("QUOTATION_DELIVERY_DEPENDENCY_MISSING");
      }
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
    } : undefined,
  };
}