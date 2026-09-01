import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { orchestrateApprovedQuotation } from "./quotation-orchestrator.ts";
import { createQuotationRuntimeDependencies } from "./quotation-runtime.ts";

const actorAuthUserId = "a1800000-0000-4000-8000-000000000001";
const quoteRequestId = "a1800000-0000-4000-8000-000000000002";
const approvalId = "a1800000-0000-4000-8000-000000000003";
const issuanceId = "a1800000-0000-4000-8000-000000000004";
const adminAccessTokenHash = "a".repeat(64);
const issuanceInputSha256 = "b".repeat(64);
const generationPayloadSha256 = "c".repeat(64);

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes).buffer));
  return [...digest].map((byte)=>byte.toString(16).padStart(2, "0")).join("");
}

Deno.test("quotation runtime binds approved authority through archive before delivery", async ()=>{
  const templateBytes = new Uint8Array([1, 2, 3]);
  const templateSha256 = await sha256(templateBytes);
  const renderedBytes = new Uint8Array([4, 5, 6, 7]);
  const renderedSha256 = await sha256(renderedBytes);
  const events: string[] = [];
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const uploads: Array<{ bucket: string; path: string; bytes: Uint8Array; options: Record<string, unknown> }> = [];
  let uploadAttempts = 0;
  const serviceClient = {
    rpc: async (name: string, args: Record<string, unknown>)=>{
      events.push(name);
      rpcCalls.push({ name, args });
      if (name === "resolve_first_customer_quotation_orchestration_v1") return { data: {
        approval_id: approvalId,
        admin_access_token_hash: adminAccessTokenHash,
        issue_year: 2099,
        issuance_input_sha256: issuanceInputSha256,
        template: {
          template_id: "LWS_QUOTATION_NL_BE",
          template_version: "1.0.0-technical",
          template_sha256: templateSha256,
          authority_status: "APPROVED",
          technical_master_filename: "assets/docs/quotation/LWS_QUOTATION_NL_BE_TECHNICAL_v1.docx",
          renderer_version: "quotation-docx-v1",
        },
        seller: { legal_name: "Lorenzo Web Solutions" },
      }, error: null };
      if (name === "prepare_quotation_issuance_v2") return { data: [{
        issuance_id: issuanceId,
        quotation_number: "LWS-OFF-2099-0001",
        quotation_version: 1,
      }], error: null };
      if (name === "build_quotation_issue_payload_v1") return { data: [{
        payload: { mode: "ISSUE", contract_version: 1 },
        payload_sha256: generationPayloadSha256,
      }], error: null };
      if (name === "commit_quotation_issuance_v2") return { data: [{
        status: "ISSUED",
        issued_at: "2099-01-01T00:00:00Z",
      }], error: null };
      if (name === "register_quotation_artifact_v1") return { data: [{
        storage_object_path: `issuances/${issuanceId}/docx/${renderedSha256}.docx`,
      }], error: null };
      throw new Error(`UNEXPECTED_RPC:${name}`);
    },
    storage: {
      from: (bucket: string)=>({
        upload: async (path: string, bytes: Uint8Array, options: Record<string, unknown>)=>{
          events.push("storage.upload");
          uploads.push({ bucket, path, bytes, options });
          uploadAttempts += 1;
          return uploadAttempts === 1
            ? { data: { path }, error: null }
            : { data: null, error: new Error("OBJECT_ALREADY_EXISTS") };
        },
        download: async (_path: string)=>{
          events.push("storage.download");
          return { data: new Blob([renderedBytes]), error: null };
        },
      }),
    },
  };
  const dependencies = createQuotationRuntimeDependencies({
    actorAuthUserId,
    serviceClient,
    templateBytes,
    renderDocx: ({ templateBytes: observedTemplate, rendererPackage })=>{
      events.push("render");
      assertEquals(observedTemplate, templateBytes);
      assertEquals(rendererPackage, {
        generation_payload: { mode: "ISSUE", contract_version: 1 },
        display_markers: null,
      });
      return { buffer: renderedBytes, sha256: renderedSha256 };
    },
    deliver: async (input)=>{
      events.push("deliver");
      assertEquals(input.issuanceId, issuanceId);
      assertEquals(input.adminAccessTokenHash, adminAccessTokenHash);
      assertEquals(input.createdBy, `operator:${actorAuthUserId}`);
      return { status: "sent", attempted: true, attemptCount: 1 };
    },
    email: { from: "LWS <offertes@example.test>", resendApiKey: "test-key" },
  });

  const result = await orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, dependencies);

  assertEquals(events, [
    "resolve_first_customer_quotation_orchestration_v1",
    "prepare_quotation_issuance_v2",
    "build_quotation_issue_payload_v1",
    "render",
    "commit_quotation_issuance_v2",
    "storage.upload",
    "register_quotation_artifact_v1",
    "deliver",
  ]);
  assertEquals(uploads, [{
    bucket: "quotation-artifacts",
    path: `issuances/${issuanceId}/docx/${renderedSha256}.docx`,
    bytes: renderedBytes,
    options: {
      contentType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      upsert: false,
    },
  }]);
  assertEquals(rpcCalls[0].args, {
    p_actor_auth_user_id: actorAuthUserId,
    p_quote_request_id: quoteRequestId,
  });
  assertEquals(rpcCalls[2].args.p_template, {
    template_id: "LWS_QUOTATION_NL_BE",
    template_version: "1.0.0-technical",
    template_sha256: templateSha256,
    authority_status: "APPROVED",
  });
  assertEquals(result, {
    issuance_id: issuanceId,
    quotation_number: "LWS-OFF-2099-0001",
    quotation_version: 1,
    issuance_status: "ISSUED",
    issued_at: "2099-01-01T00:00:00Z",
    artifact_status: "ARCHIVED",
    delivery_status: "sent",
    delivery_attempted: true,
  });

  const replay = await orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, dependencies);
  assertEquals(replay.artifact_status, "ARCHIVED");
  assertEquals(events.slice(-9), [
    "resolve_first_customer_quotation_orchestration_v1",
    "prepare_quotation_issuance_v2",
    "build_quotation_issue_payload_v1",
    "render",
    "commit_quotation_issuance_v2",
    "storage.upload",
    "storage.download",
    "register_quotation_artifact_v1",
    "deliver",
  ]);
});

