import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  orchestrateApprovedQuotation,
  type QuotationOrchestrationDependencies,
} from "./quotation-orchestrator.ts";

const actorAuthUserId = "a1000000-0000-4000-8000-000000000001";
const quoteRequestId = "a2000000-0000-4000-8000-000000000001";
const approvalId = "a3000000-0000-4000-8000-000000000001";
const issuanceId = "a4000000-0000-4000-8000-000000000001";
const hash = "a".repeat(64);
const validContext = {
  approvalId,
  adminAccessTokenHash: "f".repeat(64),
  issueYear: 2099,
  issuanceInputSha256: "1".repeat(64),
  template: {
    template_id: "LWS_QUOTATION_NL_BE",
    template_version: "1.0.0-technical",
    template_sha256: "3ad2faaaa6a0a06e566f462e1c65c631006019c0d2d462333b8c693eb11154de",
    authority_status: "APPROVED" as const,
  },
  seller: { legal_name: "Lorenzo Web Solutions" },
};

function dependencies(
  events: string[],
  overrides: Partial<QuotationOrchestrationDependencies> = {},
): QuotationOrchestrationDependencies {
  return {
    resolveContext: async ()=>{
      events.push("resolve");
      return validContext;
    },
    prepareIssuance: async (_context, key)=>{
      events.push(`prepare:${key}`);
      return { issuanceId, quotationNumber: "LWS-OFF-2099-0001", quotationVersion: 1 };
    },
    buildIssuePayload: async ()=>{
      events.push("payload");
      return { payload: { mode: "ISSUE" }, payloadSha256: "2".repeat(64) };
    },
    renderDocx: async ()=>{
      events.push("render");
      return { bytes: new TextEncoder().encode("approved quotation"), sha256: hash };
    },
    sha256: async ()=>hash,
    commitIssuance: async (_context, _issuance, _payload, _artifact, key)=>{
      events.push(`commit:${key}`);
      return { status: "ISSUED", issuedAt: "2099-01-01T00:00:00Z" };
    },
    archiveArtifact: async (_issuance, _artifact, key)=>{
      events.push(`artifact:${key}`);
      return { status: "ARCHIVED" };
    },
    deliverIssuance: async (_context, _issuance, keys)=>{
      events.push(`delivery:${keys.capability}:${keys.delivery}`);
      return { status: "sent", attempted: true, attemptCount: 1 };
    },
    ...overrides,
  };
}

Deno.test("approved quotation completes the governed orchestration exactly once in order", async ()=>{
  const events: string[] = [];
  const result = await orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, {
    resolveContext: async ()=>{
      events.push("resolve");
      return {
        approvalId,
        adminAccessTokenHash: "f".repeat(64),
        issueYear: 2099,
        issuanceInputSha256: "1".repeat(64),
        template: {
          template_id: "LWS_QUOTATION_NL_BE",
          template_version: "1.0.0-technical",
          template_sha256: "3ad2faaaa6a0a06e566f462e1c65c631006019c0d2d462333b8c693eb11154de",
          authority_status: "APPROVED",
        },
        seller: { legal_name: "Lorenzo Web Solutions" },
      };
    },
    prepareIssuance: async ()=>{
      events.push("prepare");
      return { issuanceId, quotationNumber: "LWS-OFF-2099-0001", quotationVersion: 1 };
    },
    buildIssuePayload: async ()=>{
      events.push("payload");
      return { payload: { mode: "ISSUE" }, payloadSha256: "2".repeat(64) };
    },
    renderDocx: async ()=>{
      events.push("render");
      return { bytes: new TextEncoder().encode("approved quotation"), sha256: hash };
    },
    sha256: async ()=>hash,
    commitIssuance: async ()=>{
      events.push("commit");
      return { status: "ISSUED" as const, issuedAt: "2099-01-01T00:00:00Z" };
    },
    archiveArtifact: async ()=>{
      events.push("artifact");
      return { status: "ARCHIVED" as const };
    },
    deliverIssuance: async ()=>{
      events.push("delivery");
      return { status: "sent" as const, attempted: true, attemptCount: 1 };
    },
  });

  assertEquals(events, ["resolve", "prepare", "payload", "render", "commit", "artifact", "delivery"]);
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
});

Deno.test("stale or invalid approval stops before issuance", async ()=>{
  for (const code of ["APPROVAL_NOT_FOUND", "APPROVAL_INTEGRITY_INVALID"]) {
    const events: string[] = [];
    await assertRejects(
      ()=>orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, dependencies(events, {
        resolveContext: async ()=>{
          events.push("resolve");
          throw new Error(code);
        },
      })),
      Error,
      code,
    );
    assertEquals(events, ["resolve"]);
  }
});

Deno.test("pricing terms or VAT conflict stops before rendering", async ()=>{
  for (const code of ["PRICING_INTEGRITY_INVALID", "TERMS_BINDING_CONFLICT", "VAT_BINDING_REQUIRED"]) {
    const events: string[] = [];
    await assertRejects(
      ()=>orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, dependencies(events, {
        prepareIssuance: async ()=>{
          events.push("prepare");
          throw new Error(code);
        },
      })),
      Error,
      code,
    );
    assertEquals(events, ["resolve", "prepare"]);
  }
});

Deno.test("render failure cannot commit or deliver", async ()=>{
  const events: string[] = [];
  await assertRejects(
    ()=>orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, dependencies(events, {
      renderDocx: async ()=>{
        events.push("render");
        throw new Error("QUOTATION_RENDER_FAILED");
      },
    })),
    Error,
    "QUOTATION_RENDER_FAILED",
  );
  assertEquals(events.map((event)=>event.split(":", 1)[0]), ["resolve", "prepare", "payload", "render"]);
});

