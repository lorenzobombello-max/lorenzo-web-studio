import type { EmailDeliveryResult } from "../_shared/email-delivery.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/;

export type QuotationOrchestrationInput = Readonly<{
  actorAuthUserId: string;
  quoteRequestId: string;
}>;

type LegacyQuotationOrchestrationContext = Readonly<{
  route?: "LEGACY";
  approvalId: string;
  adminAccessTokenHash: string;
  issueYear: number;
  issuanceInputSha256: string;
  template: Readonly<{
    template_id: string;
    template_version: string;
    template_sha256: string;
    authority_status: "APPROVED";
  }>;
  seller: Record<string, unknown>;
}>;

type SdfQuotationOrchestrationContext = Readonly<{
  route: "SDF";
  businessDraftId: string;
  approvalId: string;
  approvalVersion: number;
  approvalSha256: string;
  generationContractVersion: number;
}>;

export type QuotationOrchestrationContext =
  | LegacyQuotationOrchestrationContext
  | SdfQuotationOrchestrationContext;

type PreparedIssuance = Readonly<{
  issuanceId: string;
  quotationNumber: string;
  quotationVersion: number;
}>;

type IssuePayload = Readonly<{
  payload: Record<string, unknown>;
  payloadSha256: string;
}>;

type RenderedDocx = Readonly<{
  bytes: Uint8Array;
  sha256: string;
}>;

type CommittedIssuance = Readonly<{
  status: "ISSUED";
  issuedAt: string;
}>;

export type QuotationOrchestrationDependencies = Readonly<{
  resolveContext(actorAuthUserId: string, quoteRequestId: string): PromiseLike<QuotationOrchestrationContext>;
  prepareIssuance(context: QuotationOrchestrationContext, idempotencyKey: string): PromiseLike<PreparedIssuance>;
  buildIssuePayload(context: QuotationOrchestrationContext, issuance: PreparedIssuance): PromiseLike<IssuePayload>;
  renderDocx(payload: IssuePayload): PromiseLike<RenderedDocx>;
  sha256(bytes: Uint8Array): PromiseLike<string>;
  commitIssuance(
    context: QuotationOrchestrationContext,
    issuance: PreparedIssuance,
    payload: IssuePayload,
    artifact: Readonly<{ sha256: string; bytes: number }>,
    idempotencyKey: string,
  ): PromiseLike<CommittedIssuance>;
  archiveArtifact(
    issuance: PreparedIssuance,
    artifact: RenderedDocx,
    idempotencyKey: string,
  ): PromiseLike<Readonly<{ status: "ARCHIVED" }>>;
  deliverIssuance?(
    context: QuotationOrchestrationContext,
    issuance: PreparedIssuance,
    idempotencyKeys: Readonly<{ capability: string; delivery: string }>,
  ): PromiseLike<EmailDeliveryResult>;
}>;