Deno.test("template mismatch fails before issuance preparation", async ()=>{
  const rpcNames: string[] = [];
  const serviceClient = {
    rpc: async (name: string, _args: Record<string, unknown>)=>{
      rpcNames.push(name);
      return { data: {
        approval_id: approvalId,
        admin_access_token_hash: adminAccessTokenHash,
        issue_year: 2099,
        issuance_input_sha256: issuanceInputSha256,
        template: {
          template_id: "LWS_QUOTATION_NL_BE",
          template_version: "1.0.0-technical",
          template_sha256: "f".repeat(64),
          authority_status: "APPROVED",
        },
        seller: { legal_name: "Lorenzo Web Solutions" },
      }, error: null };
    },
    storage: { from: (_bucket: string)=>({
      upload: async (_path: string, _bytes: Uint8Array, _options: Record<string, unknown>)=>({ data: null, error: null }),
      download: async (_path: string)=>({ data: null, error: null }),
    }) },
  };
  const dependencies = createQuotationRuntimeDependencies({
    actorAuthUserId,
    serviceClient,
    templateBytes: new Uint8Array([1, 2, 3]),
    renderDocx: ()=>{ throw new Error("UNEXPECTED_RENDER"); },
    deliver: async ()=>({ status: "sent", attempted: true, attemptCount: 1 }),
    email: { from: "LWS <offertes@example.test>", resendApiKey: "test-key" },
  });

  await assertRejects(
    ()=>orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, dependencies),
    Error,
    "QUOTATION_TEMPLATE_HASH_INVALID",
  );
  assertEquals(rpcNames, ["resolve_first_customer_quotation_orchestration_v1"]);
});

Deno.test("SDF runtime uses frozen authority RPCs then shared render and archive without delivery", async ()=>{
  const templateBytes = new Uint8Array([9, 8, 7]);
  const templateSha256 = await sha256(templateBytes);
  const renderedBytes = new Uint8Array([6, 5, 4]);
  const renderedSha256 = await sha256(renderedBytes);
  const businessDraftId = "a1800000-0000-4000-8000-000000000005";
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const events: string[] = [];
  const serviceClient = {
    rpc: async (name: string, args: Record<string, unknown>)=>{
      events.push(name);
      rpcCalls.push({ name, args });
      if (name === "prepare_sdf_quotation_issuance_v1") return { data: [{
        issuance_id: issuanceId,
        quotation_number: "LWS-OFF-2099-0002",
        quotation_version: 1,
      }], error: null };
      if (name === "build_sdf_quotation_issue_payload_v1") return { data: [{
        payload: {
          mode: "ISSUE",
          template: {
            template_id: "LWS_QUOTATION_NL_BE",
            template_version: "1.0.0-technical",
            template_sha256: templateSha256,
          },
        },
        payload_sha256: generationPayloadSha256,
      }], error: null };
      if (name === "commit_sdf_quotation_issuance_v1") return { data: [{
        status: "ISSUED",
        issued_at: "2099-01-01T00:00:00Z",
      }], error: null };
      if (name === "register_quotation_artifact_v1") return { data: [{
        storage_object_path: `issuances/${issuanceId}/docx/${renderedSha256}.docx`,
      }], error: null };
      throw new Error(`UNEXPECTED_RPC:${name}`);
    },
    storage: { from: (_bucket: string)=>({
      upload: async (_path: string, _bytes: Uint8Array, _options: Record<string, unknown>)=>{
        events.push("storage.upload");
        return { data: {}, error: null };
      },
      download: async (_path: string)=>({ data: null, error: null }),
    }) },
  };
  const dependencies = createQuotationRuntimeDependencies({
    actorAuthUserId,
    serviceClient,
    route: "SDF",
    sdfAuthority: {
      businessDraftId,
      approvalId,
      approvalVersion: 3,
      approvalSha256: "d".repeat(64),
      generationContractVersion: 1,
    },
    templateBytes,
    renderDocx: ({ templateBytes: observedTemplate, rendererPackage })=>{
      events.push("render");
      assertEquals(observedTemplate, templateBytes);
      assertEquals(rendererPackage.generation_payload.mode, "ISSUE");
      return { buffer: renderedBytes, sha256: renderedSha256 };
    },
  });

  const result = await orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, dependencies);
  assertEquals(events, [
    "prepare_sdf_quotation_issuance_v1",
    "build_sdf_quotation_issue_payload_v1",
    "render",
    "commit_sdf_quotation_issuance_v1",
    "storage.upload",
    "register_quotation_artifact_v1",
  ]);
  assertEquals(rpcCalls[0].args.p_business_draft_id, businessDraftId);
  assertEquals(rpcCalls[1].args.p_issuance_id, issuanceId);
  assertEquals(rpcCalls[2].args.p_docx_sha256, renderedSha256);
  assertEquals(rpcCalls.some(({ args })=>"p_admin_access_token" in args), false);
  assertEquals(result.delivery_status, "NOT_STARTED");
  assertEquals(result.delivery_attempted, false);
});