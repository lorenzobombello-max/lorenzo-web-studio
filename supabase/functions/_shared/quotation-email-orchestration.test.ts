import { assertEquals } from "jsr:@std/assert@1";
import { sendPreparedSdfQuotationDelivery } from "./quotation-email-orchestration.ts";

const authority = {
  businessDraftId: "a1800000-0000-4000-8000-000000000001",
  approvalId: "a1800000-0000-4000-8000-000000000002",
  approvalVersion: 3,
  approvalSha256: "a".repeat(64),
  issuanceId: "a1800000-0000-4000-8000-000000000003",
  artifactId: "a1800000-0000-4000-8000-000000000004",
  artifactSha256: "b".repeat(64),
  artifactBytes: 4096,
};

const context = {
  issuance_id: authority.issuanceId,
  capability_id: "a1800000-0000-4000-8000-000000000005",
  orchestration_id: "a1800000-0000-4000-8000-000000000006",
  email_job_id: "a1800000-0000-4000-8000-000000000007",
  recipient_email: "customer@example.test",
  content_version: "QUOTATION_DELIVERY_NL_BE_v1",
  client_name: "Example BV",
  quotation_number: "LWS-OFF-2099-0001",
  quotation_version: 3,
  project_title: "Frozen project",
  valid_until: "2099-12-31",
  stored_token_digest: "c".repeat(64),
  encrypted_token: "v1.prepared-token",
  job_status: "pending",
  artifact_id: authority.artifactId,
  artifact_sha256: authority.artifactSha256,
  artifact_bytes: authority.artifactBytes,
};

Deno.test("prepared SDF delivery uses one owner bridge then the existing transport boundary", async () => {
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const transportCalls: Array<Record<string, unknown>> = [];
  const result = await sendPreparedSdfQuotationDelivery({
    authorityClient: {
      rpc: (name: string, args: Record<string, unknown>) => {
        rpcCalls.push({ name, args });
        return Promise.resolve({ data: [context], error: null });
      },
    },
    transportClient: {} as never,
    authority,
    from: "quotation@example.test",
    resendApiKey: "provider-secret",
  }, {
    decryptToken: (encryptedToken, tokenDigest) => {
      assertEquals(encryptedToken, context.encrypted_token);
      assertEquals(tokenDigest, context.stored_token_digest);
      return Promise.resolve("d".repeat(43));
    },
    buildAcceptanceUrl: (rawToken) => {
      assertEquals(rawToken, "d".repeat(43));
      return "https://example.test/pages/quotation-acceptance.html#token=prepared";
    },
    buildEmail: (template, data) => {
      assertEquals(template, "QUOTATION_DELIVERY_NL_BE_v1");
      assertEquals(data, {
        clientName: context.client_name,
        quotationNumber: context.quotation_number,
        quotationVersion: context.quotation_version,
        projectTitle: context.project_title,
        validUntil: context.valid_until,
        acceptanceUrl: "https://example.test/pages/quotation-acceptance.html#token=prepared",
      });
      return { subject: "Offerte", html: "<p>Offerte</p>", text: "Offerte" };
    },
    deliverEmailJob: (options) => {
      transportCalls.push(options as unknown as Record<string, unknown>);
      return Promise.resolve({ status: "sent", attempted: true, attemptCount: 1 });
    },
  });

  assertEquals(rpcCalls, [{
    name: "get_sdf_quotation_delivery_transport_context_v1",
    args: {
      p_business_draft_id: authority.businessDraftId,
      p_approval_id: authority.approvalId,
      p_expected_approval_version: authority.approvalVersion,
      p_expected_approval_sha256: authority.approvalSha256,
      p_issuance_id: authority.issuanceId,
      p_artifact_id: authority.artifactId,
      p_expected_artifact_sha256: authority.artifactSha256,
      p_expected_artifact_bytes: authority.artifactBytes,
    },
  }]);
  assertEquals(transportCalls, [{
    supabase: {},
    jobId: context.email_job_id,
    resendApiKey: "provider-secret",
    email: {
      from: "quotation@example.test",
      to: context.recipient_email,
      subject: "Offerte",
      html: "<p>Offerte</p>",
      text: "Offerte",
    },
  }]);
  assertEquals(result, {
    delivery_status: "sent",
    email_job_id: context.email_job_id,
    attempt_count: 1,
    delivery_attempted: true,
  });
  assertEquals(JSON.stringify(result).includes("token"), false);
  assertEquals(JSON.stringify(result).includes("secret"), false);
});

Deno.test("prepared SDF delivery preserves retry and terminal transport results", async () => {
  for (const delivery of [
    { status: "retry_wait" as const, attempted: true, attemptCount: 2, errorCode: "RESEND_HTTP_500" },
    { status: "failed" as const, attempted: true, attemptCount: 5, errorCode: "RESEND_HTTP_400" },
  ]) {
    const result = await sendPreparedSdfQuotationDelivery({
      authorityClient: {
        rpc: () => Promise.resolve({ data: [context], error: null }),
      },
      transportClient: {} as never,
      authority,
      from: "quotation@example.test",
      resendApiKey: "provider-secret",
    }, {
      decryptToken: () => Promise.resolve("d".repeat(43)),
      buildAcceptanceUrl: () => "https://example.test/#token=prepared",
      buildEmail: () => ({ subject: "Offerte", html: "<p>Offerte</p>", text: "Offerte" }),
      deliverEmailJob: () => Promise.resolve(delivery),
    });
    assertEquals(result, {
      delivery_status: delivery.status,
      email_job_id: context.email_job_id,
      attempt_count: delivery.attemptCount,
      delivery_attempted: true,
      error_code: delivery.errorCode,
    });
  }
});