Deno.test("artifact hash or commit failure cannot deliver", async ()=>{
  const hashEvents: string[] = [];
  await assertRejects(
    ()=>orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, dependencies(hashEvents, {
      sha256: async ()=>"b".repeat(64),
    })),
    Error,
    "QUOTATION_ARTIFACT_HASH_MISMATCH",
  );
  assertEquals(hashEvents.map((event)=>event.split(":", 1)[0]), ["resolve", "prepare", "payload", "render"]);

  const commitEvents: string[] = [];
  await assertRejects(
    ()=>orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, dependencies(commitEvents, {
      commitIssuance: async ()=>{
        commitEvents.push("commit");
        throw new Error("ARTIFACT_COMMIT_FAILED");
      },
    })),
    Error,
    "ARTIFACT_COMMIT_FAILED",
  );
  assertEquals(commitEvents.map((event)=>event.split(":", 1)[0]), ["resolve", "prepare", "payload", "render", "commit"]);

  const archiveEvents: string[] = [];
  await assertRejects(
    ()=>orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, dependencies(archiveEvents, {
      archiveArtifact: async ()=>{
        archiveEvents.push("artifact");
        throw new Error("ARTIFACT_ARCHIVE_FAILED");
      },
    })),
    Error,
    "ARTIFACT_ARCHIVE_FAILED",
  );
  assertEquals(
    archiveEvents.map((event)=>event.split(":", 1)[0]),
    ["resolve", "prepare", "payload", "render", "commit", "artifact"],
  );
});

Deno.test("retry reuses one issuance and stable commit and delivery identities", async ()=>{
  const events: string[] = [];
  const seenIssuances = new Set<string>();
  const seenKeys = {
    prepare: new Set<string>(), commit: new Set<string>(), artifact: new Set<string>(), delivery: new Set<string>(),
  };
  const deps = dependencies(events, {
    prepareIssuance: async (_context, key)=>{
      seenKeys.prepare.add(key);
      seenIssuances.add(issuanceId);
      return { issuanceId, quotationNumber: "LWS-OFF-2099-0001", quotationVersion: 1 };
    },
    commitIssuance: async (_context, _issuance, _payload, _artifact, key)=>{
      seenKeys.commit.add(key);
      return { status: "ISSUED", issuedAt: "2099-01-01T00:00:00Z" };
    },
    archiveArtifact: async (_issuance, _artifact, key)=>{
      seenKeys.artifact.add(key);
      return { status: "ARCHIVED" };
    },
    deliverIssuance: async (_context, _issuance, keys)=>{
      seenKeys.delivery.add(`${keys.capability}:${keys.delivery}`);
      return { status: "sent", attempted: seenKeys.delivery.size === 1, attemptCount: 1 };
    },
  });
  const first = await orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, deps);
  const replay = await orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, deps);
  assertEquals(replay.quotation_number, first.quotation_number);
  assertEquals(seenIssuances.size, 1);
  assertEquals(seenKeys.prepare.size, 1);
  assertEquals(seenKeys.commit.size, 1);
  assertEquals(seenKeys.artifact.size, 1);
  assertEquals(seenKeys.delivery.size, 1);
});

Deno.test("mail provider failure is returned without false SENT state", async ()=>{
  const result = await orchestrateApprovedQuotation(
    { actorAuthUserId, quoteRequestId },
    dependencies([], {
      deliverIssuance: async ()=>({
        status: "retry_wait",
        attempted: true,
        attemptCount: 1,
        errorCode: "RESEND_HTTP_503",
      }),
    }),
  );
  assertEquals(result.issuance_status, "ISSUED");
  assertEquals(result.delivery_status, "retry_wait");
  assertEquals(result.delivery_attempted, true);
});

Deno.test("SDF quotation archives with stable frozen-authority keys and never enters delivery", async ()=>{
  const events: string[] = [];
  const keys = { prepare: new Set<string>(), commit: new Set<string>(), artifact: new Set<string>() };
  const sdfContext = {
    route: "SDF" as const,
    businessDraftId: "a5000000-0000-4000-8000-000000000001",
    approvalId,
    approvalVersion: 3,
    approvalSha256: "5".repeat(64),
    generationContractVersion: 1,
  };
  const deps = dependencies(events, {
    resolveContext: async ()=>sdfContext,
    prepareIssuance: async (_context, key)=>{
      keys.prepare.add(key);
      return { issuanceId, quotationNumber: "LWS-OFF-2099-0001", quotationVersion: 1 };
    },
    commitIssuance: async (_context, _issuance, _payload, _artifact, key)=>{
      keys.commit.add(key);
      return { status: "ISSUED", issuedAt: "2099-01-01T00:00:00Z" };
    },
    archiveArtifact: async (_issuance, _artifact, key)=>{
      keys.artifact.add(key);
      return { status: "ARCHIVED" };
    },
    deliverIssuance: undefined,
  });

  const first = await orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, deps);
  const replay = await orchestrateApprovedQuotation({ actorAuthUserId, quoteRequestId }, deps);
  assertEquals(first, replay);
  assertEquals(first.delivery_status, "NOT_STARTED");
  assertEquals(first.delivery_attempted, false);
  assertEquals(keys.prepare.size, 1);
  assertEquals(keys.commit.size, 1);
  assertEquals(keys.artifact.size, 1);
});