async function deterministicUuid(namespace: string, label: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${namespace}:${label}`),
  ));
  digest[6] = (digest[6] & 0x0f) | 0x50;
  digest[8] = (digest[8] & 0x3f) | 0x80;
  const hex = [...digest.slice(0, 16)].map((byte)=>byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function validateContext(context: QuotationOrchestrationContext): void {
  if (!UUID.test(context.approvalId)) {
    throw new Error("QUOTATION_ORCHESTRATION_CONTEXT_INVALID");
  }
  if (context.route === "SDF") {
    if (!UUID.test(context.businessDraftId)
      || !Number.isSafeInteger(context.approvalVersion) || context.approvalVersion < 1
      || !SHA256.test(context.approvalSha256)
      || context.generationContractVersion !== 1) {
      throw new Error("QUOTATION_ORCHESTRATION_CONTEXT_INVALID");
    }
    return;
  }
  if (!SHA256.test(context.adminAccessTokenHash)
    || !Number.isSafeInteger(context.issueYear) || context.issueYear < 2000 || context.issueYear > 9999
    || !SHA256.test(context.issuanceInputSha256)
    || context.template.authority_status !== "APPROVED"
    || !context.template.template_id || !context.template.template_version
    || !SHA256.test(context.template.template_sha256)
    || !context.seller || typeof context.seller !== "object" || Array.isArray(context.seller)) {
    throw new Error("QUOTATION_ORCHESTRATION_CONTEXT_INVALID");
  }
}

export async function orchestrateApprovedQuotation(
  input: QuotationOrchestrationInput,
  dependencies: QuotationOrchestrationDependencies,
): Promise<Record<string, unknown>> {
  if (!UUID.test(input.actorAuthUserId) || !UUID.test(input.quoteRequestId)) {
    throw new Error("QUOTATION_ORCHESTRATION_INPUT_INVALID");
  }
  const context = await dependencies.resolveContext(input.actorAuthUserId, input.quoteRequestId);
  validateContext(context);
  const operationAuthority = context.route === "SDF"
    ? [context.businessDraftId, context.approvalId, context.approvalVersion,
      context.approvalSha256, context.generationContractVersion].join(":")
    : context.approvalId;
  const prepareKey = await deterministicUuid(operationAuthority, "quotation-prepare-v1");
  const commitKey = await deterministicUuid(operationAuthority, "quotation-commit-v1");
  const artifactKey = await deterministicUuid(operationAuthority, "quotation-artifact-v1");

  const issuance = await dependencies.prepareIssuance(context, prepareKey);
  if (!UUID.test(issuance.issuanceId)
    || !/^LWS-OFF-[0-9]{4}-[0-9]{4}$/.test(issuance.quotationNumber)
    || !Number.isSafeInteger(issuance.quotationVersion) || issuance.quotationVersion < 1) {
    throw new Error("QUOTATION_ISSUANCE_PREPARATION_INVALID");
  }
  const payload = await dependencies.buildIssuePayload(context, issuance);
  if (!payload.payload || typeof payload.payload !== "object" || Array.isArray(payload.payload)
    || payload.payload.mode !== "ISSUE" || !SHA256.test(payload.payloadSha256)) {
    throw new Error("QUOTATION_ISSUE_PAYLOAD_INVALID");
  }
  const rendered = await dependencies.renderDocx(payload);
  if (!(rendered.bytes instanceof Uint8Array) || rendered.bytes.byteLength < 1 || !SHA256.test(rendered.sha256)) {
    throw new Error("QUOTATION_RENDER_INVALID");
  }
  const computedArtifactHash = await dependencies.sha256(rendered.bytes);
  if (!SHA256.test(computedArtifactHash) || computedArtifactHash !== rendered.sha256) {
    throw new Error("QUOTATION_ARTIFACT_HASH_MISMATCH");
  }
  const committed = await dependencies.commitIssuance(
    context,
    issuance,
    payload,
    { sha256: rendered.sha256, bytes: rendered.bytes.byteLength },
    commitKey,
  );
  if (committed.status !== "ISSUED" || typeof committed.issuedAt !== "string" || !committed.issuedAt) {
    throw new Error("QUOTATION_ARTIFACT_COMMIT_INVALID");
  }
  const archived = await dependencies.archiveArtifact(issuance, rendered, artifactKey);
  if (archived.status !== "ARCHIVED") throw new Error("QUOTATION_ARTIFACT_ARCHIVE_INVALID");
  if (context.route === "SDF") {
    return {
      issuance_id: issuance.issuanceId,
      quotation_number: issuance.quotationNumber,
      quotation_version: issuance.quotationVersion,
      issuance_status: committed.status,
      issued_at: committed.issuedAt,
      artifact_status: archived.status,
      delivery_status: "NOT_STARTED",
      delivery_attempted: false,
    };
  }
  if (!dependencies.deliverIssuance) throw new Error("QUOTATION_DELIVERY_DEPENDENCY_MISSING");
  const capabilityKey = await deterministicUuid(context.approvalId, "quotation-capability-v1");
  const deliveryKey = await deterministicUuid(context.approvalId, "quotation-delivery-v1");
  const delivery = await dependencies.deliverIssuance(context, issuance, {
    capability: capabilityKey,
    delivery: deliveryKey,
  });

  return {
    issuance_id: issuance.issuanceId,
    quotation_number: issuance.quotationNumber,
    quotation_version: issuance.quotationVersion,
    issuance_status: committed.status,
    issued_at: committed.issuedAt,
    artifact_status: archived.status,
    delivery_status: delivery.status,
    delivery_attempted: delivery.attempted,
  };
}