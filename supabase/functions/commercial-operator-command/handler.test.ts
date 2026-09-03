import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  createUnsignedTestJwt,
  executeAssignmentOperatorRosterTransport,
  executeCurrentOperatorIdentityTransport,
  executeCustomerRequestTransport,
  executeDossierAssignmentMutationTransport,
  executeDossierAssignmentReadTransport,
  executeDossierDocumentAccessTransport,
  executeDossierDocumentManifestTransport,
  executeDossierLifecycleTransport,
  executeOperatorPersonalQueueTransport,
  executeRecruitmentVacancyTransport,
  executeSdfM1InvoicePreparationTransport,
  executeWorkforceCalendarTransport,
  handleCommercialOperator,
  withCommercialOperatorCors,
} from "./handler.ts";
import {
  OPERATOR_CURSOR_TTL_MS,
  signOperatorCursor,
  verifyOperatorCursor,
} from "../_shared/operator-cursor.ts";
import {
  executeCallerJwtAssignmentRosterAction,
  executeCallerJwtCurrentOperatorIdentityAction,
  executeCallerJwtCustomerRequestAction,
  executeCallerJwtCustomerRequestSmokeFixtureAction,
  executeCallerJwtCustomerRequestUploadAction,
  executeCallerJwtDossierAssignmentAction,
  executeCallerJwtInternalE2EAcceptedFileCleanupAction,
  executeCallerJwtOperatorPersonalQueueAction,
  executeCallerJwtRecruitmentVacancyAction,
  executeCallerJwtSdfM1InvoicePreparationAction,
  executeApplicationDetailRead,
  executeCustomerRequestUploadInboxPromotionAction,
  executeQuotationBusinessApprovalPromotionAction,
  executeQuotationBusinessDraftAction,
  executeServiceRoleDossierDocumentAction,
  executeServiceRoleWorkforceCalendarAction,
  normalizePendingSeenStateItems,
  normalizeWebsitePendingItems,
  verifySupabaseAuthUser,
} from "./index.ts";
import {
  createQuotationApprovalIntegrity,
  verifyQuotationApprovalIntegrity,
} from "../_shared/quotation-approval-integrity.ts";

const userId = "a1000000-0000-4000-8000-000000000001";
const jwt = createUnsignedTestJwt({
  sub: userId,
  role: "authenticated",
  exp: 4102444800,
});
const cursorSecret = "ERERERERERERERERERERERERERERERERERERERERERE";
const workforceEmployeeId = "a1800000-0000-4000-8000-000000000080";

function workforceCalendarResult(overrides: Record<string, unknown> = {}) {
  return {
    start_date: "2026-08-24",
    end_date: "2026-08-30",
    employees: [],
    ...overrides,
  };
}

const vacancyId = "a1800000-0000-4000-8000-000000000081";
const vacancyContent = {
  title: "Senior webontwikkelaar",
  department: "Delivery",
  location: "Antwerpen",
  employment_type: "Voltijds",
  summary: "Bouw betrouwbare webproducten.",
  description: "Je ontwikkelt en onderhoudt webproducten voor onze klanten.",
  requirements: "Ervaring met moderne webtechnologie en kwaliteitsbewaking.",
};
function recruitmentVacancy(overrides: Record<string, unknown> = {}) {
  return {
    id: vacancyId,
    ...vacancyContent,
    slug: "senior-webontwikkelaar",
    status: "DRAFT",
    published_at: null,
    closed_at: null,
    created_at: "2026-08-30T18:00:00.000Z",
    updated_at: "2026-08-30T18:00:00.000Z",
    ...overrides,
  };
}

function request(body: Record<string, unknown>, token = jwt) {
  return new Request("https://example.test", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Origin: "https://lorenzowebsolutions.be",
    },
    body: JSON.stringify(body),
  });
}

function pendingIntakeDto(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    quote_request_id: "a1800000-0000-4000-8000-000000000091",
    intake_id: "a1800000-0000-4000-8000-000000000092",
    name: "Pending prospect",
    organization: "Prospect BV",
    support_reference: "#5C19F9DD",
    email: "pending@example.test",
    phone: null,
    request_kind: "website",
    sdf_package: null,
    website_type: "Website op maat",
    invitation_created_at: "2099-01-01T10:00:00Z",
    invitation_sent_at: "2099-01-01T10:01:00Z",
    invitation_delivery_status: null,
    intake_status: "invited",
    effective_access: "ACTIVE",
    access_token_expires_at: "2099-01-08T10:00:00Z",
    lifecycle_revision: 0,
    retention_state: "ACTIVE",
    archived_at: null,
    retention_revision: 0,
    can_permanently_delete: true,
    delete_block_reason: null,
    started_at: null,
    current_reminder_cycle: 0,
    reminder_1_sent_at: null,
    reminder_2_sent_at: null,
    last_activity_at: "2099-01-01T10:01:00Z",
    dossier_state: "ACTIVE",
    dossier_revision: 0,
    ...overrides,
  };
}

Deno.test("Website pending rows normalize to the canonical cross-product DTO", async () => {
  const legacy = pendingIntakeDto({ seen_at: "2099-01-02T10:00:00Z" });
  delete legacy.sdf_package;
  delete legacy.invitation_delivery_status;
  delete legacy.last_activity_at;
  const normalized = normalizeWebsitePendingItems({ items: [legacy] });
  assertEquals(normalized, [pendingIntakeDto({
    last_activity_at: "2099-01-01T10:00:00Z",
  })]);
  const compatible = dependencies({
    executePendingIntakes: async () => ({ items: normalized }),
  });
  assertEquals(
    (await handleCommercialOperator(
      request({ action: "list_pending_intakes" }),
      compatible.deps,
    )).status,
    200,
  );

  const withoutSeenAt = pendingIntakeDto();
  delete withoutSeenAt.sdf_package;
  delete withoutSeenAt.invitation_delivery_status;
  delete withoutSeenAt.last_activity_at;
  assertEquals(normalizeWebsitePendingItems({ items: [withoutSeenAt] }), [pendingIntakeDto({
    last_activity_at: "2099-01-01T10:00:00Z",
  })]);
});

Deno.test("pending seen-state normalization strips only seen_at for Website and SDF", async () => {
  const sdfItem = pendingIntakeDto({
    request_kind: "slimme_documentenflow",
    sdf_package: "groei",
    website_type: "Slimme documentenflow - groei",
    invitation_delivery_status: "pending",
  });
  const normalizedSdf = normalizePendingSeenStateItems({
    items: [{ ...sdfItem, seen_at: "2099-01-02T10:00:00Z" }],
  });
  assertEquals(normalizedSdf, [sdfItem]);

  const normalizedUnknown = normalizePendingSeenStateItems({
    items: [{ ...sdfItem, seen_at: null, unknown_field: true }],
  });
  assertEquals(normalizedUnknown, [{ ...sdfItem, unknown_field: true }]);

  const compatible = dependencies({
    executePendingIntakes: async () => ({ items: normalizedSdf }),
  });
  assertEquals(
    (await handleCommercialOperator(
      request({ action: "list_pending_intakes" }),
      compatible.deps,
    )).status,
    200,
  );

  const strict = dependencies({
    executePendingIntakes: async () => ({ items: normalizedUnknown }),
  });
  assertEquals(
    (await handleCommercialOperator(
      request({ action: "list_pending_intakes" }),
      strict.deps,
    )).status,
    500,
  );
});

function cursorRequest(input: Record<string, unknown>) {
  return {
    zone: input.zone as "ACTIVE" | "ARCHIVED" | "TRASHED" | "ACTIVE_ARCHIVED",
    operationalStatus: input.operational_status as string | null,
    year: input.year as number | null,
    quarter: input.quarter as "Q1" | "Q2" | "Q3" | "Q4" | null,
    requestKind: input.request_kind as
      | "website"
      | "slimme_documentenflow"
      | null,
    search: input.search as string | null,
  };
}

function dependencies(overrides: Record<string, unknown> = {}) {
  const calls: Array<{ jwt: string; input: Record<string, unknown> }> = [];
  const events: string[] = [];
  return {
    calls,
    events,
    deps: {
      now: () => Date.now(),
      verifyUser: async () => ({ id: userId }),
      authorizeApplicationReader: async () => {
        events.push("preflight");
      },
      verifyOperatorCursor: async (
        cursor: string,
        input: Record<string, unknown>,
      ) => {
        events.push("verify");
        return await verifyOperatorCursor(cursor, cursorRequest(input), {
          now: 4_102_444_800_001,
          secret: cursorSecret,
        });
      },
      executeApplicationListV2: async () => {
        events.push("core");
        return {
          items: [{ quote_request_id: userId }],
          has_more: true,
          next_position: {
            dossier_date: "2099-01-02T10:20:30+00:00",
            quote_request_id: userId,
          },
        };
      },
      executePendingIntakes: async (
        _actorAuthUserId: string,
        retentionState: string,
      ) => {
        events.push("pending");
        events.push(retentionState);
        return {
          items: [pendingIntakeDto()],
        };
      },
      executePendingIntakeCount: async () => {
        events.push("pending-count");
        return { active_count: 3 };
      },
      executeDossierSubstance: async () => ({
        quote_request_id: userId,
        request_kind: "slimme_documentenflow",
        request: {
          reference: "#A1800000",
          original_text: "Exact original text",
          requested_service: "Slimme Documentenflow - groei",
          requested_at: "2099-01-01T10:00:00Z",
        },
        customer: {
          name: "Customer",
          company: null,
          email: "customer@example.test",
          phone: null,
        },
        intake: {
          intake_id: "a1800000-0000-4000-8000-000000000002",
          status: "in_progress",
          invitation_state: "ACTIVATED",
          invited_at: "2099-01-01T10:01:00Z",
          started_at: "2099-01-01T10:02:00Z",
          submitted_at: null,
          structured_answers: {
            documentPurpose: { categories: ["invoice"], otherDescription: null },
            workflowCapabilities: ["receive"],
            businessRequirements: {
              currentWorkflow: "Manual", desiredWorkflow: "Automated",
              volumeBand: null, frequency: null,
              relevantDocumentTypes: [], rolesUsers: [],
            },
            sampleDocumentMetadata: {
              available: false, requestedByLws: false, uploadRequiredLater: true,
            },
            commercialQualification: {
              packageDirection: "groei", customComplexity: null,
              documentVolumes: [], flowCount: 1, userCount: 2,
            },
          },
        },
        documents: { customer_request_count: 0, uploaded_document_count: 0 },
      }),
      signOperatorCursor: async (
        position: Record<string, string>,
        input: Record<string, unknown>,
      ) => {
        events.push("sign");
        return await signOperatorCursor(
          {
            dossierDate: position.dossier_date,
            quoteRequestId: position.quote_request_id,
          },
          cursorRequest(input),
          { now: 4_102_444_800_001, secret: cursorSecret },
        );
      },
      executeApplicationFacetsV2: async () => {
        events.push("facets");
        return { years: [] };
      },
      consumeRateLimit: async () => ({ allowed: true, retry_after_seconds: 0 }),
      executeCommand: async () => ({ command: true }),
      executeApplicationAction: async (
        token: string,
        input: Record<string, unknown>,
      ) => {
        calls.push({ jwt: token, input });
        return { action: input.action };
      },
      ...overrides,
    },
  };
}

const v2Input = {
  action: "list_applications_v2",
  zone: "ACTIVE_ARCHIVED",
  operational_status: "SUBMITTED",
  year: 2099,
  quarter: "Q1",
  request_kind: "website",
  search: "Example",
  limit: 1,
};

const quotationBusinessInput = {
  commercial_lines: [{
    rule_id: "fixed-rule",
    quantity: 1,
    description_context: "Approved scope",
  }],
  discount: {
    discount_type: null,
    discount_value_minor: 0,
    discount_reason: null,
  },
  scope: {
    project_title: "Project",
    project_type: "website",
    scope_summary: "Approved scope",
    requested_languages: ["nl"],
    included_page_count: 1,
    features: [],
    copywriting: {},
    seo: {},
    hosting: {},
    maintenance: {},
    exclusions: [],
    assumptions: [],
    indicative_timing: {},
  },
  payment_schedule: { milestones: [] },
  validity_days: null,
};

Deno.test("SDF qualification transition uses the established application action boundary", async () => {
  const harness = dependencies();
  const input = {
    action: "transition_sdf_qualification_intake",
    quote_request_id: "a1800000-0000-4000-8000-000000000091",
    transition: "request_more_information",
    reason: "Bezorg meer context over de huidige goedkeuringsstap.",
    idempotency_key: "a1800000-0000-4000-8000-000000000093",
  };
  const accepted = await handleCommercialOperator(request(input), harness.deps);
  assertEquals(accepted.status, 200);
  assertEquals(harness.calls[0].input, input);

  const rejected = await handleCommercialOperator(request({ ...input, website_type: "Website" }), harness.deps);
  assertEquals(rejected.status, 400);
});

Deno.test("removed SDF active-work acceptance action fails closed", async () => {
  const harness = dependencies();
  const input = {
    action: "accept_sdf_for_active_work_v1",
    quote_request_id: "a1800000-0000-4000-8000-000000000094",
    idempotency_key: "a1800000-0000-4000-8000-000000000095",
  };
  const rejected = await handleCommercialOperator(request(input), harness.deps);
  assertEquals(rejected.status, 400);
  assertEquals(harness.calls.length, 0);
});

const sdfM1InvoicePreparationRequest = {
  action: "prepare_sdf_m1_invoice",
  obligation_id: "a1800000-0000-4000-8000-000000000096",
  template_authority_id: "a1800000-0000-4000-8000-000000000097",
  idempotency_key: "a1800000-0000-4000-8000-000000000098",
} as const;

Deno.test("SDF M1 invoice preparation accepts only exact authority inputs", async () => {
  const harness = dependencies();
  const accepted = await handleCommercialOperator(
    request(sdfM1InvoicePreparationRequest),
    harness.deps,
  );
  assertEquals(accepted.status, 200);
  assertEquals(harness.calls[0], {
    jwt,
    input: sdfM1InvoicePreparationRequest,
  });

  for (const override of [
    { amount_minor: 1 },
    { currency: "EUR" },
    { percentage_basis_points: 4000 },
    { vat_treatment: "EXEMPT" },
    { quotation_number: "LWS-2099-0001" },
    { customer_snapshot: {} },
    { sdf_package: "start" },
  ]) {
    const rejected = await handleCommercialOperator(
      request({ ...sdfM1InvoicePreparationRequest, ...override }),
      dependencies().deps,
    );
    assertEquals(rejected.status, 400);
    assertEquals((await rejected.json()).code, "INVALID_REQUEST");
  }
});

Deno.test("SDF M1 invoice preparation transport reuses the caller RPC and canonical response", async () => {
  const calls: unknown[] = [];
  const candidateId = "a1800000-0000-4000-8000-000000000099";
  const client = {
    rpc: async (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      return {
        data: {
          candidate_id: candidateId,
          candidate_state: "PREPARED",
          invoice_number: null,
          was_created: true,
        },
        error: null,
      };
    },
  };
  assertEquals(
    await executeSdfM1InvoicePreparationTransport(
      client,
      sdfM1InvoicePreparationRequest,
    ),
    {
      obligation_id: sdfM1InvoicePreparationRequest.obligation_id,
      candidate_id: candidateId,
      candidate_state: "PREPARED",
      invoice_number: null,
      was_created: true,
    },
  );
  assertEquals(calls, [{
    name: "prepare_sdf_m1_invoice_candidate_v1",
    args: {
      p_obligation_id: sdfM1InvoicePreparationRequest.obligation_id,
      p_template_authority_id:
        sdfM1InvoicePreparationRequest.template_authority_id,
      p_idempotency_key: sdfM1InvoicePreparationRequest.idempotency_key,
    },
  }]);

  const reused = await executeSdfM1InvoicePreparationTransport({
    rpc: async () => ({
      data: {
        candidate_id: candidateId,
        candidate_state: "PREPARED",
        invoice_number: null,
        was_created: false,
      },
      error: null,
    }),
  }, sdfM1InvoicePreparationRequest);
  assertEquals(reused.candidate_id, candidateId);
  assertEquals(reused.was_created, false);
});

Deno.test("SDF M1 invoice preparation index dispatch constructs only a caller JWT client", async () => {
  const seenJwts: string[] = [];
  const candidateId = "a1800000-0000-4000-8000-000000000099";
  const result = await executeCallerJwtSdfM1InvoicePreparationAction(
    jwt,
    sdfM1InvoicePreparationRequest,
    (seenJwt) => {
      seenJwts.push(seenJwt);
      return {
        rpc: async () => ({
          data: {
            candidate_id: candidateId,
            candidate_state: "PREPARED",
            invoice_number: null,
            was_created: true,
          },
          error: null,
        }),
      };
    },
  );
  assertEquals(seenJwts, [jwt]);
  assertEquals(result, {
    obligation_id: sdfM1InvoicePreparationRequest.obligation_id,
    candidate_id: candidateId,
    candidate_state: "PREPARED",
    invoice_number: null,
    was_created: true,
  });
});

Deno.test("SDF M1 invoice preparation fails closed on response drift and maps RPC errors", async () => {
  await assertRejects(
    () => executeSdfM1InvoicePreparationTransport({
      rpc: async () => ({
        data: {
          candidate_id: crypto.randomUUID(),
          candidate_state: "ISSUED",
          invoice_number: "LWS-2099-0001",
          was_created: true,
        },
        error: null,
      }),
    }, sdfM1InvoicePreparationRequest),
    Error,
    "INVALID_SDF_M1_INVOICE_PREPARATION_RESPONSE",
  );

  for (const [message, status, code] of [
    ["SDF_INVOICE_AUTHORITY_DENIED", 403, "OPERATOR_NOT_AUTHORIZED"],
    ["SDF_M1_OBLIGATION_REQUIRED", 404, "NOT_FOUND"],
    ["SDF_INVOICE_TEMPLATE_AUTHORITY_REQUIRED", 404, "NOT_FOUND"],
    ["IDEMPOTENCY_CONFLICT", 409, "IDEMPOTENCY_CONFLICT"],
    ["SDF_M1_INVOICE_CANDIDATE_CONFLICT", 409, "CONFLICT"],
    ["SDF_APPLICATION_REFERENCE_REQUIRED", 409, "VALIDATION_FAILED"],
  ] as const) {
    const response = await handleCommercialOperator(
      request(sdfM1InvoicePreparationRequest),
      dependencies({
        executeApplicationAction: async () => {
          throw new Error(message);
        },
      }).deps,
    );
    assertEquals(response.status, status);
    assertEquals((await response.json()).code, code);
  }
});
const quotationBusinessRequest = {
  action: "upsert_quotation_business_draft" as const,
  intake_id: "a1800000-0000-4000-8000-000000000083",
  expected_revision: 0,
  idempotency_key: "a1800000-0000-4000-8000-000000000084",
  input: quotationBusinessInput,
};
const quotationPromotionRequest = {
  action: "promote_quotation_business_draft_to_approval" as const,
  intake_id: quotationBusinessRequest.intake_id,
  expected_revision: 1,
  idempotency_key: "a1800000-0000-4000-8000-000000000086",
};
const quotationIssuanceRequest = {
  action: "issue_and_deliver_approved_quotation" as const,
  quote_request_id: "a1800000-0000-4000-8000-000000000090",
};
const sdfQuotationIssuanceRequest = {
  action: "issue_sdf_approved_quotation" as const,
  quote_request_id: "a1800000-0000-4000-8000-000000000090",
  business_draft_id: "a1800000-0000-4000-8000-000000000091",
  approval_id: "a1800000-0000-4000-8000-000000000092",
  approval_version: 3,
  approval_sha256: "a".repeat(64),
  generation_contract_version: 1,
};
const sdfQuotationDeliveryPreparationRequest = {
  action: "prepare_sdf_quotation_delivery" as const,
  business_draft_id: "a1800000-0000-4000-8000-000000000091",
  approval_id: "a1800000-0000-4000-8000-000000000092",
  approval_version: 3,
  approval_sha256: "a".repeat(64),
  issuance_id: "a1800000-0000-4000-8000-000000000093",
  artifact_id: "a1800000-0000-4000-8000-000000000094",
  artifact_sha256: "b".repeat(64),
  artifact_bytes: 4096,
};
const sdfQuotationDeliverySendRequest = {
  ...sdfQuotationDeliveryPreparationRequest,
  action: "send_sdf_quotation_delivery" as const,
};

Deno.test("allowed production preflight returns the complete CORS contract without side effects", async () => {
  let nextCalls = 0;
  const response = await withCommercialOperatorCors(
    new Request("https://example.test", {
      method: "OPTIONS",
      headers: {
        Origin: "https://lorenzowebsolutions.be",
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "apikey,authorization,content-type,x-client-info",
      },
    }),
    async () => {
      nextCalls += 1;
      return new Response(null, { status: 500 });
    },
  );
  assertEquals(response.status, 204);
  assertEquals(
    response.headers.get("access-control-allow-origin"),
    "https://lorenzowebsolutions.be",
  );
  assertEquals(
    response.headers.get("access-control-allow-headers"),
    "apikey,authorization,content-type,idempotency-key,x-client-info,x-requested-with",
  );
  assertEquals(
    response.headers.get("access-control-allow-methods"),
    "GET,POST,OPTIONS",
  );
  assertEquals(nextCalls, 0);
});

Deno.test("allowed production success and error responses include CORS", async () => {
  const successHarness = dependencies();
  const success = await withCommercialOperatorCors(
    request({ action: "list_applications" }),
    () =>
      handleCommercialOperator(
        request({ action: "list_applications" }),
        successHarness.deps,
      ),
  );
  assertEquals(success.status, 200);
  assertEquals(
    success.headers.get("access-control-allow-origin"),
    "https://lorenzowebsolutions.be",
  );

  const error = await withCommercialOperatorCors(
    new Request("https://example.test", {
      method: "GET",
      headers: { Origin: "https://lorenzowebsolutions.be" },
    }),
    () =>
      handleCommercialOperator(
        new Request("https://example.test", { method: "GET" }),
        dependencies().deps,
      ),
  );
  assertEquals(error.status, 405);
  assertEquals(
    error.headers.get("access-control-allow-origin"),
    "https://lorenzowebsolutions.be",
  );
});

Deno.test("disallowed origin is rejected before handler execution", async () => {
  let nextCalls = 0;
  const response = await withCommercialOperatorCors(
    new Request("https://example.test", {
      method: "POST",
      headers: { Origin: "https://attacker.example" },
    }),
    async () => {
      nextCalls += 1;
      return new Response(null, { status: 200 });
    },
  );
  assertEquals(response.status, 403);
  assertEquals(
    response.headers.get("access-control-allow-origin"),
    "https://lorenzowebsolutions.be",
  );
  assertEquals(nextCalls, 0);
});

Deno.test("application list uses the verified human JWT and bounded pagination", async () => {
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({ action: "list_applications", limit: 25, offset: 5 }),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(harness.calls, [{
    jwt,
    input: { action: "list_applications", limit: 25, offset: 5 },
  }]);
});

Deno.test("authentication failures deny before command dispatch", async () => {
  const cases = [
    {
      name: "missing bearer",
      request: new Request("https://example.test", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "list_applications" }),
      }),
    },
    {
      name: "malformed JWT",
      request: request({ action: "list_applications" }, "not-a-jwt"),
    },
    {
      name: "expired JWT",
      request: request(
        { action: "list_applications" },
        createUnsignedTestJwt({
          sub: userId,
          role: "authenticated",
          exp: 1,
        }),
      ),
    },
  ];
  for (const testCase of cases) {
    const harness = dependencies();
    let verifyCalls = 0;
    const response = await handleCommercialOperator(testCase.request, {
      ...harness.deps,
      verifyUser: async () => {
        verifyCalls += 1;
        return { id: userId };
      },
    });
    assertEquals(response.status, 401, testCase.name);
    assertEquals(verifyCalls, 0, testCase.name);
    assertEquals(harness.calls.length, 0, testCase.name);
  }
});

Deno.test("Supabase Auth rejection and errors fail closed before dispatch", async () => {
  for (
    const verifyUser of [
      async () => null,
      async () => {
        throw new Error("AUTH_UNAVAILABLE");
      },
    ]
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request({ action: "list_applications" }),
      { ...harness.deps, verifyUser },
    );
    assertEquals(response.status >= 400, true);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("runtime auth adapter verifies the exact bearer JWT and rejects Auth errors", async () => {
  const calls: string[] = [];
  const client = (user: { id: string } | null, error: unknown = null) => ({
    auth: {
      getUser: async (token: string) => {
        calls.push(token);
        return { data: { user }, error };
      },
    },
  });
  assertEquals(await verifySupabaseAuthUser(client({ id: userId }), jwt), {
    id: userId,
  });
  assertEquals(
    await verifySupabaseAuthUser(client(null, "INVALID_JWT"), jwt),
    null,
  );
  assertEquals(
    await verifySupabaseAuthUser(client(null, "WRONG_PROJECT"), jwt),
    null,
  );
  assertEquals(calls, [jwt, jwt, jwt]);
});

Deno.test("commercial operator command disables its legacy gateway JWT check", async () => {
  const config = await Deno.readTextFile(
    new URL("../../config.toml", import.meta.url),
  );
  const section = config.match(
    /\[functions\.commercial-operator-command\]([\s\S]*?)(?=\n\[|$)/,
  );
  assertEquals(
    [...(section?.[1].matchAll(/^verify_jwt\s*=\s*(true|false)$/gm) ?? [])]
      .map((match) => match[1]),
    ["false"],
  );
});

Deno.test("application detail requires exactly one valid locator", async () => {
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({
      action: "get_application_detail",
      application_reference: "LWS-AAN-2099-0001",
    }),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(harness.calls[0].input, {
    action: "get_application_detail",
    quote_request_id: null,
    application_reference: "LWS-AAN-2099-0001",
    support_reference: null,
  });
  for (
    const applicationReference of ["lws-aan-2099-0001", " LWS-AAN-2099-0001 "]
  ) {
    assertEquals(
      (await handleCommercialOperator(
        request({
          action: "get_application_detail",
          application_reference: applicationReference,
        }),
        harness.deps,
      )).status,
      400,
    );
  }
  const ambiguous = await handleCommercialOperator(
    request({
      action: "get_application_detail",
      quote_request_id: userId,
      application_reference: "LWS-AAN-2099-0001",
    }),
    harness.deps,
  );
  assertEquals(ambiguous.status, 400);
  assertEquals(harness.calls.length, 1);
});

Deno.test("application detail normalizes one support-reference locator", async () => {
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({
      action: "get_application_detail",
      support_reference: " f98b2f08 ",
    }),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(harness.calls[0].input, {
    action: "get_application_detail",
    quote_request_id: null,
    application_reference: null,
    support_reference: "#F98B2F08",
  });

  for (
    const body of [
      { action: "get_application_detail", support_reference: "#F98B2F0" },
      {
        action: "get_application_detail",
        support_reference: "#F98B2F08",
        quote_request_id: userId,
      },
      {
        action: "promote_accepted_application",
        support_reference: "#F98B2F08",
        idempotency_key: "a1800000-0000-4000-8000-000000000001",
      },
    ]
  ) {
    assertEquals(
      (await handleCommercialOperator(request(body), harness.deps)).status,
      400,
    );
  }
  assertEquals(harness.calls.length, 1);
});

Deno.test("application detail preserves successful historical support reads", async () => {
  const calls: string[] = [];
  const result = await executeApplicationDetailRead(
    {
      rpc: async (name) => {
        calls.push(name);
        return { data: { source: "historical" }, error: null };
      },
    },
    () => ({
      rpc: async (name) => {
        calls.push(name);
        return { data: null, error: null };
      },
    }),
    {
      quote_request_id: null,
      application_reference: null,
      support_reference: "#F98B2F08",
    },
    userId,
  );
  assertEquals(result, { data: { source: "historical" }, error: null });
  assertEquals(calls, ["get_operator_application_by_support_reference_v1"]);
});

Deno.test("application detail falls back only for a missing support-reference detail", async () => {
  const calls: Array<{ name: string; parameters: Record<string, unknown> }> = [];
  const result = await executeApplicationDetailRead(
    {
      rpc: async (name, parameters) => {
        calls.push({ name, parameters });
        return { data: null, error: { message: "APPLICATION_NOT_FOUND" } };
      },
    },
    () => ({
      rpc: async (name, parameters) => {
        calls.push({ name, parameters });
        return { data: { source: "trashed-website-intake" }, error: null };
      },
    }),
    {
      quote_request_id: null,
      application_reference: null,
      support_reference: "#F98B2F08",
    },
    userId,
  );
  assertEquals(result, {
    data: { source: "trashed-website-intake" },
    error: null,
  });
  assertEquals(calls, [
    {
      name: "get_operator_application_by_support_reference_v1",
      parameters: { p_support_reference: "#F98B2F08" },
    },
    {
      name: "get_operator_trashed_website_intake_detail_v1",
      parameters: {
        p_actor_auth_user_id: userId,
        p_support_reference: "#F98B2F08",
      },
    },
  ]);
});

Deno.test("application detail never falls back for other errors or locators", async () => {
  let fallbackCalls = 0;
  const serviceClient = () => ({
    rpc: async () => {
      fallbackCalls += 1;
      return { data: null, error: null };
    },
  });
  const denied = await executeApplicationDetailRead(
    {
      rpc: async () => ({
        data: null,
        error: { message: "APPLICATION_SCOPE_DENIED" },
      }),
    },
    serviceClient,
    {
      quote_request_id: null,
      application_reference: null,
      support_reference: "#F98B2F08",
    },
    userId,
  );
  const normalMissing = await executeApplicationDetailRead(
    {
      rpc: async () => ({
        data: null,
        error: { message: "APPLICATION_NOT_FOUND" },
      }),
    },
    serviceClient,
    {
      quote_request_id: userId,
      application_reference: null,
      support_reference: null,
    },
    userId,
  );
  assertEquals(denied.error, { message: "APPLICATION_SCOPE_DENIED" });
  assertEquals(normalMissing.error, { message: "APPLICATION_NOT_FOUND" });
  assertEquals(fallbackCalls, 0);
});

Deno.test("dossier substance requires one quote request and validates its closed response", async () => {
  const harness = dependencies();
  const accepted = await handleCommercialOperator(
    request({ action: "get_dossier_substance", quote_request_id: userId }),
    harness.deps,
  );
  assertEquals(accepted.status, 200);
  assertEquals(harness.events, ["preflight"]);

  for (const body of [
    { action: "get_dossier_substance" },
    { action: "get_dossier_substance", quote_request_id: "invalid" },
    { action: "get_dossier_substance", quote_request_id: userId, customer: "forbidden" },
  ]) {
    assertEquals((await handleCommercialOperator(request(body), harness.deps)).status, 400);
  }

  const invalid = dependencies({
    executeDossierSubstance: async () => ({ quote_request_id: userId }),
  });
  assertEquals((await handleCommercialOperator(
    request({ action: "get_dossier_substance", quote_request_id: userId }),
    invalid.deps,
  )).status, 500);
});

Deno.test("dossier assignment read accepts only one normalized reference", async () => {
  for (
    const [dossierReference, normalizedReference] of [
      [" LWS-AAN-2099-0001 ", "LWS-AAN-2099-0001"],
      [" f98b2f08 ", "#F98B2F08"],
      ["#f98b2f08", "#F98B2F08"],
    ]
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request({
        action: "get_dossier_assignment",
        dossier_reference: dossierReference,
      }),
      harness.deps,
    );
    assertEquals(response.status, 200);
    assertEquals(harness.calls, [{
      jwt,
      input: {
        action: "get_dossier_assignment",
        dossier_reference: normalizedReference,
      },
    }]);
    assertEquals(await response.json(), {
      ok: true,
      code: "APPLICATION_ACTION_ACCEPTED",
      result: { action: "get_dossier_assignment" },
    });
  }

  for (
    const invalid of [
      {},
      { dossier_reference: "invalid" },
      { dossier_reference: "LWS-AAN-2099-0001", quote_request_id: userId },
      { dossier_reference: "LWS-AAN-2099-0001", actor_id: userId },
    ]
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request({
        action: "get_dossier_assignment",
        ...invalid,
      }),
      harness.deps,
    );
    assertEquals(response.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("assignment roster accepts only the fixed read action", async () => {
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({
      action: "get_assignment_operator_roster",
    }),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(harness.calls, [{
    jwt,
    input: { action: "get_assignment_operator_roster" },
  }]);
  assertEquals(await response.json(), {
    ok: true,
    code: "APPLICATION_ACTION_ACCEPTED",
    result: { action: "get_assignment_operator_roster" },
  });

  for (
    const extra of [{ role: "operator" }, { status: "ACTIVE" }, {
      actor_id: userId,
    }]
  ) {
    const invalidHarness = dependencies();
    const invalidResponse = await handleCommercialOperator(
      request({
        action: "get_assignment_operator_roster",
        ...extra,
      }),
      invalidHarness.deps,
    );
    assertEquals(invalidResponse.status, 400);
    assertEquals(invalidHarness.calls.length, 0);
  }
});

Deno.test("assignment roster uses the exact RPC and exposes only eligible picker fields", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await executeAssignmentOperatorRosterTransport({
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      return Promise.resolve({
        data: [
          {
            operator_id: "a1800000-0000-4000-8000-000000000060",
            display_name: "Active Operator",
            role: "operator",
            status: "ACTIVE",
            auth_user_id: userId,
            email: "private@example.test",
            history: [{ event_type: "PRIVATE" }],
          },
          {
            operator_id: "a1800000-0000-4000-8000-000000000061",
            display_name: "Manager",
            role: "operations_manager",
            status: "ACTIVE",
          },
          {
            operator_id: "a1800000-0000-4000-8000-000000000062",
            display_name: "Owner",
            role: "owner",
            status: "ACTIVE",
          },
          {
            operator_id: "a1800000-0000-4000-8000-000000000063",
            display_name: "Disabled",
            role: "operator",
            status: "DISABLED",
          },
          {
            operator_id: "a1800000-0000-4000-8000-000000000064",
            display_name: "Revoked",
            role: "operator",
            status: "REVOKED",
          },
        ],
        error: null,
      });
    },
  });
  assertEquals(calls, [{ name: "get_operations_manager_roster_v1", args: {} }]);
  assertEquals(result, [{
    operator_id: "a1800000-0000-4000-8000-000000000060",
    display_name: "Active Operator",
  }]);
  assertEquals(Object.keys(result[0]), ["operator_id", "display_name"]);
});

Deno.test("assignment roster preserves a valid empty eligible result", async () => {
  const result = await executeAssignmentOperatorRosterTransport({
    rpc: () => Promise.resolve({ data: [], error: null }),
  });
  assertEquals(result, []);
});

Deno.test("index assignment roster dispatch constructs its RPC client from the caller JWT", async () => {
  const clientForCalls: string[] = [];
  const rpcCalls: string[] = [];
  const result = await executeCallerJwtAssignmentRosterAction(
    jwt,
    (token: string) => {
      clientForCalls.push(token);
      return {
        rpc: (name: string) => {
          rpcCalls.push(name);
          return Promise.resolve({ data: [], error: null });
        },
      };
    },
  );
  assertEquals(clientForCalls, [jwt]);
  assertEquals(rpcCalls, ["get_operations_manager_roster_v1"]);
  assertEquals(result, []);
});

Deno.test("assignment roster errors use stable authorization and internal contracts", async () => {
  for (
    const [databaseCode, status, responseCode] of [
      [
        "OPERATIONS_MANAGER_ROSTER_READER_REQUIRED",
        403,
        "OPERATOR_NOT_AUTHORIZED",
      ],
      ["OPERATOR_REVOKED", 403, "OPERATOR_NOT_AUTHORIZED"],
      ["UNEXPECTED_ROSTER_FAILURE", 500, "INTERNAL_ERROR"],
    ] as const
  ) {
    const harness = dependencies({
      executeApplicationAction: async () => {
        throw new Error(databaseCode);
      },
    });
    const response = await handleCommercialOperator(
      request({
        action: "get_assignment_operator_roster",
      }),
      harness.deps,
    );
    assertEquals(response.status, status);
    assertEquals((await response.json()).code, responseCode);
  }
});

Deno.test("personal dossier queue accepts only bounded cursor pagination without client authority", async () => {
  for (
    const [body, input] of [
      [{ action: "get_my_assigned_dossiers" }, {
        action: "get_my_assigned_dossiers",
        cursor: null,
        limit: 25,
      }],
      [{ action: "get_my_assigned_dossiers", cursor: "aabb", limit: 100 }, {
        action: "get_my_assigned_dossiers",
        cursor: "aabb",
        limit: 100,
      }],
    ] as const
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request(body),
      harness.deps,
    );
    assertEquals(response.status, 200);
    assertEquals(harness.calls, [{ jwt, input }]);
  }

  for (
    const invalid of [
      { operator_id: userId },
      { assignee_operator_id: userId },
      { auth_user_id: userId },
      { role: "operator" },
      { status: "ACTIVE" },
      { cursor: "" },
      { cursor: 1 },
      { limit: 0 },
      { limit: -1 },
      { limit: 1.5 },
      { limit: 101 },
      { limit: null },
    ]
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request({ action: "get_my_assigned_dossiers", ...invalid }),
      harness.deps,
    );
    assertEquals(response.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("personal dossier queue transport uses the exact caller-scoped RPC", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const safeResult = {
    items: [{ reference: "LWS-AAN-2099-0001" }],
    has_more: false,
    next_cursor: null,
  };
  const result = await executeOperatorPersonalQueueTransport({
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      return Promise.resolve({ data: safeResult, error: null });
    },
  }, { action: "get_my_assigned_dossiers", cursor: "aabb", limit: 25 });
  assertEquals(calls, [{
    name: "get_operator_personal_dossier_queue_v1",
    args: { p_cursor: "aabb", p_limit: 25 },
  }]);
  assertEquals(result, safeResult);
});

Deno.test("personal dossier queue index dispatch constructs only a caller JWT client", async () => {
  const clientForCalls: string[] = [];
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await executeCallerJwtOperatorPersonalQueueAction(
    jwt,
    { action: "get_my_assigned_dossiers", cursor: null, limit: 25 },
    (token: string) => {
      clientForCalls.push(token);
      return {
        rpc: (name: string, args: Record<string, unknown>) => {
          rpcCalls.push({ name, args });
          return Promise.resolve({
            data: { items: [], has_more: false, next_cursor: null },
            error: null,
          });
        },
      };
    },
  );
  assertEquals(clientForCalls, [jwt]);
  assertEquals(rpcCalls, [{
    name: "get_operator_personal_dossier_queue_v1",
    args: { p_cursor: null, p_limit: 25 },
  }]);
  assertEquals(result, { items: [], has_more: false, next_cursor: null });
});

Deno.test("personal dossier queue rejects service role JWT before dispatch", async () => {
  const serviceJwt = createUnsignedTestJwt({
    sub: userId,
    role: "service_role",
    exp: 4102444800,
  });
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({ action: "get_my_assigned_dossiers" }, serviceJwt),
    harness.deps,
  );
  assertEquals(response.status, 401);
  assertEquals((await response.json()).code, "HUMAN_JWT_REQUIRED");
  assertEquals(harness.calls.length, 0);
});

Deno.test("personal dossier queue errors use stable public envelopes", async () => {
  for (
    const [databaseCode, status, responseCode] of [
      [
        "OPERATOR_PERSONAL_QUEUE_READER_REQUIRED",
        403,
        "OPERATOR_NOT_AUTHORIZED",
      ],
      ["OPERATOR_DISABLED", 403, "OPERATOR_NOT_AUTHORIZED"],
      ["INVALID_OPERATOR_PERSONAL_QUEUE_CURSOR", 400, "INVALID_REQUEST"],
      ["INVALID_OPERATOR_PERSONAL_QUEUE_LIMIT", 400, "INVALID_REQUEST"],
      ["UNEXPECTED_PERSONAL_QUEUE_FAILURE", 500, "INTERNAL_ERROR"],
    ] as const
  ) {
    const harness = dependencies({
      executeApplicationAction: async () => {
        throw new Error(databaseCode);
      },
    });
    const response = await handleCommercialOperator(
      request({ action: "get_my_assigned_dossiers" }),
      harness.deps,
    );
    assertEquals(response.status, status);
    assertEquals(await response.json(), { ok: false, code: responseCode });
  }
});

Deno.test("existing assignment Edge actions remain registered alongside personal queue", async () => {
  for (
    const body of [
      {
        action: "get_dossier_assignment",
        dossier_reference: "LWS-AAN-2099-0001",
      },
      { action: "get_assignment_operator_roster" },
      {
        action: "assign_dossier",
        dossier_reference: "LWS-AAN-2099-0001",
        assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
        expected_revision: 2,
        idempotency_key: "a1800000-0000-4000-8000-000000000051",
      },
    ]
  ) {
    const response = await handleCommercialOperator(
      request(body),
      dependencies().deps,
    );
    assertEquals(response.status, 200);
  }
});

Deno.test("dossier assignment mutation validates and normalizes the fixed command shape", async () => {
  for (
    const [reasonInput, normalizedReason] of [
      [undefined, null],
      [null, null],
      ["   ", null],
      ["  Capacity rebalance  ", "Capacity rebalance"],
    ]
  ) {
    const harness = dependencies();
    const body: Record<string, unknown> = {
      action: "assign_dossier",
      dossier_reference: " f98b2f08 ",
      assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
      expected_revision: 2,
      idempotency_key: "a1800000-0000-4000-8000-000000000051",
    };
    if (reasonInput !== undefined) body.reason = reasonInput;
    const response = await handleCommercialOperator(
      request(body),
      harness.deps,
    );
    assertEquals(response.status, 200);
    assertEquals(harness.calls, [{
      jwt,
      input: {
        action: "assign_dossier",
        dossier_reference: "#F98B2F08",
        assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
        expected_revision: 2,
        idempotency_key: "a1800000-0000-4000-8000-000000000051",
        reason: normalizedReason,
      },
    }]);
  }

  for (
    const invalid of [
      { dossier_reference: undefined },
      { dossier_reference: "invalid" },
      { assignee_operator_id: "invalid" },
      { expected_revision: -1 },
      { expected_revision: 1.5 },
      { idempotency_key: "invalid" },
      { reason: 42 },
      { reason: "x".repeat(501) },
      { auth_user_id: userId },
      { role: "owner" },
      { capability: userId },
    ]
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request({
        action: "assign_dossier",
        dossier_reference: "LWS-AAN-2099-0001",
        assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
        expected_revision: 2,
        idempotency_key: "a1800000-0000-4000-8000-000000000051",
        ...invalid,
      }),
      harness.deps,
    );
    assertEquals(response.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("assignment transports call exact RPCs through the supplied human client", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const readResult = {
    assignment_state: "ASSIGNED",
    assignee_operator_id: userId,
    assignee_display_name: "Assigned Operator",
    revision: 2,
    assigned_at: "2099-01-01T00:00:00Z",
  };
  const mutationResult = {
    assignment_state: "ASSIGNED",
    assignee_operator_id: userId,
    revision: 3,
    assigned_at: "2099-01-01T00:00:01Z",
    no_change: false,
    replayed: false,
  };
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      return Promise.resolve({
        data: name === "get_operator_dossier_assignment_v1"
          ? readResult
          : mutationResult,
        error: null,
      });
    },
  };
  const actualReadResult = await executeDossierAssignmentReadTransport(client, {
    action: "get_dossier_assignment",
    dossier_reference: "#F98B2F08",
  });
  const actualMutationResult = await executeDossierAssignmentMutationTransport(
    client,
    {
      action: "assign_dossier",
      dossier_reference: "#F98B2F08",
      assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
      expected_revision: 2,
      idempotency_key: "a1800000-0000-4000-8000-000000000051",
      reason: null,
    },
  );
  assertEquals(calls, [
    {
      name: "get_operator_dossier_assignment_v1",
      args: { p_dossier_reference: "#F98B2F08" },
    },
    {
      name: "assign_operator_dossier_v1",
      args: {
        p_dossier_reference: "#F98B2F08",
        p_assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
        p_expected_revision: 2,
        p_idempotency_key: "a1800000-0000-4000-8000-000000000051",
        p_reason: null,
      },
    },
  ]);
  assertEquals(actualReadResult, readResult);
  assertEquals(actualMutationResult, mutationResult);
});

Deno.test("index assignment dispatch constructs both RPC clients from the caller JWT", async () => {
  const clientForCalls: string[] = [];
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const clientFor = (token: string) => {
    clientForCalls.push(token);
    return {
      rpc: (name: string, args: Record<string, unknown>) => {
        rpcCalls.push({ name, args });
        return Promise.resolve({
          data: { assignment_state: "ASSIGNED" },
          error: null,
        });
      },
    };
  };

  await executeCallerJwtDossierAssignmentAction(jwt, {
    action: "get_dossier_assignment",
    dossier_reference: "#F98B2F08",
  }, clientFor);
  await executeCallerJwtDossierAssignmentAction(jwt, {
    action: "assign_dossier",
    dossier_reference: "#F98B2F08",
    assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
    expected_revision: 2,
    idempotency_key: "a1800000-0000-4000-8000-000000000051",
    reason: null,
  }, clientFor);

  assertEquals(clientForCalls, [jwt, jwt]);
  assertEquals(rpcCalls.map(({ name }) => name), [
    "get_operator_dossier_assignment_v1",
    "assign_operator_dossier_v1",
  ]);
});

Deno.test("assignment success variants pass through without synthetic state", async () => {
  for (
    const result of [
      {
        assignment_state: "ASSIGNED",
        assignee_operator_id: userId,
        revision: 1,
        assigned_at: "2099-01-01T00:00:00Z",
        no_change: false,
        replayed: false,
      },
      {
        assignment_state: "ASSIGNED",
        assignee_operator_id: userId,
        revision: 1,
        assigned_at: "2099-01-01T00:00:00Z",
        no_change: true,
        replayed: false,
      },
      {
        assignment_state: "ASSIGNED",
        assignee_operator_id: userId,
        revision: 1,
        assigned_at: "2099-01-01T00:00:00Z",
        no_change: false,
        replayed: true,
      },
    ]
  ) {
    const harness = dependencies({
      executeApplicationAction: async () => result,
    });
    const response = await handleCommercialOperator(
      request({
        action: "assign_dossier",
        dossier_reference: "LWS-AAN-2099-0001",
        assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
        expected_revision: 0,
        idempotency_key: "a1800000-0000-4000-8000-000000000051",
      }),
      harness.deps,
    );
    assertEquals(response.status, 200);
    assertEquals((await response.json()).result, result);
  }
});

Deno.test("assignment database errors expose stable transport contracts", async () => {
  for (
    const [databaseCode, status, responseCode] of [
      ["DOSSIER_ASSIGNMENT_ACTOR_REQUIRED", 403, "OPERATOR_NOT_AUTHORIZED"],
      ["DOSSIER_ASSIGNMENT_READER_REQUIRED", 403, "OPERATOR_NOT_AUTHORIZED"],
      ["DOSSIER_NOT_FOUND", 404, "DOSSIER_NOT_FOUND"],
      ["AMBIGUOUS_DOSSIER_REFERENCE", 409, "AMBIGUOUS_DOSSIER_REFERENCE"],
      ["ASSIGNEE_OPERATOR_NOT_FOUND", 404, "ASSIGNEE_OPERATOR_NOT_FOUND"],
      ["ASSIGNEE_NOT_ELIGIBLE", 409, "ASSIGNEE_NOT_ELIGIBLE"],
      ["OPERATOR_DOSSIER_ASSIGNMENT_STATE_REQUIRED", 409, "COMMAND_REJECTED"],
      ["CONCURRENT_MODIFICATION", 409, "CONCURRENT_MODIFICATION"],
      ["IDEMPOTENCY_CONFLICT", 409, "IDEMPOTENCY_CONFLICT"],
      ["INVALID_DOSSIER_REFERENCE", 400, "INVALID_REQUEST"],
      ["INVALID_DOSSIER_ASSIGNMENT_COMMAND", 400, "INVALID_REQUEST"],
      ["REASSIGNMENT_REASON_REQUIRED", 400, "INVALID_REQUEST"],
      ["UNEXPECTED_ASSIGNMENT_FAILURE", 500, "INTERNAL_ERROR"],
    ] as const
  ) {
    const harness = dependencies({
      executeApplicationAction: async () => {
        throw new Error(databaseCode);
      },
    });
    const response = await handleCommercialOperator(
      request({
        action: "assign_dossier",
        dossier_reference: "LWS-AAN-2099-0001",
        assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
        expected_revision: 0,
        idempotency_key: "a1800000-0000-4000-8000-000000000051",
      }),
      harness.deps,
    );
    assertEquals(response.status, status);
    assertEquals((await response.json()).code, responseCode);
  }
});

Deno.test("project dossier accepts only one server-authorized project UUID", async () => {
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({ action: "get_project_dossier", project_id: userId }),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(harness.calls[0], {
    jwt,
    input: { action: "get_project_dossier", project_id: userId },
  });
  const invalid = await handleCommercialOperator(
    request({ action: "get_project_dossier", project_id: "not-a-project" }),
    harness.deps,
  );
  assertEquals(invalid.status, 400);
  assertEquals(harness.calls.length, 1);
});

Deno.test("project site actions use a fixed validated command shape", async () => {
  for (
    const [action, operation, expectedRevision] of [
      ["bind_project_site", "INITIAL_BIND", 0],
      ["rotate_project_site", "ROTATION", 1],
    ]
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request({
        action,
        project_id: userId,
        expected_revision: expectedRevision,
        idempotency_key: "a1800000-0000-4000-8000-000000000009",
        canonical_domain: "project.example",
        evidence: "Approved operator site command",
      }),
      harness.deps,
    );
    assertEquals(response.status, 200);
    assertEquals(harness.calls[0].input, {
      action,
      project_id: userId,
      operation,
      expected_revision: expectedRevision,
      idempotency_key: "a1800000-0000-4000-8000-000000000009",
      canonical_domain: "project.example",
      evidence: "Approved operator site command",
    });
  }

  for (
    const invalid of [
      { canonical_domain: "https://project.example" },
      { canonical_domain: "Project.example" },
      { canonical_domain: "project.example/path" },
      { evidence: "" },
      { expected_revision: -1 },
    ]
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request({
        action: "rotate_project_site",
        project_id: userId,
        expected_revision: 1,
        idempotency_key: "a1800000-0000-4000-8000-000000000009",
        canonical_domain: "project.example",
        evidence: "Approved operator site command",
        ...invalid,
      }),
      harness.deps,
    );
    assertEquals(response.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("promotion requires server-shaped locator and idempotency UUID", async () => {
  const harness = dependencies();
  const invalid = await handleCommercialOperator(
    request({
      action: "promote_accepted_application",
      quote_request_id: userId,
      idempotency_key: "bad",
    }),
    harness.deps,
  );
  assertEquals(invalid.status, 400);
  const valid = await handleCommercialOperator(
    request({
      action: "promote_accepted_application",
      quote_request_id: userId,
      idempotency_key: "a1800000-0000-4000-8000-000000000001",
    }),
    harness.deps,
  );
  assertEquals(valid.status, 200);
  assertEquals(harness.calls.length, 1);
});

Deno.test("service role JWT cannot enter application actions", async () => {
  const serviceJwt = createUnsignedTestJwt({
    sub: userId,
    role: "service_role",
    exp: 4102444800,
  });
  for (
    const action of ["list_applications", "get_assignment_operator_roster", "inspect_sdf_qualification_intake"]
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request({ action }, serviceJwt),
      harness.deps,
    );
    assertEquals(response.status, 401);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("qualification inspect forwards quotation preparation authorization", async () => {
  const inspectResult = {
    quote_request_id: userId,
    status: "qualification_complete",
    quotation_preparation_authorized: true,
  };
  const harness = dependencies({
    executeApplicationAction: async () => inspectResult,
  });
  const response = await handleCommercialOperator(
    request({
      action: "inspect_sdf_qualification_intake",
      quote_request_id: userId,
    }),
    harness.deps,
  );

  assertEquals(response.status, 200);
  assertEquals((await response.json()).result, inspectResult);
});

Deno.test("intake lifecycle actions require the fixed revisioned command shape", async () => {
  for (
    const [action, eventType] of [
      ["interrupt_intake", "INTERRUPTED"],
      ["resume_intake", "RESUMED"],
      ["cancel_intake", "CANCELLED"],
      ["reactivate_intake", "REACTIVATED"],
    ]
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request({
        action,
        intake_id: "a1800000-0000-4000-8000-000000000030",
        expected_revision: 2,
        idempotency_key: "a1800000-0000-4000-8000-000000000031",
        reason: "  Operator lifecycle reason  ",
      }),
      harness.deps,
    );
    assertEquals(response.status, 200);
    assertEquals(harness.calls[0].input, {
      action,
      intake_id: "a1800000-0000-4000-8000-000000000030",
      event_type: eventType,
      expected_revision: 2,
      idempotency_key: "a1800000-0000-4000-8000-000000000031",
      reason: "Operator lifecycle reason",
    });
  }

  for (
    const invalid of [
      { expected_revision: -1 },
      { idempotency_key: "invalid" },
      { reason: "" },
      { reason: "x".repeat(501) },
      { access_token: "forbidden" },
    ]
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request({
        action: "interrupt_intake",
        intake_id: "a1800000-0000-4000-8000-000000000030",
        expected_revision: 2,
        idempotency_key: "a1800000-0000-4000-8000-000000000031",
        reason: "Reason",
        ...invalid,
      }),
      harness.deps,
    );
    assertEquals(response.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("intake lifecycle database errors retain existing HTTP contracts", async () => {
  for (
    const [databaseCode, status, responseCode] of [
      ["CONCURRENT_MODIFICATION", 409, "CONCURRENT_MODIFICATION"],
      ["INVALID_INTAKE_LIFECYCLE_TRANSITION", 409, "COMMAND_REJECTED"],
      ["IDEMPOTENCY_CONFLICT", 409, "IDEMPOTENCY_CONFLICT"],
      ["INTAKE_NOT_FOUND", 404, "INTAKE_NOT_FOUND"],
      ["OPERATOR_REVOKED", 403, "OPERATOR_NOT_AUTHORIZED"],
    ] as const
  ) {
    const harness = dependencies();
    harness.deps.executeApplicationAction = async () => {
      throw new Error(databaseCode);
    };
    const result = await handleCommercialOperator(
      request({
        action: "interrupt_intake",
        intake_id: "a1800000-0000-4000-8000-000000000030",
        expected_revision: 2,
        idempotency_key: "a1800000-0000-4000-8000-000000000031",
        reason: "Reason",
      }),
      harness.deps,
    );
    assertEquals(result.status, status);
    assertEquals((await result.json()).code, responseCode);
  }
});

Deno.test("dossier lifecycle actions require the fixed revisioned command shape", async () => {
  for (
    const [action, eventType] of [
      ["archive_dossier", "ARCHIVED"],
      ["reactivate_dossier", "REACTIVATED"],
      ["trash_dossier", "TRASHED"],
      ["restore_dossier", "RESTORED"],
    ]
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request({
        action,
        quote_request_id: "a1800000-0000-4000-8000-000000000040",
        expected_revision: 3,
        idempotency_key: "a1800000-0000-4000-8000-000000000041",
        reason: "  Operator dossier reason  ",
      }),
      harness.deps,
    );
    assertEquals(response.status, 200);
    assertEquals(harness.calls[0].input, {
      action,
      quote_request_id: "a1800000-0000-4000-8000-000000000040",
      event_type: eventType,
      expected_revision: 3,
      idempotency_key: "a1800000-0000-4000-8000-000000000041",
      reason: "Operator dossier reason",
    });
  }

  for (
    const invalid of [
      { quote_request_id: "invalid" },
      { expected_revision: -1 },
      { idempotency_key: "invalid" },
      { reason: "" },
      { reason: "x".repeat(501) },
      { event_type: "TRASHED" },
      { actor_operator_id: userId },
      { deletion_eligible_at: "2099-01-01T00:00:00Z" },
    ]
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request({
        action: "trash_dossier",
        quote_request_id: "a1800000-0000-4000-8000-000000000040",
        expected_revision: 3,
        idempotency_key: "a1800000-0000-4000-8000-000000000041",
        reason: "Reason",
        ...invalid,
      }),
      harness.deps,
    );
    assertEquals(response.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("dossier lifecycle database errors expose only stable public contracts", async () => {
  for (
    const [databaseCode, status, responseCode] of [
      ["DOSSIER_NOT_FOUND", 404, "DOSSIER_NOT_FOUND"],
      ["CONCURRENT_MODIFICATION", 409, "CONCURRENT_MODIFICATION"],
      ["IDEMPOTENCY_CONFLICT", 409, "IDEMPOTENCY_CONFLICT"],
      ["INVALID_OPERATOR_DOSSIER_TRANSITION", 409, "COMMAND_REJECTED"],
      ["LEGACY_TEST_CLEANUP_AUTHORITY_REQUIRED", 409, "COMMAND_REJECTED"],
      ["LEGACY_TEST_CLEANUP_IDENTITY_MISMATCH", 409, "COMMAND_REJECTED"],
      [
        "LEGACY_TEST_CLEANUP_QUOTATION_BLOCKER_PRESENT",
        409,
        "COMMAND_REJECTED",
      ],
      [
        "LEGACY_TEST_CLEANUP_COMMERCIAL_BLOCKER_PRESENT",
        409,
        "COMMAND_REJECTED",
      ],
      ["LEGACY_TEST_CLEANUP_PAYMENT_BLOCKER_PRESENT", 409, "COMMAND_REJECTED"],
      ["LEGACY_TEST_CLEANUP_SDF_BLOCKER_PRESENT", 409, "COMMAND_REJECTED"],
      ["TRASHED_DOSSIER_BLOCKER_CREATION_DENIED", 409, "COMMAND_REJECTED"],
      ["EDGE_DOSSIER_CAPABILITY_REQUIRED", 403, "OPERATOR_NOT_AUTHORIZED"],
    ] as const
  ) {
    const harness = dependencies();
    harness.deps.executeApplicationAction = async () => {
      throw new Error(databaseCode);
    };
    const result = await handleCommercialOperator(
      request({
        action: "trash_dossier",
        quote_request_id: "a1800000-0000-4000-8000-000000000040",
        expected_revision: 3,
        idempotency_key: "a1800000-0000-4000-8000-000000000041",
        reason: "Reason",
      }),
      harness.deps,
    );
    assertEquals(result.status, status);
    assertEquals((await result.json()).code, responseCode);
  }
});

Deno.test("dossier lifecycle transport issues server capability before JWT-bound command", async () => {
  const calls: Array<
    { client: string; name: string; args: Record<string, unknown> }
  > = [];
  const capability = "a1800000-0000-4000-8000-000000000042";
  const input = {
    action: "trash_dossier",
    quote_request_id: "a1800000-0000-4000-8000-000000000040",
    event_type: "TRASHED",
    expected_revision: 3,
    idempotency_key: "a1800000-0000-4000-8000-000000000041",
    reason: "Operator dossier reason",
  };
  const issueCapability = (args: Record<string, unknown>) => {
    calls.push({
      client: "service",
      name: "issue_operator_dossier_lifecycle_edge_capability_v1",
      args,
    });
    return Promise.resolve({ data: capability, error: null });
  };
  const executeCommand = (args: Record<string, unknown>) => {
    calls.push({
      client: "human",
      name: "execute_operator_dossier_lifecycle_command_v1",
      args,
    });
    return Promise.resolve({
      data: { state: "TRASHED", revision: 4 },
      error: null,
    });
  };

  assertEquals(
    await executeDossierLifecycleTransport(
      issueCapability,
      executeCommand,
      userId,
      input,
    ),
    { state: "TRASHED", revision: 4 },
  );
  assertEquals(calls, [
    {
      client: "service",
      name: "issue_operator_dossier_lifecycle_edge_capability_v1",
      args: {
        p_actor_auth_user_id: userId,
        p_quote_request_id: input.quote_request_id,
        p_event_type: input.event_type,
        p_expected_revision: input.expected_revision,
        p_idempotency_key: input.idempotency_key,
        p_reason: input.reason,
      },
    },
    {
      client: "human",
      name: "execute_operator_dossier_lifecycle_command_v1",
      args: {
        p_quote_request_id: input.quote_request_id,
        p_event_type: input.event_type,
        p_expected_revision: input.expected_revision,
        p_idempotency_key: input.idempotency_key,
        p_reason: input.reason,
        p_edge_capability: capability,
      },
    },
  ]);
});

Deno.test("existing commercial command path remains rate limited and unchanged", async () => {
  const harness = dependencies();
  let rateLimitCalls = 0;
  harness.deps.consumeRateLimit = async () => {
    rateLimitCalls += 1;
    return { allowed: true, retry_after_seconds: 0 };
  };
  const response = await handleCommercialOperator(
    request({
      project_id: userId,
      command_type: "archive_project",
      expected_state: "DELIVERED",
      expected_revision: 2,
      idempotency_key: "a1800000-0000-4000-8000-000000000001",
      payload: {},
    }),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(rateLimitCalls, 1);
  assertEquals(harness.calls.length, 0);
});

Deno.test("internal E2E creation accepts only the fixed owner-command shape", async () => {
  const harness = dependencies();
  const valid = await handleCommercialOperator(
    request({
      action: "create_internal_e2e_run",
      idempotency_key: "a1800000-0000-4000-8000-000000000010",
      run_label: "production smoke",
      ttl_minutes: 30,
    }),
    harness.deps,
  );
  assertEquals(valid.status, 200);
  assertEquals(harness.calls[0].input, {
    action: "create_internal_e2e_run",
    idempotency_key: "a1800000-0000-4000-8000-000000000010",
    run_label: "production smoke",
    ttl_minutes: 30,
  });
  for (
    const forbidden of [
      { classification: "internal_e2e" },
      { email: "attacker@example.test" },
      { mailbox: "attacker@example.test" },
    ]
  ) {
    const blocked = await handleCommercialOperator(
      request({
        action: "create_internal_e2e_run",
        idempotency_key: "a1800000-0000-4000-8000-000000000011",
        run_label: "blocked",
        ttl_minutes: 30,
        ...forbidden,
      }),
      harness.deps,
    );
    assertEquals(blocked.status, 400);
  }
  assertEquals(harness.calls.length, 1);
});

Deno.test("Customer Request smoke fixture accepts only an idempotency key", async () => {
  const harness = dependencies();
  const valid = await handleCommercialOperator(
    request({
      action: "create_customer_request_smoke_fixture",
      idempotency_key: "a1800000-0000-4000-8000-000000000030",
    }),
    harness.deps,
  );
  assertEquals(valid.status, 200);
  assertEquals(harness.calls[0].input, {
    action: "create_customer_request_smoke_fixture",
    idempotency_key: "a1800000-0000-4000-8000-000000000030",
  });
  for (
    const forbidden of [
      { run_label: "caller controlled" },
      { customer_id: userId },
      { project_id: userId },
      { quote_request_id: userId },
      { name: "Real Person" },
      { email: "real@example.com" },
      { record_classification: "production" },
      { request_reference: "LWS-VRZ-2099-9999" },
    ]
  ) {
    const blocked = await handleCommercialOperator(
      request({
        action: "create_customer_request_smoke_fixture",
        idempotency_key: "a1800000-0000-4000-8000-000000000031",
        ...forbidden,
      }),
      harness.deps,
    );
    assertEquals(blocked.status, 400);
  }
  assertEquals(harness.calls.length, 1);
});

Deno.test("Customer Request smoke fixture uses one atomic caller-JWT RPC", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await executeCallerJwtCustomerRequestSmokeFixtureAction(
    jwt,
    "a1800000-0000-4000-8000-000000000030",
    (token: string) => ({
      rpc: async (name: string, args: Record<string, unknown>) => {
        assertEquals(token, jwt);
        calls.push({ name, args });
        return {
          data: {
            run_id: userId,
            request_id: "a1800000-0000-4000-8000-000000000031",
          },
          error: null,
        };
      },
    }),
  );
  assertEquals(calls, [{
    name: "create_customer_request_smoke_fixture_v1",
    args: { p_idempotency_key: "a1800000-0000-4000-8000-000000000030" },
  }]);
  assertEquals(result, {
    run_id: userId,
    request_id: "a1800000-0000-4000-8000-000000000031",
  });
});

Deno.test("internal E2E accepted-file cleanup accepts only exact server-binding input", async () => {
  const harness = dependencies();
  const validInput = {
    action: "cleanup_internal_e2e_accepted_file",
    run_id: "a1800000-0000-4000-8000-000000000040",
    request_id: "a1800000-0000-4000-8000-000000000041",
    upload_request_id: "a1800000-0000-4000-8000-000000000042",
    uploaded_file_id: "a1800000-0000-4000-8000-000000000043",
    idempotency_key: "a1800000-0000-4000-8000-000000000044",
  };
  const valid = await handleCommercialOperator(
    request(validInput),
    harness.deps,
  );
  assertEquals(valid.status, 200);
  assertEquals(harness.calls[0].input, validInput);

  for (
    const forbidden of [
      { storage_bucket_id: "customer-request-quarantine" },
      { storage_object_path: "caller/selected.png" },
      { bucket: "customer-request-quarantine" },
      { path: "caller/selected.png" },
      { customer_id: userId },
    ]
  ) {
    const blocked = await handleCommercialOperator(
      request({ ...validInput, ...forbidden }),
      harness.deps,
    );
    assertEquals(blocked.status, 400);
  }
  assertEquals(harness.calls.length, 1);
});

Deno.test("internal E2E accepted-file cleanup authorizes, removes one exact object, then finalizes", async () => {
  const events: Array<Record<string, unknown>> = [];
  const input = {
    action: "cleanup_internal_e2e_accepted_file" as const,
    run_id: "a1800000-0000-4000-8000-000000000040",
    request_id: "a1800000-0000-4000-8000-000000000041",
    upload_request_id: "a1800000-0000-4000-8000-000000000042",
    uploaded_file_id: "a1800000-0000-4000-8000-000000000043",
    idempotency_key: "a1800000-0000-4000-8000-000000000044",
  };
  const result = await executeCallerJwtInternalE2EAcceptedFileCleanupAction(
    jwt,
    input,
    (token: string) => ({
      rpc: async (name: string, args: Record<string, unknown>) => {
        assertEquals(token, jwt);
        events.push({ client: "human", name, args });
        if (name === "authorize_internal_e2e_accepted_file_cleanup_v1") {
          return {
            data: {
              state: "AUTHORIZED",
              cleanup_authorization_id: "a1800000-0000-4000-8000-000000000045",
              storage_bucket_id: "customer-request-quarantine",
              storage_object_path:
                `requests/${input.request_id}/uploads/${input.upload_request_id}/files/${input.uploaded_file_id}.png`,
            },
            error: null,
          };
        }
        return {
          data: { state: "DELETED", uploaded_file_id: input.uploaded_file_id },
          error: null,
        };
      },
    }),
    () => ({
      storage: {
        from: (bucket: string) => ({
          remove: async (paths: string[]) => {
            events.push({
              client: "service",
              operation: "remove",
              bucket,
              paths,
            });
            return { data: [], error: null };
          },
        }),
      },
    }),
  );
  assertEquals(result, {
    state: "DELETED",
    uploaded_file_id: input.uploaded_file_id,
  });
  assertEquals(events, [
    {
      client: "human",
      name: "authorize_internal_e2e_accepted_file_cleanup_v1",
      args: {
        p_run_id: input.run_id,
        p_request_id: input.request_id,
        p_upload_request_id: input.upload_request_id,
        p_uploaded_file_id: input.uploaded_file_id,
        p_idempotency_key: input.idempotency_key,
      },
    },
    {
      client: "service",
      operation: "remove",
      bucket: "customer-request-quarantine",
      paths: [
        `requests/${input.request_id}/uploads/${input.upload_request_id}/files/${input.uploaded_file_id}.png`,
      ],
    },
    {
      client: "human",
      name: "finalize_internal_e2e_accepted_file_cleanup_v1",
      args: {
        p_cleanup_authorization_id: "a1800000-0000-4000-8000-000000000045",
        p_idempotency_key: input.idempotency_key,
      },
    },
  ]);
});

Deno.test("internal E2E accepted-file cleanup never finalizes after Storage removal failure", async () => {
  const rpcNames: string[] = [];
  let removalCalls = 0;
  let error: Error | null = null;
  try {
    await executeCallerJwtInternalE2EAcceptedFileCleanupAction(
      jwt,
      {
        action: "cleanup_internal_e2e_accepted_file",
        run_id: "a1800000-0000-4000-8000-000000000050",
        request_id: "a1800000-0000-4000-8000-000000000051",
        upload_request_id: "a1800000-0000-4000-8000-000000000052",
        uploaded_file_id: "a1800000-0000-4000-8000-000000000053",
        idempotency_key: "a1800000-0000-4000-8000-000000000054",
      },
      () => ({
        rpc: async (name: string, _args: Record<string, unknown>) => {
          rpcNames.push(name);
          return {
            data: {
              state: "AUTHORIZED",
              cleanup_authorization_id: "a1800000-0000-4000-8000-000000000055",
              storage_bucket_id: "customer-request-quarantine",
              storage_object_path:
                "requests/a1800000-0000-4000-8000-000000000051/uploads/a1800000-0000-4000-8000-000000000052/files/a1800000-0000-4000-8000-000000000053.png",
            },
            error: null,
          };
        },
      }),
      () => ({
        storage: {
          from: (_bucket: string) => ({
            remove: async (_paths: string[]) => {
              removalCalls += 1;
              return {
                data: null,
                error: { message: "STORAGE_REMOVE_FAILED" },
              };
            },
          }),
        },
      }),
    );
  } catch (caught) {
    error = caught as Error;
  }
  assertEquals(error?.message, "STORAGE_REMOVE_FAILED");
  assertEquals(removalCalls, 1);
  assertEquals(rpcNames, ["authorize_internal_e2e_accepted_file_cleanup_v1"]);
});

Deno.test("internal E2E finalization requires a terminal state and revision", async () => {
  const harness = dependencies();
  const valid = await handleCommercialOperator(
    request({
      action: "finalize_internal_e2e_run",
      run_id: "a1800000-0000-4000-8000-000000000020",
      terminal_status: "PASSED",
      expected_revision: 0,
      idempotency_key: "a1800000-0000-4000-8000-000000000021",
    }),
    harness.deps,
  );
  assertEquals(valid.status, 200);
  const active = await handleCommercialOperator(
    request({
      action: "finalize_internal_e2e_run",
      run_id: "a1800000-0000-4000-8000-000000000020",
      terminal_status: "ACTIVE",
      expected_revision: 0,
      idempotency_key: "a1800000-0000-4000-8000-000000000022",
    }),
    harness.deps,
  );
  assertEquals(active.status, 400);
  assertEquals(harness.calls.length, 1);
});

Deno.test("v2 list preserves preflight verify core sign order and hides raw position", async () => {
  const harness = dependencies();
  const signed = await signOperatorCursor(
    {
      dossierDate: "2099-01-03T10:20:30+00:00",
      quoteRequestId: userId,
    },
    cursorRequest(v2Input),
    { now: 4_102_444_800_000, secret: cursorSecret },
  );
  const response = await handleCommercialOperator(
    request({ ...v2Input, cursor: signed }),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(harness.events, ["preflight", "verify", "core", "sign"]);
  const body = await response.json();
  assertEquals(Array.isArray(body.result.items), true);
  assertEquals(body.result.has_more, true);
  assertEquals(typeof body.result.next_cursor, "string");
  assertEquals("next_position" in body.result, false);
});

Deno.test("v2 list rejects forged position, changed search/filter, expired, and malformed cursors before core", async () => {
  const signed = await signOperatorCursor(
    {
      dossierDate: "2099-01-03T10:20:30+00:00",
      quoteRequestId: userId,
    },
    cursorRequest(v2Input),
    { now: 4_102_444_800_000, secret: cursorSecret },
  );
  const parts = signed.split(".");
  const payloadPart = parts[1].replace(/-/g, "+").replace(/_/g, "/");
  const payload = JSON.parse(
    atob(payloadPart.padEnd(Math.ceil(payloadPart.length / 4) * 4, "=")),
  );
  payload.dossierDate = "2999-01-01T00:00:00+00:00";
  payload.quoteRequestId = "ffffffff-ffff-4fff-8fff-ffffffffffff";
  const binary = JSON.stringify(payload);
  const forged = `v1.${
    btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")
  }.${parts[2]}`;
  for (
    const input of [
      { ...v2Input, cursor: forged },
      { ...v2Input, search: "Changed", cursor: signed },
      { ...v2Input, zone: "ACTIVE", cursor: signed },
      { ...v2Input, cursor: "malformed" },
    ]
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request(input),
      harness.deps,
    );
    assertEquals(response.status, 400);
    assertEquals(harness.events.includes("core"), false);
  }
  const expiredHarness = dependencies({
    verifyOperatorCursor: async (
      cursor: string,
      input: Record<string, unknown>,
    ) =>
      await verifyOperatorCursor(cursor, cursorRequest(input), {
        now: 4_102_444_800_000 + OPERATOR_CURSOR_TTL_MS,
        secret: cursorSecret,
      }),
  });
  assertEquals(
    (await handleCommercialOperator(
      request({ ...v2Input, cursor: signed }),
      expiredHarness.deps,
    )).status,
    400,
  );
});

Deno.test("v2 facets uses preflight and actor-bound core without cursor signing", async () => {
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({
      action: "get_application_facets_v2",
      zone: "ACTIVE_ARCHIVED",
      operational_status: null,
      request_kind: null,
      search: null,
    }),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(harness.events, ["preflight", "facets"]);
});

Deno.test("v2 list fails closed for unauthorized actor, missing secret, and invalid DB core response", async () => {
  const unauthorized = dependencies({
    authorizeApplicationReader: async () => {
      throw new Error("APPLICATION_SCOPE_DENIED");
    },
  });
  assertEquals(
    (await handleCommercialOperator(request(v2Input), unauthorized.deps))
      .status,
    403,
  );

  const missingSecret = dependencies({
    signOperatorCursor: async (
      position: Record<string, string>,
      input: Record<string, unknown>,
    ) =>
      await signOperatorCursor(
        {
          dossierDate: position.dossier_date,
          quoteRequestId: position.quote_request_id,
        },
        cursorRequest(input),
        { secret: "short" },
      ),
  });
  assertEquals(
    (await handleCommercialOperator(request(v2Input), missingSecret.deps))
      .status,
    500,
  );

  const invalidCore = dependencies({
    executeApplicationListV2: async () => ({
      items: [],
      has_more: true,
      next_position: null,
    }),
  });
  assertEquals(
    (await handleCommercialOperator(request(v2Input), invalidCore.deps)).status,
    500,
  );
});

Deno.test("Customer Requests actions accept only bounded operational input", async () => {
  const requestId = "a1800000-0000-4000-8000-000000000070";
  const idempotencyKey = "a1800000-0000-4000-8000-000000000071";
  for (
    const [body, input] of [
      [
        {
          action: "list_customer_requests_for_dossier",
          dossier_reference: " lws-aan-2099-0001 ",
        },
        {
          action: "list_customer_requests_for_dossier",
          dossier_reference: "LWS-AAN-2099-0001",
          cursor: null,
          limit: 25,
        },
      ],
      [
        { action: "get_customer_request", request_id: requestId },
        { action: "get_customer_request", request_id: requestId },
      ],
      [
        {
          action: "transition_customer_request",
          request_id: requestId,
          command_type: "START",
          expected_revision: 2,
          idempotency_key: idempotencyKey,
        },
        {
          action: "transition_customer_request",
          request_id: requestId,
          command_type: "START",
          expected_revision: 2,
          idempotency_key: idempotencyKey,
        },
      ],
    ] as const
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request(body),
      harness.deps,
    );
    assertEquals(response.status, 200);
    assertEquals(harness.calls, [{ jwt, input }]);
  }

  for (
    const invalid of [
      {
        action: "list_customer_requests_for_dossier",
        dossier_reference: "LWS-AAN-2099-0001",
        quote_request_id: requestId,
      },
      {
        action: "list_customer_requests_for_dossier",
        dossier_reference: "LWS-AAN-2099-0001",
        customer_id: requestId,
      },
      {
        action: "list_customer_requests_for_dossier",
        dossier_reference: "LWS-AAN-2099-0001",
        role: "operator",
      },
      {
        action: "list_customer_requests_for_dossier",
        dossier_reference: "invalid",
      },
      {
        action: "list_customer_requests_for_dossier",
        dossier_reference: "LWS-AAN-2099-0001",
        cursor: "",
      },
      {
        action: "list_customer_requests_for_dossier",
        dossier_reference: "LWS-AAN-2099-0001",
        limit: 101,
      },
      { action: "get_customer_request", request_id: "invalid" },
      {
        action: "get_customer_request",
        request_id: requestId,
        project_id: requestId,
      },
      {
        action: "transition_customer_request",
        request_id: requestId,
        command_type: "TRIAGE",
        expected_revision: 2,
        idempotency_key: idempotencyKey,
      },
      {
        action: "transition_customer_request",
        request_id: requestId,
        command_type: "START",
        expected_revision: -1,
        idempotency_key: idempotencyKey,
      },
      {
        action: "transition_customer_request",
        request_id: requestId,
        command_type: "START",
        expected_revision: 2,
        idempotency_key: idempotencyKey,
        payload: {},
      },
    ]
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request(invalid),
      harness.deps,
    );
    assertEquals(response.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("SDF Customer Request create accepts no client authority fields", async () => {
  const quoteRequestId = "a1800000-0000-4000-8000-000000000072";
  const idempotencyKey = "a1800000-0000-4000-8000-000000000073";
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({
      action: "create_sdf_customer_request",
      quote_request_id: quoteRequestId,
      idempotency_key: idempotencyKey,
      request_type: "FILE_DELIVERY",
      title: " Bronbestanden aanleveren ",
      description: " Lever de bronbestanden aan. ",
      priority: "NORMAL",
    }),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(harness.calls, [{
    jwt,
    input: {
      action: "create_sdf_customer_request",
      quote_request_id: quoteRequestId,
      idempotency_key: idempotencyKey,
      request_type: "FILE_DELIVERY",
      title: "Bronbestanden aanleveren",
      description: "Lever de bronbestanden aan.",
      priority: "NORMAL",
    },
  }]);

  for (
    const authorityField of [
      { request_kind: "slimme_documentenflow" },
      { customer_id: quoteRequestId },
      { project_id: quoteRequestId },
      { submitted_at: "2099-01-01T00:00:00Z" },
    ]
  ) {
    const denied = dependencies();
    const deniedResponse = await handleCommercialOperator(
      request({
        action: "create_sdf_customer_request",
        quote_request_id: quoteRequestId,
        idempotency_key: idempotencyKey,
        request_type: "FILE_DELIVERY",
        title: "Bronbestanden",
        description: "Lever de bronbestanden aan.",
        priority: null,
        ...authorityField,
      }),
      denied.deps,
    );
    assertEquals(deniedResponse.status, 400);
    assertEquals(denied.calls.length, 0);
  }
});

Deno.test("SDF Customer Request create uses the exact caller-scoped RPC", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const input = {
    action: "create_sdf_customer_request" as const,
    quote_request_id: "a1800000-0000-4000-8000-000000000072",
    idempotency_key: "a1800000-0000-4000-8000-000000000073",
    request_type: "FILE_DELIVERY",
    title: "Bronbestanden aanleveren",
    description: "Lever de bronbestanden aan.",
    priority: "NORMAL" as const,
  };
  const result = await executeCallerJwtCustomerRequestAction(
    jwt,
    input,
    (token: string) => ({
      rpc: (name: string, args: Record<string, unknown>) => {
        assertEquals(token, jwt);
        calls.push({ name, args });
        return Promise.resolve({
          data: { request_id: "a1800000-0000-4000-8000-000000000074" },
          error: null,
        });
      },
    }),
  );
  assertEquals(result, { request_id: "a1800000-0000-4000-8000-000000000074" });
  assertEquals(calls, [{
    name: "create_sdf_customer_request_v1",
    args: {
      p_quote_request_id: input.quote_request_id,
      p_idempotency_key: input.idempotency_key,
      p_request_type: input.request_type,
      p_title: input.title,
      p_description: input.description,
      p_priority: input.priority,
    },
  }]);
});

Deno.test("Customer Requests transport uses exact caller-scoped RPCs", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  await executeCustomerRequestTransport(client, {
    action: "list_customer_requests_for_dossier",
    dossier_reference: "LWS-AAN-2099-0001",
    cursor: "aabb",
    limit: 25,
  });
  await executeCustomerRequestTransport(client, {
    action: "get_customer_request",
    request_id: "a1800000-0000-4000-8000-000000000070",
  });
  await executeCustomerRequestTransport(client, {
    action: "transition_customer_request",
    request_id: "a1800000-0000-4000-8000-000000000070",
    command_type: "RESUME",
    expected_revision: 4,
    idempotency_key: "a1800000-0000-4000-8000-000000000071",
  });
  assertEquals(calls, [
    {
      name: "get_customer_requests_for_dossier_v1",
      args: {
        p_dossier_reference: "LWS-AAN-2099-0001",
        p_cursor: "aabb",
        p_limit: 25,
      },
    },
    {
      name: "get_customer_request_v1",
      args: { p_request_id: "a1800000-0000-4000-8000-000000000070" },
    },
    {
      name: "transition_customer_request_v1",
      args: {
        p_request_id: "a1800000-0000-4000-8000-000000000070",
        p_command_type: "RESUME",
        p_expected_revision: 4,
        p_idempotency_key: "a1800000-0000-4000-8000-000000000071",
        p_payload: {},
      },
    },
  ]);
});

Deno.test("Customer Requests index dispatch constructs only a caller JWT client", async () => {
  const clientForCalls: string[] = [];
  const rpcCalls: string[] = [];
  const result = await executeCallerJwtCustomerRequestAction(jwt, {
    action: "get_customer_request",
    request_id: "a1800000-0000-4000-8000-000000000070",
  }, (token: string) => {
    clientForCalls.push(token);
    return {
      rpc: (name: string) => {
        rpcCalls.push(name);
        return Promise.resolve({
          data: { request_id: "a1800000-0000-4000-8000-000000000070" },
          error: null,
        });
      },
    };
  });
  assertEquals(clientForCalls, [jwt]);
  assertEquals(rpcCalls, ["get_customer_request_v1"]);
  assertEquals(result, { request_id: "a1800000-0000-4000-8000-000000000070" });
});

Deno.test("Customer Request upload-link actions accept only authority-minimal input", async () => {
  const requestId = "a1800000-0000-4000-8000-000000000070";
  const uploadRequestId = "a1800000-0000-4000-8000-000000000072";
  const idempotencyKey = "a1800000-0000-4000-8000-000000000071";
  for (
    const [body, input] of [
      [
        {
          action: "create_customer_request_upload_link",
          request_id: requestId,
          idempotency_key: idempotencyKey,
        },
        {
          action: "create_customer_request_upload_link",
          request_id: requestId,
          idempotency_key: idempotencyKey,
        },
      ],
      [
        {
          action: "revoke_customer_request_upload_link",
          upload_request_id: uploadRequestId,
          reason: " Klant vroeg intrekking ",
          idempotency_key: idempotencyKey,
        },
        {
          action: "revoke_customer_request_upload_link",
          upload_request_id: uploadRequestId,
          reason: "Klant vroeg intrekking",
          idempotency_key: idempotencyKey,
        },
      ],
    ] as const
  ) {
    const harness = dependencies();
    assertEquals(
      (await handleCommercialOperator(request(body), harness.deps)).status,
      200,
    );
    assertEquals(harness.calls, [{ jwt, input }]);
  }
  for (
    const invalid of [
      {
        action: "create_customer_request_upload_link",
        request_id: requestId,
        idempotency_key: idempotencyKey,
        customer_id: requestId,
      },
      {
        action: "create_customer_request_upload_link",
        request_id: "invalid",
        idempotency_key: idempotencyKey,
      },
      {
        action: "revoke_customer_request_upload_link",
        upload_request_id: uploadRequestId,
        reason: "",
        idempotency_key: idempotencyKey,
      },
      {
        action: "revoke_customer_request_upload_link",
        upload_request_id: uploadRequestId,
        request_id: requestId,
        reason: "x",
        idempotency_key: idempotencyKey,
      },
    ]
  ) {
    const harness = dependencies();
    assertEquals(
      (await handleCommercialOperator(request(invalid), harness.deps)).status,
      400,
    );
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("Customer Request upload-link create is digest-only and retry-stable", async () => {
  Deno.env.set("CUSTOMER_REQUEST_UPLOAD_CAPABILITY_SECRET", "u".repeat(32));
  Deno.env.set("SITE_URL", "https://lorenzowebsolutions.be");
  const requestId = "a1800000-0000-4000-8000-000000000070";
  const idempotencyKey = "a1800000-0000-4000-8000-000000000071";
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const clientFor = (token: string) => ({
    rpc: async (name: string, args: Record<string, unknown>) => {
      assertEquals(token, jwt);
      calls.push({ name, args });
      return {
        data: {
          state: "ACTIVE",
          upload_request_id: "a1800000-0000-4000-8000-000000000072",
          expires_at: "2099-01-01T00:00:00Z",
        },
        error: null,
      };
    },
  });
  const input = {
    action: "create_customer_request_upload_link" as const,
    request_id: requestId,
    idempotency_key: idempotencyKey,
  };
  const first = await executeCallerJwtCustomerRequestUploadAction(
    jwt,
    input,
    clientFor,
  );
  const second = await executeCallerJwtCustomerRequestUploadAction(
    jwt,
    input,
    clientFor,
  );
  assertEquals(first, second);
  assertEquals(calls.map((call) => call.name), [
    "create_customer_request_upload_request_v1",
    "create_customer_request_upload_request_v1",
  ]);
  assertEquals(calls[0].args.p_token_digest, calls[1].args.p_token_digest);
  assertEquals(typeof calls[0].args.p_token_digest, "string");
  assertEquals(
    JSON.stringify(calls).includes(
      new URL((first as Record<string, string>).upload_url).hash.slice(7),
    ),
    false,
  );
});

Deno.test("Customer Request upload-link revoke uses only caller JWT and capability id", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await executeCallerJwtCustomerRequestUploadAction(
    jwt,
    {
      action: "revoke_customer_request_upload_link",
      upload_request_id: "a1800000-0000-4000-8000-000000000072",
      reason: "Klant vroeg intrekking",
      idempotency_key: "a1800000-0000-4000-8000-000000000071",
    },
    (token: string) => ({
      rpc: async (name: string, args: Record<string, unknown>) => {
        assertEquals(token, jwt);
        calls.push({ name, args });
        return { data: { state: "REVOKED" }, error: null };
      },
    }),
  );
  assertEquals(result, { state: "REVOKED" });
  assertEquals(calls, [{
    name: "revoke_customer_request_upload_request_v1",
    args: {
      p_upload_request_id: "a1800000-0000-4000-8000-000000000072",
      p_reason: "Klant vroeg intrekking",
      p_idempotency_key: "a1800000-0000-4000-8000-000000000071",
    },
  }]);
});

Deno.test("Customer Request upload promotion accepts only one canonical source id", async () => {
  const uploadedFileId = "a1800000-0000-4000-8000-000000000073";
  const valid = dependencies();
  const response = await handleCommercialOperator(
    request({
      action: "promote_customer_request_upload_to_document_inbox",
      uploaded_file_id: uploadedFileId,
    }),
    valid.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(valid.calls, [{
    jwt,
    input: {
      action: "promote_customer_request_upload_to_document_inbox",
      uploaded_file_id: uploadedFileId,
    },
  }]);

  for (
    const extra of [
      { quote_request_id: userId },
      { customer_request_id: userId },
      { source_type: "CUSTOMER_REQUEST_UPLOAD" },
      { bucket: "supplier-documents" },
      { path: "documents/forged.pdf" },
      { operator_id: userId },
    ]
  ) {
    const harness = dependencies();
    const denied = await handleCommercialOperator(
      request({
        action: "promote_customer_request_upload_to_document_inbox",
        uploaded_file_id: uploadedFileId,
        ...extra,
      }),
      harness.deps,
    );
    assertEquals(denied.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("Customer Request upload promotion copies privately then finalizes under caller JWT", async () => {
  const uploadedFileId = "a1800000-0000-4000-8000-000000000073";
  const inboxItemId = "a1800000-0000-4000-8000-000000000074";
  const bytes = new TextEncoder().encode("%PDF-private-customer-upload");
  const shaBuffer = await crypto.subtle.digest("SHA-256", bytes);
  const sha256 = [...new Uint8Array(shaBuffer)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  const sourcePath =
    `requests/${userId}/uploads/${userId}/files/${uploadedFileId}.pdf`;
  const destinationPath = `documents/${sha256}.pdf`;
  const rpcCalls: string[] = [];
  const storageCalls: string[] = [];
  const callerClient = {
    rpc: async (name: string) => {
      rpcCalls.push(name);
      if (name === "authorize_customer_request_upload_inbox_promotion_v1") {
        return {
          data: {
            state: "AUTHORIZED",
            uploaded_file_id: uploadedFileId,
            customer_request_id: "a1800000-0000-4000-8000-000000000075",
            quote_request_id: "a1800000-0000-4000-8000-000000000076",
            source_bucket_id: "customer-request-quarantine",
            source_object_path: sourcePath,
            destination_bucket_id: "supplier-documents",
            destination_object_path: destinationPath,
            original_file_name: "brief.pdf",
            mime_type: "application/pdf",
            byte_count: bytes.byteLength,
            sha256,
          },
          error: null,
        };
      }
      return {
        data: {
          state: "PROMOTED",
          uploaded_file_id: uploadedFileId,
          document_inbox_item_id: inboxItemId,
          status: "RECEIVED",
          replayed: false,
        },
        error: null,
      };
    },
  };
  const service = {
    rpc: async (name: string) => {
      rpcCalls.push(name);
      return { data: true, error: null };
    },
    storage: {
      from: (bucket: string) => ({
        download: async (path: string) => {
          storageCalls.push(`download:${bucket}:${path}`);
          return {
            data: new Blob([bytes], { type: "application/pdf" }),
            error: null,
          };
        },
        upload: async (path: string, _bytes: Uint8Array, options: unknown) => {
          storageCalls.push(
            `upload:${bucket}:${path}:${JSON.stringify(options)}`,
          );
          return { data: {}, error: null };
        },
      }),
    },
  };
  const result = await executeCustomerRequestUploadInboxPromotionAction(
    jwt,
    {
      action: "promote_customer_request_upload_to_document_inbox",
      uploaded_file_id: uploadedFileId,
    },
    (token) => {
      assertEquals(token, jwt);
      return callerClient;
    },
    () => service,
  );
  assertEquals(result, {
    uploaded_file_id: uploadedFileId,
    document_inbox_item_id: inboxItemId,
    status: "RECEIVED",
    replayed: false,
  });
  assertEquals(rpcCalls, [
    "authorize_customer_request_upload_inbox_promotion_v1",
    "finalize_supplier_document_upload_object_v1",
    "finalize_customer_request_upload_inbox_promotion_v1",
  ]);
  assertEquals(storageCalls, [
    `download:customer-request-quarantine:${sourcePath}`,
    `upload:supplier-documents:${destinationPath}:{"contentType":"application/pdf","upsert":false}`,
  ]);
  assertEquals(JSON.stringify(rpcCalls).includes("extract"), false);
  assertEquals(JSON.stringify(rpcCalls).includes("provider"), false);
});

Deno.test("Customer Request upload promotion replays without storage and fails closed on corrupt source", async () => {
  const uploadedFileId = "a1800000-0000-4000-8000-000000000073";
  let serviceCalls = 0;
  const replay = await executeCustomerRequestUploadInboxPromotionAction(
    jwt,
    {
      action: "promote_customer_request_upload_to_document_inbox",
      uploaded_file_id: uploadedFileId,
    },
    () => ({
      rpc: async () => ({
        data: {
          state: "PROMOTED",
          uploaded_file_id: uploadedFileId,
          document_inbox_item_id: "a1800000-0000-4000-8000-000000000074",
          status: "RECEIVED",
          replayed: true,
        },
        error: null,
      }),
    }),
    () => {
      serviceCalls += 1;
      throw new Error("service must not be constructed for replay");
    },
  );
  assertEquals((replay as Record<string, unknown>).replayed, true);
  assertEquals(serviceCalls, 0);

  await assertRejects(
    () =>
      executeCustomerRequestUploadInboxPromotionAction(
        jwt,
        {
          action: "promote_customer_request_upload_to_document_inbox",
          uploaded_file_id: uploadedFileId,
        },
        () => ({
          rpc: async () => ({
            data: {
              state: "AUTHORIZED",
              uploaded_file_id: uploadedFileId,
              customer_request_id: userId,
              quote_request_id: "a1800000-0000-4000-8000-000000000076",
              source_bucket_id: "customer-request-quarantine",
              source_object_path: "requests/source.pdf",
              destination_bucket_id: "supplier-documents",
              destination_object_path: `documents/${"a".repeat(64)}.pdf`,
              mime_type: "application/pdf",
              byte_count: 5,
              sha256: "a".repeat(64),
            },
            error: null,
          }),
        }),
        () => ({
          rpc: async () => ({ data: true, error: null }),
          storage: {
            from: () => ({
              download: async () => ({
                data: new Blob(["wrong"], { type: "application/pdf" }),
                error: null,
              }),
              upload: async () => ({ data: {}, error: null }),
            }),
          },
        }),
      ),
    Error,
    "CUSTOMER_REQUEST_UPLOAD_SOURCE_CONTENT_MISMATCH",
  );
});

Deno.test("Customer Requests reject service role and expose stable error envelopes", async () => {
  const serviceJwt = createUnsignedTestJwt({
    sub: userId,
    role: "service_role",
    exp: 4102444800,
  });
  const serviceHarness = dependencies();
  const serviceResponse = await handleCommercialOperator(
    request({
      action: "get_customer_request",
      request_id: "a1800000-0000-4000-8000-000000000070",
    }, serviceJwt),
    serviceHarness.deps,
  );
  assertEquals(serviceResponse.status, 401);
  assertEquals((await serviceResponse.json()).code, "HUMAN_JWT_REQUIRED");
  assertEquals(serviceHarness.calls.length, 0);

  for (
    const [databaseCode, status, responseCode] of [
      ["CUSTOMER_REQUEST_ACCESS_DENIED", 403, "OPERATOR_NOT_AUTHORIZED"],
      ["INVALID_CUSTOMER_REQUEST_LIST_CURSOR", 400, "INVALID_REQUEST"],
      ["CONCURRENT_MODIFICATION", 409, "CONCURRENT_MODIFICATION"],
      ["INVALID_CUSTOMER_REQUEST_TRANSITION", 409, "COMMAND_REJECTED"],
      ["UNEXPECTED_CUSTOMER_REQUEST_FAILURE", 500, "INTERNAL_ERROR"],
    ] as const
  ) {
    const harness = dependencies({
      executeApplicationAction: async () => {
        throw new Error(databaseCode);
      },
    });
    const response = await handleCommercialOperator(
      request({
        action: "get_customer_request",
        request_id: "a1800000-0000-4000-8000-000000000070",
      }),
      harness.deps,
    );
    assertEquals(response.status, status);
    assertEquals((await response.json()).code, responseCode);
  }
});

Deno.test("current operator identity accepts only the fixed presentation action", async () => {
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({ action: "get_current_operator_identity" }),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(harness.calls, [{
    jwt,
    input: { action: "get_current_operator_identity" },
  }]);

  for (
    const extra of [{ operator_id: userId }, { role: "owner" }, {
      status: "ACTIVE",
    }, { email: "private@example.test" }]
  ) {
    const invalidHarness = dependencies();
    const invalidResponse = await handleCommercialOperator(
      request({ action: "get_current_operator_identity", ...extra }),
      invalidHarness.deps,
    );
    assertEquals(invalidResponse.status, 400);
    assertEquals(invalidHarness.calls.length, 0);
  }
});

Deno.test("current operator identity transport exposes only the safe projection", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await executeCurrentOperatorIdentityTransport({
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      return Promise.resolve({
        data: {
          display_name: "Current Operator",
          role: "operator",
          status: "ACTIVE",
        },
        error: null,
      });
    },
  });
  assertEquals(calls, [{ name: "get_current_operator_identity_v1", args: {} }]);
  assertEquals(result, {
    display_name: "Current Operator",
    role: "operator",
    status: "ACTIVE",
  });
  assertEquals(Object.keys(result), ["display_name", "role", "status"]);
});

Deno.test("current operator identity index dispatch constructs only a caller JWT client", async () => {
  const clientForCalls: string[] = [];
  const rpcCalls: string[] = [];
  const result = await executeCallerJwtCurrentOperatorIdentityAction(
    jwt,
    (token: string) => {
      clientForCalls.push(token);
      return {
        rpc: (name: string) => {
          rpcCalls.push(name);
          return Promise.resolve({
            data: { display_name: "Owner", role: "owner", status: "ACTIVE" },
            error: null,
          });
        },
      };
    },
  );
  assertEquals(clientForCalls, [jwt]);
  assertEquals(rpcCalls, ["get_current_operator_identity_v1"]);
  assertEquals(result, {
    display_name: "Owner",
    role: "owner",
    status: "ACTIVE",
  });
});

Deno.test("current operator identity errors use stable authorization envelopes", async () => {
  for (
    const databaseCode of [
      "UNKNOWN_OPERATOR",
      "OPERATOR_DISABLED",
      "OPERATOR_REVOKED",
      "OPERATOR_INACTIVE",
    ]
  ) {
    const harness = dependencies({
      executeApplicationAction: async () => {
        throw new Error(databaseCode);
      },
    });
    const response = await handleCommercialOperator(
      request({ action: "get_current_operator_identity" }),
      harness.deps,
    );
    assertEquals(response.status, 403);
    assertEquals(await response.json(), {
      ok: false,
      code: "OPERATOR_NOT_AUTHORIZED",
    });
  }
});

Deno.test("quotation business draft accepts only the exact authority-minimal request", async () => {
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request(quotationBusinessRequest),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(harness.calls, [{ jwt, input: quotationBusinessRequest }]);

  for (
    const invalid of [
      { ...quotationBusinessRequest, intake_id: undefined },
      { ...quotationBusinessRequest, intake_id: "bad" },
      { ...quotationBusinessRequest, expected_revision: undefined },
      { ...quotationBusinessRequest, expected_revision: -1 },
      { ...quotationBusinessRequest, idempotency_key: undefined },
      { ...quotationBusinessRequest, idempotency_key: "bad" },
      { ...quotationBusinessRequest, input: null },
      {
        ...quotationBusinessRequest,
        input: { ...quotationBusinessInput, commercial_lines: [] },
      },
      {
        ...quotationBusinessRequest,
        input: { ...quotationBusinessInput, validity_days: 366 },
      },
      {
        ...quotationBusinessRequest,
        input: {
          ...quotationBusinessInput,
          payment_schedule: { milestones: null },
        },
      },
      {
        ...quotationBusinessRequest,
        input: {
          ...quotationBusinessInput,
          discount: {
            discount_type: {},
            discount_value_minor: 0,
            discount_reason: null,
          },
        },
      },
      {
        ...quotationBusinessRequest,
        input: { ...quotationBusinessInput, seller_authority: {} },
      },
      {
        ...quotationBusinessRequest,
        input: { ...quotationBusinessInput, approval_hmac: "injected" },
      },
      { ...quotationBusinessRequest, actor_auth_user_id: userId },
      { ...quotationBusinessRequest, operator_id: userId },
    ]
  ) {
    const invalidHarness = dependencies();
    const invalidResponse = await handleCommercialOperator(
      request(invalid),
      invalidHarness.deps,
    );
    assertEquals(invalidResponse.status, 400);
    assertEquals(invalidHarness.calls.length, 0);
  }
});

Deno.test("quotation business draft rejects caller-selected terms authority", async () => {
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({
      ...quotationBusinessRequest,
      input: {
        ...quotationBusinessInput,
        terms_authority_id: "a1800000-0000-4000-8000-000000000099",
      },
    }),
    harness.deps,
  );
  assertEquals(response.status, 400);
  assertEquals(harness.calls.length, 0);
});

Deno.test("quotation business draft rejects caller-selected VAT authority", async () => {
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({
      ...quotationBusinessRequest,
      input: {
        ...quotationBusinessInput,
        vat_decision_authority_id: "a1800000-0000-4000-8000-000000000098",
      },
    }),
    harness.deps,
  );
  assertEquals(response.status, 400);
  assertEquals(harness.calls.length, 0);
});

Deno.test("quotation business draft transport uses verified actor and only its service RPC", async () => {
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const canonicalPayload = {
    contract_version: 1,
    totals: { total_gross_minor: 12100 },
  };
  const result = await executeQuotationBusinessDraftAction(
    userId,
    quotationBusinessRequest,
    {
      rpc: (name: string, args: Record<string, unknown>) => {
        rpcCalls.push({ name, args });
        return Promise.resolve({
          data: {
            approval_draft_id: "a1800000-0000-4000-8000-000000000085",
            business_revision: 1,
            canonical_payload: canonicalPayload,
            canonical_payload_sha256: "internal-hash",
            bindings: { internal: true },
            prepared_by_actor: "internal-actor",
            prepared_at: "2099-01-01T00:00:00Z",
            replayed: false,
          },
          error: null,
        });
      },
    },
  );
  assertEquals(rpcCalls, [{
    name: "upsert_quotation_business_draft_v2",
    args: {
      p_actor_auth_user_id: userId,
      p_intake_id: quotationBusinessRequest.intake_id,
      p_expected_revision: 0,
      p_idempotency_key: quotationBusinessRequest.idempotency_key,
      p_input: quotationBusinessInput,
    },
  }]);
  assertEquals(result, {
    approval_draft_id: "a1800000-0000-4000-8000-000000000085",
    business_revision: 1,
    canonical_payload: canonicalPayload,
    prepared_at: "2099-01-01T00:00:00Z",
    replayed: false,
  });
});

Deno.test("quotation business draft retries reuse the same validated route", async () => {
  const harness = dependencies();
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const response = await handleCommercialOperator(
      request(quotationBusinessRequest),
      harness.deps,
    );
    assertEquals(response.status, 200);
  }
  assertEquals(harness.calls, [
    { jwt, input: quotationBusinessRequest },
    { jwt, input: quotationBusinessRequest },
  ]);
});

Deno.test("quotation business draft preserves auth boundary and stable authority errors", async () => {
  const serviceJwt = createUnsignedTestJwt({
    sub: userId,
    role: "service_role",
    exp: 4102444800,
  });
  const serviceHarness = dependencies();
  const serviceResponse = await handleCommercialOperator(
    request(quotationBusinessRequest, serviceJwt),
    serviceHarness.deps,
  );
  assertEquals(serviceResponse.status, 401);
  assertEquals((await serviceResponse.json()).code, "HUMAN_JWT_REQUIRED");
  assertEquals(serviceHarness.calls.length, 0);

  for (
    const [databaseCode, status, responseCode] of [
      ["QUOTATION_BUSINESS_SCOPE_DENIED", 403, "OPERATOR_NOT_AUTHORIZED"],
      ["STALE_BUSINESS_REVISION", 409, "STALE_BUSINESS_REVISION"],
      ["IDEMPOTENCY_CONFLICT", 409, "IDEMPOTENCY_CONFLICT"],
      ["PRICING_INTEGRITY_INVALID", 409, "COMMAND_REJECTED"],
      ["UNEXPECTED_QUOTATION_FAILURE", 500, "INTERNAL_ERROR"],
    ] as const
  ) {
    const harness = dependencies({
      executeApplicationAction: async () => {
        throw new Error(databaseCode);
      },
    });
    const response = await handleCommercialOperator(
      request(quotationBusinessRequest),
      harness.deps,
    );
    assertEquals(response.status, status);
    assertEquals(await response.json(), { ok: false, code: responseCode });
  }
});

Deno.test("quotation business approval promotion accepts only authority-minimal input", async () => {
  const harness = dependencies();
  assertEquals(
    (await handleCommercialOperator(
      request(quotationPromotionRequest),
      harness.deps,
    )).status,
    200,
  );
  assertEquals(harness.calls, [{ jwt, input: quotationPromotionRequest }]);

  for (
    const authoritativeField of [
      "business_draft_id",
      "approval_id",
      "approval_payload",
      "payload_hash",
      "hmac",
      "integrity",
      "integrity_root",
      "terms",
      "vat",
      "seller",
      "pricing_authority",
    ]
  ) {
    const invalidHarness = dependencies();
    const invalid = {
      ...quotationPromotionRequest,
      [authoritativeField]: "injected",
    };
    assertEquals(
      (await handleCommercialOperator(request(invalid), invalidHarness.deps))
        .status,
      400,
    );
    assertEquals(invalidHarness.calls.length, 0);
  }
});

Deno.test("approved quotation issuance accepts only the dossier locator", async () => {
  const harness = dependencies();
  assertEquals(
    (await handleCommercialOperator(
      request(quotationIssuanceRequest),
      harness.deps,
    )).status,
    200,
  );
  assertEquals(harness.calls, [{ jwt, input: quotationIssuanceRequest }]);

  for (
    const invalid of [
      { action: quotationIssuanceRequest.action },
      { ...quotationIssuanceRequest, quote_request_id: "bad" },
      { ...quotationIssuanceRequest, approval_id: userId },
      { ...quotationIssuanceRequest, recipient_email: "injected@example.test" },
      { ...quotationIssuanceRequest, template_id: "injected" },
      { ...quotationIssuanceRequest, total_gross_minor: 1 },
      { ...quotationIssuanceRequest, status: "SENT" },
      { ...quotationIssuanceRequest, idempotency_key: userId },
      { ...quotationIssuanceRequest, operator_id: userId },
    ]
  ) {
    const invalidHarness = dependencies();
    assertEquals(
      (await handleCommercialOperator(request(invalid), invalidHarness.deps))
        .status,
      400,
    );
    assertEquals(invalidHarness.calls.length, 0);
  }
});

Deno.test("SDF quotation issuance accepts only frozen authority locators", async () => {
  const harness = dependencies();
  assertEquals(
    (await handleCommercialOperator(request(sdfQuotationIssuanceRequest), harness.deps)).status,
    200,
  );
  assertEquals(harness.calls, [{ jwt, input: sdfQuotationIssuanceRequest }]);

  for (const invalid of [
    { ...sdfQuotationIssuanceRequest, approval_version: 0 },
    { ...sdfQuotationIssuanceRequest, approval_sha256: "bad" },
    { ...sdfQuotationIssuanceRequest, generation_contract_version: 2 },
    { ...sdfQuotationIssuanceRequest, admin_access_token: "injected" },
    { ...sdfQuotationIssuanceRequest, template_id: "injected" },
    { ...sdfQuotationIssuanceRequest, total_gross_minor: 1 },
    { ...sdfQuotationIssuanceRequest, recipient_email: "injected@example.test" },
    { ...sdfQuotationIssuanceRequest, delivery_status: "SENT" },
  ]) {
    const invalidHarness = dependencies();
    assertEquals((await handleCommercialOperator(request(invalid), invalidHarness.deps)).status, 400);
    assertEquals(invalidHarness.calls.length, 0);
  }
});

Deno.test("SDF delivery preparation accepts only frozen authority and artifact identity", async () => {
  const harness = dependencies();
  assertEquals(
    (await handleCommercialOperator(
      request(sdfQuotationDeliveryPreparationRequest),
      harness.deps,
    )).status,
    200,
  );
  assertEquals(harness.calls, [{
    jwt,
    input: sdfQuotationDeliveryPreparationRequest,
  }]);

  for (const requiredField of [
    "business_draft_id",
    "approval_id",
    "approval_version",
    "approval_sha256",
    "issuance_id",
    "artifact_id",
    "artifact_sha256",
    "artifact_bytes",
  ] as const) {
    const { [requiredField]: _omitted, ...invalid } =
      sdfQuotationDeliveryPreparationRequest;
    const invalidHarness = dependencies();
    assertEquals(
      (await handleCommercialOperator(request(invalid), invalidHarness.deps))
        .status,
      400,
    );
    assertEquals(invalidHarness.calls.length, 0);
  }

  for (const invalid of [
    { ...sdfQuotationDeliveryPreparationRequest, issuance_id: "bad" },
    { ...sdfQuotationDeliveryPreparationRequest, artifact_id: "bad" },
    { ...sdfQuotationDeliveryPreparationRequest, approval_sha256: "bad" },
    { ...sdfQuotationDeliveryPreparationRequest, artifact_sha256: "bad" },
    { ...sdfQuotationDeliveryPreparationRequest, artifact_bytes: 0 },
    { ...sdfQuotationDeliveryPreparationRequest, admin_access_token: "injected" },
    { ...sdfQuotationDeliveryPreparationRequest, token_digest: "c".repeat(64) },
    { ...sdfQuotationDeliveryPreparationRequest, encrypted_token: "injected" },
    { ...sdfQuotationDeliveryPreparationRequest, recipient_email: "injected@example.test" },
    { ...sdfQuotationDeliveryPreparationRequest, template_id: "injected" },
    { ...sdfQuotationDeliveryPreparationRequest, delivery_status: "SENT" },
    { ...sdfQuotationDeliveryPreparationRequest, requested_expires_at: "2099-01-01T00:00:00Z" },
  ]) {
    const invalidHarness = dependencies();
    assertEquals(
      (await handleCommercialOperator(request(invalid), invalidHarness.deps))
        .status,
      400,
    );
    assertEquals(invalidHarness.calls.length, 0);
  }
});

Deno.test("SDF delivery preparation maps owner denial without masking internal failures", async () => {
  const ownerDenied = await handleCommercialOperator(
    request(sdfQuotationDeliveryPreparationRequest),
    dependencies({
      executeApplicationAction: async () => {
        throw new Error("OWNER_REQUIRED");
      },
    }).deps,
  );
  assertEquals(ownerDenied.status, 403);
  assertEquals((await ownerDenied.json()).code, "OPERATOR_NOT_AUTHORIZED");

  const internalFailure = await handleCommercialOperator(
    request(sdfQuotationDeliveryPreparationRequest),
    dependencies({
      executeApplicationAction: async () => {
        throw new Error("UNEXPECTED_SDF_PREPARATION_FAILURE");
      },
    }).deps,
  );
  assertEquals(internalFailure.status, 500);
  assertEquals((await internalFailure.json()).code, "INTERNAL_ERROR");
});

Deno.test("SDF delivery send accepts only frozen authority identity", async () => {
  const harness = dependencies();
  const accepted = await handleCommercialOperator(
    request(sdfQuotationDeliverySendRequest),
    harness.deps,
  );
  assertEquals(accepted.status, 200);
  assertEquals(harness.calls, [{ jwt, input: sdfQuotationDeliverySendRequest }]);

  for (const forbidden of [
    { recipient_email: "injected@example.test" },
    { template: "INJECTED" },
    { token: "injected" },
    { encrypted_token: "injected" },
    { acceptance_url: "https://example.test/injected" },
    { idempotency_key: "a1800000-0000-4000-8000-000000000099" },
    { admin_access_token: "injected" },
    { attachment: "injected" },
  ]) {
    const invalidHarness = dependencies();
    const response = await handleCommercialOperator(
      request({ ...sdfQuotationDeliverySendRequest, ...forbidden }),
      invalidHarness.deps,
    );
    assertEquals(response.status, 400);
    assertEquals(invalidHarness.calls.length, 0);
  }

  const ownerDenied = await handleCommercialOperator(
    request(sdfQuotationDeliverySendRequest),
    dependencies({
      executeApplicationAction: async () => {
        throw new Error("OWNER_REQUIRED");
      },
    }).deps,
  );
  assertEquals(ownerDenied.status, 403);
  assertEquals((await ownerDenied.json()).code, "OPERATOR_NOT_AUTHORIZED");
});

Deno.test("approved quotation issuance exposes stable stage errors", async () => {
  for (
    const [internalCode, status, publicCode] of [
      ["QUOTATION_ORCHESTRATION_SCOPE_DENIED", 403, "OPERATOR_NOT_AUTHORIZED"],
      ["APPROVAL_NOT_FOUND", 404, "QUOTATION_APPROVAL_NOT_FOUND"],
      ["QUOTATION_ADMIN_CAPABILITY_UNAVAILABLE", 409, "QUOTATION_NOT_ISSUABLE"],
      ["APPROVAL_INTEGRITY_INVALID", 409, "QUOTATION_NOT_ISSUABLE"],
      ["QUOTATION_VAT_BINDING_REQUIRED", 409, "QUOTATION_NOT_ISSUABLE"],
      ["QUOTATION_TEMPLATE_HASH_INVALID", 500, "QUOTATION_GENERATION_FAILED"],
      ["QUOTATION_RENDER_INVALID", 500, "QUOTATION_GENERATION_FAILED"],
      ["QUOTATION_ARTIFACT_UPLOAD_FAILED", 500, "QUOTATION_ARCHIVE_FAILED"],
      ["QUOTATION_ARTIFACT_ARCHIVE_INVALID", 500, "QUOTATION_ARCHIVE_FAILED"],
      ["QUOTATION_DELIVERY_FAILED", 502, "QUOTATION_DELIVERY_FAILED"],
    ] as const
  ) {
    const harness = dependencies({
      executeApplicationAction: async () => {
        throw new Error(internalCode);
      },
    });
    const response = await handleCommercialOperator(
      request(quotationIssuanceRequest),
      harness.deps,
    );
    assertEquals(response.status, status);
    assertEquals(await response.json(), { ok: false, code: publicCode });
  }
});

Deno.test("quotation business approval CREATE signs resolved authority and calls only promotion RPCs", async () => {
  const approvalId = "a1800000-0000-4000-8000-000000000087";
  const secret = "create-secret-that-is-at-least-32-bytes";
  const context = {
    mode: "CREATE",
    business_draft_id: "a1800000-0000-4000-8000-000000000088",
    business_revision: 1,
    approval_draft_id: "a1800000-0000-4000-8000-000000000089",
    quote_request_id: "a1800000-0000-4000-8000-000000000090",
    intake_id: quotationPromotionRequest.intake_id,
    pricing_snapshot_id: "a1800000-0000-4000-8000-000000000091",
    contract_version: 1,
    payload_sha256: "a".repeat(64),
  };
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await executeQuotationBusinessApprovalPromotionAction(
    userId,
    quotationPromotionRequest,
    {
      rpc: async (name: string, args: Record<string, unknown>) => {
        calls.push({ name, args });
        return name ===
            "resolve_quotation_business_approval_promotion_context_v1"
          ? { data: context, error: null }
          : {
            data: {
              business_draft_id: context.business_draft_id,
              business_revision: 1,
              approval_id: approvalId,
              approval_version: 1,
              status: "APPROVED",
              approved_at: "2099-01-01T00:00:00Z",
              was_created: true,
              integrity: "must-not-leak",
            },
            error: null,
          };
      },
    },
    {
      createApprovalId: () => approvalId,
      getEnv: (name: string) =>
        name === "QUOTATION_APPROVAL_INTEGRITY_ACTIVE_KEY_ID"
          ? "v1"
          : name === "QUOTATION_APPROVAL_INTEGRITY_KEY_V1"
          ? secret
          : undefined,
    },
  );
  assertEquals(calls.map((call) => call.name), [
    "resolve_quotation_business_approval_promotion_context_v1",
    "promote_quotation_business_draft_to_approval_v1",
  ]);
  const integrity = calls[1].args.p_integrity as Parameters<
    typeof verifyQuotationApprovalIntegrity
  >[0];
  assertEquals(await verifyQuotationApprovalIntegrity(integrity, secret), true);
  assertEquals(calls[1].args, {
    p_actor_auth_user_id: userId,
    p_intake_id: quotationPromotionRequest.intake_id,
    p_expected_revision: 1,
    p_idempotency_key: quotationPromotionRequest.idempotency_key,
    p_approval_id: approvalId,
    p_integrity: integrity,
  });
  assertEquals(result, {
    business_draft_id: context.business_draft_id,
    business_revision: 1,
    approval_id: approvalId,
    approval_version: 1,
    status: "APPROVED",
    approved_at: "2099-01-01T00:00:00Z",
    was_created: true,
  });
});

Deno.test("quotation business approval ADOPT verifies its historical key before writing", async () => {
  const approvalId = "a1800000-0000-4000-8000-000000000092";
  const secret = "historical-secret-that-is-at-least-32-bytes";
  const dbRoot = {
    intakeId: quotationPromotionRequest.intake_id,
    approvalId,
    payloadSha256: "b".repeat(64),
    quoteRequestId: "a1800000-0000-4000-8000-000000000094",
    contractVersion: 1,
    pricingSnapshotId: "a1800000-0000-4000-8000-000000000093",
    integrityRootVersion: 1 as const,
  };
  const integrity = await createQuotationApprovalIntegrity(
    dbRoot,
    "v2",
    secret,
  );
  let writes = 0;
  const client = {
    rpc: async (name: string, _args: Record<string, unknown>) => {
      if (name === "resolve_quotation_business_approval_promotion_context_v1") {
        return {
          data: {
            mode: "ADOPT",
            business_draft_id: "a1800000-0000-4000-8000-000000000095",
            business_revision: 1,
            approval_draft_id: "a1800000-0000-4000-8000-000000000096",
            approval_id: approvalId,
            quote_request_id: dbRoot.quoteRequestId,
            intake_id: dbRoot.intakeId,
            pricing_snapshot_id: dbRoot.pricingSnapshotId,
            contract_version: 1,
            payload_sha256: dbRoot.payloadSha256,
            integrity,
          },
          error: null,
        };
      }
      writes += 1;
      return {
        data: {
          business_draft_id: "a1800000-0000-4000-8000-000000000095",
          business_revision: 1,
          approval_id: approvalId,
          approval_version: 1,
          status: "APPROVED",
          approved_at: "2099-01-01T00:00:00Z",
          was_created: false,
        },
        error: null,
      };
    },
  };
  const options = {
    createApprovalId: crypto.randomUUID,
    getEnv: (name: string) =>
      name === "QUOTATION_APPROVAL_INTEGRITY_KEY_V2" ? secret : undefined,
  };
  await executeQuotationBusinessApprovalPromotionAction(
    userId,
    quotationPromotionRequest,
    client,
    options,
  );
  assertEquals(writes, 1);

  integrity.root = {
    ...dbRoot,
    quoteRequestId: "a1800000-0000-4000-8000-000000000097",
  };
  let error: Error | null = null;
  try {
    await executeQuotationBusinessApprovalPromotionAction(
      userId,
      quotationPromotionRequest,
      client,
      options,
    );
  } catch (caught) {
    error = caught as Error;
  }
  assertEquals(error?.message, "APPROVAL_CONFLICT");
  assertEquals(writes, 1);

  integrity.root = dbRoot;
  integrity.mac = "0".repeat(64);
  error = null;
  try {
    await executeQuotationBusinessApprovalPromotionAction(
      userId,
      quotationPromotionRequest,
      client,
      options,
    );
  } catch (caught) {
    error = caught as Error;
  }
  assertEquals(error?.message, "APPROVAL_CONFLICT");
  assertEquals(writes, 1);
});

Deno.test("quotation business approval promotion fails closed for missing active or historical keys", async () => {
  const base = {
    business_draft_id: "a1800000-0000-4000-8000-000000000095",
    business_revision: 1,
    approval_draft_id: "a1800000-0000-4000-8000-000000000096",
    quote_request_id: "a1800000-0000-4000-8000-000000000094",
    intake_id: quotationPromotionRequest.intake_id,
    pricing_snapshot_id: "a1800000-0000-4000-8000-000000000093",
    contract_version: 1,
    payload_sha256: "b".repeat(64),
  };
  const approvalId = "a1800000-0000-4000-8000-000000000092";
  const integrity = await createQuotationApprovalIntegrity(
    {
      approvalId,
      contractVersion: 1,
      intakeId: base.intake_id,
      integrityRootVersion: 1,
      payloadSha256: base.payload_sha256,
      pricingSnapshotId: base.pricing_snapshot_id,
      quoteRequestId: base.quote_request_id,
    },
    "v2",
    "historical-secret-that-is-at-least-32-bytes",
  );
  for (
    const context of [
      { ...base, mode: "CREATE" },
      { ...base, mode: "ADOPT", approval_id: approvalId, integrity },
    ]
  ) {
    let writerCalls = 0;
    let error: Error | null = null;
    try {
      await executeQuotationBusinessApprovalPromotionAction(
        userId,
        quotationPromotionRequest,
        {
          rpc: async (name: string) => {
            if (
              name ===
                "resolve_quotation_business_approval_promotion_context_v1"
            ) return { data: context, error: null };
            writerCalls += 1;
            return { data: null, error: null };
          },
        },
        { createApprovalId: () => approvalId, getEnv: () => undefined },
      );
    } catch (caught) {
      error = caught as Error;
    }
    assertEquals(error?.message, "SERVER_CONFIGURATION_ERROR");
    assertEquals(writerCalls, 0);
  }
});

Deno.test("quotation business approval promotion exposes only stable public errors", async () => {
  for (
    const [databaseCode, status, responseCode] of [
      ["QUOTATION_BUSINESS_SCOPE_DENIED", 403, "OPERATOR_NOT_AUTHORIZED"],
      ["STALE_BUSINESS_REVISION", 409, "STALE_BUSINESS_REVISION"],
      ["IDEMPOTENCY_CONFLICT", 409, "IDEMPOTENCY_CONFLICT"],
      ["APPROVAL_CONFLICT", 409, "APPROVAL_CONFLICT"],
      ["SERVER_CONFIGURATION_ERROR", 500, "SERVER_CONFIGURATION_ERROR"],
    ] as const
  ) {
    const harness = dependencies({
      executeApplicationAction: async () => {
        throw new Error(databaseCode);
      },
    });
    const response = await handleCommercialOperator(
      request(quotationPromotionRequest),
      harness.deps,
    );
    assertEquals(response.status, status);
    assertEquals(await response.json(), { ok: false, code: responseCode });
  }
});

Deno.test("pending-intake list uses preflight and returns only the safe DTO", async () => {
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({ action: "list_pending_intakes" }),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(harness.events, ["preflight", "pending", "ACTIVE"]);
  const body = await response.json();
  assertEquals(body.result.items[0].intake_status, "invited");
  assertEquals(body.result.items[0].started_at, null);
  assertEquals(body.result.items[0].current_reminder_cycle, 0);
  assertEquals(body.result.items[0].reminder_1_sent_at, null);
  assertEquals(body.result.items[0].reminder_2_sent_at, null);
  assertEquals("access_token_hash" in body.result.items[0], false);
  assertEquals("encrypted_payload" in body.result.items[0], false);
});

Deno.test("pending-intake list rejects extra input, unauthorized readers, and unsafe database responses", async () => {
  const invalid = dependencies();
  assertEquals(
    (await handleCommercialOperator(
      request({ action: "list_pending_intakes", limit: 1 }),
      invalid.deps,
    )).status,
    400,
  );
  assertEquals(invalid.events, ["preflight"]);

  const unauthorized = dependencies({
    authorizeApplicationReader: async () => {
      throw new Error("APPLICATION_SCOPE_DENIED");
    },
  });
  assertEquals(
    (await handleCommercialOperator(
      request({ action: "list_pending_intakes" }),
      unauthorized.deps,
    )).status,
    403,
  );

  const unsafe = dependencies({
    executePendingIntakes: async () => ({
      items: [{ access_token_hash: "forbidden" }],
    }),
  });
  assertEquals(
    (await handleCommercialOperator(
      request({ action: "list_pending_intakes" }),
      unsafe.deps,
    )).status,
    500,
  );
});

Deno.test("pending-intake list accepts the current reminder DTO and rejects contract drift", async () => {
  const current = dependencies({
    executePendingIntakes: async () => ({
      items: [pendingIntakeDto({
        started_at: "2099-01-02T10:00:00Z",
        current_reminder_cycle: 2,
        reminder_1_sent_at: "2099-01-05T10:00:00Z",
      })],
    }),
  });
  const currentResponse = await handleCommercialOperator(
    request({ action: "list_pending_intakes" }),
    current.deps,
  );
  assertEquals(currentResponse.status, 200);
  assertEquals(
    (await currentResponse.json()).result.items[0].current_reminder_cycle,
    2,
  );

  const missingReminderCycle = pendingIntakeDto();
  delete missingReminderCycle.current_reminder_cycle;
  const missingDossierState = pendingIntakeDto();
  delete missingDossierState.dossier_state;
  for (
    const item of [
      missingReminderCycle,
      missingDossierState,
      pendingIntakeDto({ current_reminder_cycle: "0" }),
      pendingIntakeDto({ dossier_state: "TRASHED" }),
      pendingIntakeDto({ dossier_revision: -1 }),
      pendingIntakeDto({ unknown_field: true }),
    ]
  ) {
    const malformed = dependencies({
      executePendingIntakes: async () => ({ items: [item] }),
    });
    assertEquals(
      (await handleCommercialOperator(
        request({ action: "list_pending_intakes" }),
        malformed.deps,
      )).status,
      500,
    );
  }
});

Deno.test("pending-intake list accepts the canonical SDF delivery DTO", async () => {
  const harness = dependencies({
    executePendingIntakes: async () => ({
      items: [pendingIntakeDto({
        request_kind: "slimme_documentenflow",
        support_reference: "#5C19F9DD",
        sdf_package: "groei",
        website_type: "Slimme documentenflow - groei",
        invitation_delivery_status: "pending",
      })],
    }),
  });
  const response = await handleCommercialOperator(request({ action: "list_pending_intakes" }), harness.deps);
  assertEquals(response.status, 200);
  const item = (await response.json()).result.items[0];
  assertEquals(item.sdf_package, "groei");
  assertEquals(item.support_reference, "#5C19F9DD");

  for (const support_reference of [undefined, null, "5C19F9DD", "#not-valid"]) {
    const invalid = pendingIntakeDto({
      request_kind: "slimme_documentenflow",
      sdf_package: "groei",
      website_type: "Slimme documentenflow - groei",
      invitation_delivery_status: "pending",
      support_reference,
    });
    const malformed = dependencies({ executePendingIntakes: async () => ({ items: [invalid] }) });
    assertEquals((await handleCommercialOperator(request({ action: "list_pending_intakes" }), malformed.deps)).status, 500);
  }
});

Deno.test("pending-intake list and retention actions use fixed validated state", async () => {
  let archivedRetentionState = "";
  const archived = dependencies({
    executePendingIntakes: async (
      _actorAuthUserId: string,
      retentionState: string,
    ) => {
      archivedRetentionState = retentionState;
      return { items: [] };
    },
  });
  const archivedResponse = await handleCommercialOperator(
    request({ action: "list_pending_intakes", retention_state: "ARCHIVED" }),
    archived.deps,
  );
  assertEquals(archivedResponse.status, 200);
  assertEquals((await archivedResponse.json()).result.items, []);
  assertEquals(archived.events, ["preflight"]);
  assertEquals(archivedRetentionState, "ARCHIVED");

  for (
    const [action, eventType] of [
      ["archive_pending_intake", "ARCHIVED"],
      ["restore_pending_intake", "RESTORED"],
    ] as const
  ) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request({
        action,
        intake_id: "a1800000-0000-4000-8000-000000000092",
        expected_revision: 0,
        idempotency_key: "a1800000-0000-4000-8000-000000000093",
        reason: "Workspace retention",
      }),
      harness.deps,
    );
    assertEquals(response.status, 200);
    assertEquals(harness.events, ["preflight"]);
    assertEquals(harness.calls[0].input, {
      action,
      intake_id: "a1800000-0000-4000-8000-000000000092",
      event_type: eventType,
      expected_revision: 0,
      idempotency_key: "a1800000-0000-4000-8000-000000000093",
      reason: "Workspace retention",
    });
  }
});

Deno.test("pending permanent delete requires exact identifiers and explicit reason", async () => {
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({
      action: "permanently_delete_pending_intake",
      intake_id: "a1800000-0000-4000-8000-000000000092",
      quote_request_id: "a1800000-0000-4000-8000-000000000091",
      idempotency_key: "a1800000-0000-4000-8000-000000000094",
      reason: "Confirmed disposable pre-submission record",
    }),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(harness.events, ["preflight"]);
  assertEquals(harness.calls[0].input, {
    action: "permanently_delete_pending_intake",
    intake_id: "a1800000-0000-4000-8000-000000000092",
    quote_request_id: "a1800000-0000-4000-8000-000000000091",
    idempotency_key: "a1800000-0000-4000-8000-000000000094",
    reason: "Confirmed disposable pre-submission record",
  });
  assertEquals(
    (await handleCommercialOperator(
      request({
        action: "permanently_delete_pending_intake",
        intake_id: "a1800000-0000-4000-8000-000000000092",
        quote_request_id: "a1800000-0000-4000-8000-000000000091",
        idempotency_key: "a1800000-0000-4000-8000-000000000094",
      }),
      dependencies().deps,
    )).status,
    400,
  );
});

Deno.test("pending workspace mutations expose safe conflict envelopes", async () => {
  for (
    const [databaseCode, responseCode] of [
      ["PENDING_INTAKE_DELETE_BLOCKED", "COMMAND_REJECTED"],
      ["PENDING_INTAKE_REQUIRED", "COMMAND_REJECTED"],
      ["STALE_PENDING_INTAKE_RETENTION_REVISION", "CONCURRENT_MODIFICATION"],
    ] as const
  ) {
    const harness = dependencies({
      executeApplicationAction: async () => {
        throw new Error(databaseCode);
      },
    });
    const response = await handleCommercialOperator(
      request({
        action: "archive_pending_intake",
        intake_id: "a1800000-0000-4000-8000-000000000092",
        expected_revision: 0,
        idempotency_key: "a1800000-0000-4000-8000-000000000093",
        reason: "Workspace retention",
      }),
      harness.deps,
    );
    assertEquals(response.status, 409);
    assertEquals((await response.json()).code, responseCode);
  }
});

Deno.test("pending-intake count returns only active aggregate metadata", async () => {
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({ action: "count_pending_intakes" }),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    ok: true,
    code: "APPLICATION_ACTION_ACCEPTED",
    result: { active_count: 3 },
  });
  assertEquals(harness.events, ["preflight", "pending-count"]);
});

Deno.test("dossier document actions accept only exact authority-minimal input", async () => {
  const quoteRequestId = "a1800000-0000-4000-8000-000000000093";
  const documentId = "a1800000-0000-4000-8000-000000000094";
  for (
    const [body, input] of [
      [
        {
          action: "get_dossier_document_manifest",
          quote_request_id: quoteRequestId,
        },
        {
          action: "get_dossier_document_manifest",
          quote_request_id: quoteRequestId,
        },
      ],
      [
        {
          action: "create_dossier_document_access",
          quote_request_id: quoteRequestId,
          source_type: "CUSTOMER_UPLOAD",
          document_id: documentId,
        },
        {
          action: "create_dossier_document_access",
          quote_request_id: quoteRequestId,
          source_type: "CUSTOMER_UPLOAD",
          document_id: documentId,
        },
      ],
    ] as const
  ) {
    const harness = dependencies();
    assertEquals(
      (await handleCommercialOperator(request(body), harness.deps)).status,
      200,
    );
    assertEquals(harness.calls, [{ jwt, input }]);
  }
  for (
    const invalid of [
      { action: "get_dossier_document_manifest", quote_request_id: "invalid" },
      {
        action: "get_dossier_document_manifest",
        quote_request_id: quoteRequestId,
        storage_bucket_id: "quotation-artifacts",
      },
      {
        action: "create_dossier_document_access",
        quote_request_id: quoteRequestId,
        source_type: "QUOTATION",
        document_id: documentId,
      },
      {
        action: "create_dossier_document_access",
        quote_request_id: quoteRequestId,
        source_type: "CUSTOMER_UPLOAD",
        document_id: documentId,
        storage_object_path: "forged/path.pdf",
      },
    ]
  ) {
    const harness = dependencies();
    assertEquals(
      (await handleCommercialOperator(request(invalid), harness.deps)).status,
      400,
    );
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("dossier document manifest transport validates and exposes only the approved DTO", async () => {
  const quoteRequestId = "a1800000-0000-4000-8000-000000000093";
  const documentId = "a1800000-0000-4000-8000-000000000094";
  const row = {
    document_id: documentId,
    source_type: "CUSTOMER_UPLOAD",
    document_type: "CUSTOMER_UPLOAD",
    artifact_type: null,
    title: "briefing.pdf",
    filename: "briefing.pdf",
    status: "ACCEPTED",
    created_at: "2099-01-01T00:00:00Z",
    accepted_at: null,
    source_record_id: documentId,
    version: null,
    sha256: "1".repeat(64),
    quote_request_id: quoteRequestId,
    customer_id: null,
    project_id: null,
    can_open: true,
    can_download: true,
  };
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await executeDossierDocumentManifestTransport(
    {
      rpc: async (name, args) => {
        calls.push({ name, args });
        return { data: [row], error: null };
      },
    },
    userId,
    {
      action: "get_dossier_document_manifest",
      quote_request_id: quoteRequestId,
    },
  );
  assertEquals(result, [row]);
  assertEquals(calls, [{
    name: "get_operator_dossier_document_manifest_v1",
    args: {
      p_actor_auth_user_id: userId,
      p_quote_request_id: quoteRequestId,
    },
  }]);
  await assertRejects(
    () =>
      executeDossierDocumentManifestTransport(
        {
          rpc: () =>
            Promise.resolve({
              data: [{ ...row, storage_object_path: "private/path.pdf" }],
              error: null,
            }),
        },
        userId,
        {
          action: "get_dossier_document_manifest",
          quote_request_id: quoteRequestId,
        },
      ),
    Error,
    "INVALID_DOSSIER_DOCUMENT_MANIFEST_RESPONSE",
  );
});

Deno.test("dossier document access signs only an exact authorized locator and returns no locator", async () => {
  const quoteRequestId = "a1800000-0000-4000-8000-000000000093";
  const documentId = "a1800000-0000-4000-8000-000000000094";
  const events: string[] = [];
  const result = await executeDossierDocumentAccessTransport(
    {
      rpc: async (name, args) => {
        events.push(`rpc:${name}`);
        assertEquals(args, {
          p_actor_auth_user_id: userId,
          p_quote_request_id: quoteRequestId,
          p_source_type: "QUOTATION_ARTIFACT",
          p_document_id: documentId,
        });
        return {
          data: {
            state: "AUTHORIZED",
            document_id: documentId,
            source_type: "QUOTATION_ARTIFACT",
            storage_bucket_id: "quotation-artifacts",
            storage_object_path: "issuances/exact.docx",
            filename: "LWS-OFF-2099-0001-v1.docx",
            expires_in_seconds: 60,
          },
          error: null,
        };
      },
    },
    userId,
    {
      action: "create_dossier_document_access",
      quote_request_id: quoteRequestId,
      source_type: "QUOTATION_ARTIFACT",
      document_id: documentId,
    },
    async (bucket, path, ttl, filename) => {
      events.push("sign");
      assertEquals({ bucket, path, ttl, filename }, {
        bucket: "quotation-artifacts",
        path: "issuances/exact.docx",
        ttl: 60,
        filename: "LWS-OFF-2099-0001-v1.docx",
      });
      return "https://storage.example.test/signed/exact";
    },
    () => 4_070_908_800_000,
  );
  assertEquals(events, [
    "rpc:authorize_operator_dossier_document_download_v1",
    "sign",
  ]);
  assertEquals(result, {
    signed_url: "https://storage.example.test/signed/exact",
    expires_at: "2099-01-01T00:01:00.000Z",
    filename: "LWS-OFF-2099-0001-v1.docx",
  });
  assertEquals(JSON.stringify(result).includes("quotation-artifacts"), false);
  assertEquals(JSON.stringify(result).includes("issuances/exact.docx"), false);
});

Deno.test("dossier document access fails closed before signing and maps authorization safely", async () => {
  let signCalls = 0;
  const quoteRequestId = "a1800000-0000-4000-8000-000000000093";
  const documentId = "a1800000-0000-4000-8000-000000000094";
  await assertRejects(
    () =>
      executeDossierDocumentAccessTransport(
        {
          rpc: () =>
            Promise.resolve({
              data: {
                state: "AUTHORIZED",
                document_id: documentId,
                source_type: "CUSTOMER_UPLOAD",
                storage_bucket_id: "customer-request-quarantine",
                storage_object_path: "forged/path.pdf",
                filename: "briefing.pdf",
                expires_in_seconds: 300,
              },
              error: null,
            }),
        },
        userId,
        {
          action: "create_dossier_document_access",
          quote_request_id: quoteRequestId,
          source_type: "CUSTOMER_UPLOAD",
          document_id: documentId,
        },
        async () => {
          signCalls += 1;
          return "https://storage.example.test/forged";
        },
      ),
    Error,
    "INVALID_DOSSIER_DOCUMENT_AUTHORIZATION_RESPONSE",
  );
  assertEquals(signCalls, 0);

  for (
    const databaseCode of [
      "DOSSIER_DOCUMENT_READER_REQUIRED",
      "DOSSIER_DOCUMENT_ACCESS_DENIED",
    ]
  ) {
    const harness = dependencies({
      executeApplicationAction: async () => {
        throw new Error(databaseCode);
      },
    });
    const response = await handleCommercialOperator(
      request({
        action: "create_dossier_document_access",
        quote_request_id: quoteRequestId,
        source_type: "CUSTOMER_UPLOAD",
        document_id: documentId,
      }),
      harness.deps,
    );
    assertEquals(response.status, 403);
    assertEquals((await response.json()).code, "OPERATOR_NOT_AUTHORIZED");
  }
});

Deno.test("dossier document index dispatch signs only the RPC-authorized object for 60 seconds", async () => {
  const quoteRequestId = "a1800000-0000-4000-8000-000000000093";
  const documentId = "a1800000-0000-4000-8000-000000000094";
  const calls: Array<Record<string, unknown>> = [];
  const client = {
    rpc: async (name: string, args: Record<string, unknown>) => {
      calls.push({ kind: "rpc", name, args });
      return {
        data: {
          state: "AUTHORIZED",
          document_id: documentId,
          source_type: "CUSTOMER_UPLOAD",
          storage_bucket_id: "customer-request-quarantine",
          storage_object_path: "requests/exact/file.pdf",
          filename: "briefing.pdf",
          expires_in_seconds: 60,
        },
        error: null,
      };
    },
    storage: {
      from: (bucket: string) => ({
        createSignedUrl: async (
          path: string,
          expiresIn: number,
          options: { download: string },
        ) => {
          calls.push({ kind: "sign", bucket, path, expiresIn, options });
          return {
            data: { signedUrl: "https://storage.example.test/signed/upload" },
            error: null,
          };
        },
      }),
    },
  };
  const result = await executeServiceRoleDossierDocumentAction(
    userId,
    {
      action: "create_dossier_document_access",
      quote_request_id: quoteRequestId,
      source_type: "CUSTOMER_UPLOAD",
      document_id: documentId,
    },
    client,
    () => 4_070_908_800_000,
  );
  assertEquals(calls, [
    {
      kind: "rpc",
      name: "authorize_operator_dossier_document_download_v1",
      args: {
        p_actor_auth_user_id: userId,
        p_quote_request_id: quoteRequestId,
        p_source_type: "CUSTOMER_UPLOAD",
        p_document_id: documentId,
      },
    },
    {
      kind: "sign",
      bucket: "customer-request-quarantine",
      path: "requests/exact/file.pdf",
      expiresIn: 60,
      options: { download: "briefing.pdf" },
    },
  ]);
  assertEquals(result, {
    signed_url: "https://storage.example.test/signed/upload",
    expires_at: "2099-01-01T00:01:00.000Z",
    filename: "briefing.pdf",
  });
});

Deno.test("workforce calendar accepts only exact bounded dates without client actor authority", async () => {
  const harness = dependencies();
  const response = await handleCommercialOperator(
    request({
      action: "list_workforce_calendar",
      start_date: "2026-08-24",
      end_date: "2026-08-30",
    }),
    harness.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(harness.calls, [{
    jwt,
    input: {
      action: "list_workforce_calendar",
      start_date: "2026-08-24",
      end_date: "2026-08-30",
    },
  }]);
  assertEquals(Object.hasOwn(harness.calls[0].input, "actor_id"), false);

  const invalidRequests = [
    { start_date: "2026-8-24", end_date: "2026-08-30" },
    { start_date: "2026-08-24", end_date: "2026-02-30" },
    { start_date: "2026-08-30", end_date: "2026-08-24" },
    { start_date: "2026-01-01", end_date: "2027-01-02" },
  ];
  for (const invalid of invalidRequests) {
    const invalidResponse = await handleCommercialOperator(
      request({ action: "list_workforce_calendar", ...invalid }),
      dependencies().deps,
    );
    assertEquals(invalidResponse.status, 400);
    assertEquals((await invalidResponse.json()).code, "INVALID_REQUEST");
  }
  const maximumResponse = await handleCommercialOperator(
    request({
      action: "list_workforce_calendar",
      start_date: "2027-01-01",
      end_date: "2028-01-01",
    }),
    dependencies().deps,
  );
  assertEquals(maximumResponse.status, 200);
  const forgedActor = await handleCommercialOperator(
    request({
      action: "list_workforce_calendar",
      start_date: "2026-08-24",
      end_date: "2026-08-30",
      actor_id: userId,
    }),
    dependencies().deps,
  );
  assertEquals(forgedActor.status, 400);
  assertEquals((await forgedActor.json()).code, "IDENTITY_FIELD_FORBIDDEN");
});

Deno.test("workforce calendar transport calls only the service RPC with server actor and accepts empty authority", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const input = {
    action: "list_workforce_calendar" as const,
    start_date: "2026-08-24",
    end_date: "2026-08-30",
  };
  const result = await executeServiceRoleWorkforceCalendarAction(
    userId,
    input,
    {
      rpc: (name: string, args: Record<string, unknown>) => {
        calls.push({ name, args });
        return Promise.resolve({
          data: workforceCalendarResult(),
          error: null,
        });
      },
    },
  );
  assertEquals(result, workforceCalendarResult());
  assertEquals(calls, [{
    name: "list_workforce_calendar_v1",
    args: {
      p_actor_id: userId,
      p_start_date: "2026-08-24",
      p_end_date: "2026-08-30",
    },
  }]);
});

Deno.test("workforce calendar transport accepts the exact employee DTO and all six statuses", async () => {
  const statuses = [
    "WORKED_FULL_DAY",
    "WORKED_HALF_DAY_AM",
    "WORKED_HALF_DAY_PM",
    "LEAVE",
    "SICK",
    "OTHER_ABSENCE",
  ];
  const data = workforceCalendarResult({
    employees: [{
      employee_id: workforceEmployeeId,
      display_name: "Workforce Employee",
      role_title: "Consultant",
      team_name: null,
      employment_status: "ACTIVE",
      entries: statuses.map((status, index) => ({
        date: `2026-08-${String(24 + index).padStart(2, "0")}`,
        status,
      })),
    }],
  });
  const result = await executeWorkforceCalendarTransport(
    {
      rpc: () => Promise.resolve({ data, error: null }),
    },
    userId,
    {
      action: "list_workforce_calendar",
      start_date: "2026-08-24",
      end_date: "2026-08-30",
    },
  );
  assertEquals(result, data);
});

Deno.test("workforce calendar response validator rejects drift and unknown status", async () => {
  const input = {
    action: "list_workforce_calendar" as const,
    start_date: "2026-08-24",
    end_date: "2026-08-30",
  };
  const employee = {
    employee_id: workforceEmployeeId,
    display_name: "Workforce Employee",
    role_title: null,
    team_name: "Operations",
    employment_status: "ACTIVE",
    entries: [{ date: "2026-08-24", status: "WORKED_FULL_DAY" }],
  };
  for (
    const invalid of [
      workforceCalendarResult({
        employees: [{ ...employee, email: "private@example.test" }],
      }),
      workforceCalendarResult({
        employees: [{
          ...employee,
          entries: [{ date: "2026-08-24", status: "UNKNOWN" }],
        }],
      }),
      workforceCalendarResult({
        employees: [{
          ...employee,
          entries: [{ date: "2026-02-30", status: "WORKED_FULL_DAY" }],
        }],
      }),
      { ...workforceCalendarResult(), extra: true },
    ]
  ) {
    await assertRejects(
      () =>
        executeWorkforceCalendarTransport(
          {
            rpc: () => Promise.resolve({ data: invalid, error: null }),
          },
          userId,
          input,
        ),
      Error,
      "INVALID_WORKFORCE_CALENDAR_RESPONSE",
    );
  }
});

Deno.test("workforce calendar failures use stable authorization and internal envelopes", async () => {
  for (
    const [databaseCode, status, publicCode] of [
      ["WORKFORCE_MANAGEMENT_READER_REQUIRED", 403, "OPERATOR_NOT_AUTHORIZED"],
      ["OPERATOR_NOT_ACTIVE", 403, "OPERATOR_NOT_AUTHORIZED"],
      ["UNEXPECTED_WORKFORCE_FAILURE", 500, "INTERNAL_ERROR"],
    ] as const
  ) {
    const harness = dependencies({
      executeApplicationAction: async () => {
        throw new Error(databaseCode);
      },
    });
    const response = await handleCommercialOperator(
      request({
        action: "list_workforce_calendar",
        start_date: "2026-08-24",
        end_date: "2026-08-30",
      }),
      harness.deps,
    );
    assertEquals(response.status, status);
    assertEquals((await response.json()).code, publicCode);
  }
});

Deno.test("recruitment vacancy actions accept only exact authority-minimal input", async () => {
  const valid = [
    { action: "list_recruitment_vacancies" },
    { action: "get_recruitment_publication_state" },
    { action: "set_recruitment_publication_enabled", enabled: true },
    { action: "set_recruitment_publication_enabled", enabled: false },
    {
      action: "create_recruitment_vacancy",
      slug: "senior-webontwikkelaar",
      ...vacancyContent,
    },
    {
      action: "update_recruitment_vacancy",
      vacancy_id: vacancyId,
      ...vacancyContent,
    },
    {
      action: "set_recruitment_vacancy_status",
      vacancy_id: vacancyId,
      status: "PUBLISHED",
    },
    {
      action: "set_recruitment_vacancy_status",
      vacancy_id: vacancyId,
      status: "CLOSED",
    },
  ];
  for (const input of valid) {
    const harness = dependencies();
    const response = await handleCommercialOperator(
      request(input),
      harness.deps,
    );
    assertEquals(response.status, 200);
    assertEquals(harness.calls[0].input, input);
  }

  for (
    const input of [
      { action: "list_recruitment_vacancies", role: "owner" },
      { action: "get_recruitment_publication_state", role: "owner" },
      { action: "set_recruitment_publication_enabled", enabled: "true" },
      {
        action: "set_recruitment_publication_enabled",
        enabled: true,
        header: false,
      },
      {
        action: "create_recruitment_vacancy",
        slug: "Invalid Slug",
        ...vacancyContent,
      },
      {
        action: "create_recruitment_vacancy",
        slug: "valid-slug",
        ...vacancyContent,
        title: " ",
      },
      {
        action: "update_recruitment_vacancy",
        vacancy_id: "not-a-uuid",
        ...vacancyContent,
      },
      {
        action: "update_recruitment_vacancy",
        vacancy_id: vacancyId,
        ...vacancyContent,
        status: "PUBLISHED",
      },
      {
        action: "set_recruitment_vacancy_status",
        vacancy_id: vacancyId,
        status: "DRAFT",
      },
      {
        action: "set_recruitment_vacancy_status",
        vacancy_id: vacancyId,
        status: "PUBLISHED",
        actor_id: userId,
      },
    ]
  ) {
    const response = await handleCommercialOperator(
      request(input),
      dependencies().deps,
    );
    assertEquals(response.status, 400);
  }
});

Deno.test("recruitment vacancy transports use exact RPC names and arguments", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      const data = name === "list_owner_recruitment_vacancies_v1"
        ? [recruitmentVacancy()]
        : name === "get_public_recruitment_publication_state_v1"
        ? { enabled: true }
        : name === "set_recruitment_publication_enabled_v1"
        ? { enabled: false }
        : name === "set_recruitment_vacancy_status_v1"
        ? {
          id: vacancyId,
          slug: "senior-webontwikkelaar",
          status: "PUBLISHED",
          published_at: "2026-08-30T19:00:00.000Z",
          closed_at: null,
        }
        : { id: vacancyId, slug: "senior-webontwikkelaar", status: "DRAFT" };
      return Promise.resolve({ data, error: null });
    },
  };
  assertEquals(
    await executeRecruitmentVacancyTransport(client, {
      action: "list_recruitment_vacancies",
    }),
    [recruitmentVacancy()],
  );
  assertEquals(
    await executeRecruitmentVacancyTransport(client, {
      action: "get_recruitment_publication_state",
    }),
    { enabled: true },
  );
  assertEquals(
    await executeRecruitmentVacancyTransport(client, {
      action: "set_recruitment_publication_enabled",
      enabled: false,
    }),
    { enabled: false },
  );
  await executeRecruitmentVacancyTransport(client, {
    action: "create_recruitment_vacancy",
    slug: "senior-webontwikkelaar",
    ...vacancyContent,
  });
  await executeRecruitmentVacancyTransport(client, {
    action: "update_recruitment_vacancy",
    vacancy_id: vacancyId,
    ...vacancyContent,
  });
  await executeRecruitmentVacancyTransport(client, {
    action: "set_recruitment_vacancy_status",
    vacancy_id: vacancyId,
    status: "PUBLISHED",
  });
  assertEquals(calls, [
    { name: "list_owner_recruitment_vacancies_v1", args: {} },
    { name: "get_public_recruitment_publication_state_v1", args: {} },
    {
      name: "set_recruitment_publication_enabled_v1",
      args: { p_enabled: false },
    },
    {
      name: "create_recruitment_vacancy_v1",
      args: {
        p_title: vacancyContent.title,
        p_slug: "senior-webontwikkelaar",
        p_department: vacancyContent.department,
        p_location: vacancyContent.location,
        p_employment_type: vacancyContent.employment_type,
        p_summary: vacancyContent.summary,
        p_description: vacancyContent.description,
        p_requirements: vacancyContent.requirements,
      },
    },
    {
      name: "update_recruitment_vacancy_v1",
      args: {
        p_vacancy_id: vacancyId,
        p_title: vacancyContent.title,
        p_department: vacancyContent.department,
        p_location: vacancyContent.location,
        p_employment_type: vacancyContent.employment_type,
        p_summary: vacancyContent.summary,
        p_description: vacancyContent.description,
        p_requirements: vacancyContent.requirements,
      },
    },
    {
      name: "set_recruitment_vacancy_status_v1",
      args: { p_vacancy_id: vacancyId, p_status: "PUBLISHED" },
    },
  ]);
});

Deno.test("recruitment vacancy response validators reject projection and lifecycle drift", async () => {
  for (
    const invalid of [
      { ...recruitmentVacancy(), operator_id: userId },
      { ...recruitmentVacancy(), status: "UNKNOWN" },
      { ...recruitmentVacancy(), created_at: "not-a-date" },
    ]
  ) {
    await assertRejects(
      () =>
        executeRecruitmentVacancyTransport({
          rpc: () => Promise.resolve({ data: [invalid], error: null }),
        }, { action: "list_recruitment_vacancies" }),
      Error,
      "INVALID_RECRUITMENT_VACANCY_RESPONSE",
    );
  }
  await assertRejects(
    () =>
      executeRecruitmentVacancyTransport({
        rpc: () =>
          Promise.resolve({
            data: {
              id: vacancyId,
              slug: "senior-webontwikkelaar",
              status: "PUBLISHED",
            },
            error: null,
          }),
      }, {
        action: "create_recruitment_vacancy",
        slug: "senior-webontwikkelaar",
        ...vacancyContent,
      }),
    Error,
    "INVALID_RECRUITMENT_VACANCY_RESPONSE",
  );
  await assertRejects(
    () =>
      executeRecruitmentVacancyTransport({
        rpc: () =>
          Promise.resolve({
            data: {
              id: vacancyId,
              slug: "senior-webontwikkelaar",
              status: "CLOSED",
              published_at: null,
              closed_at: "bad-date",
            },
            error: null,
          }),
      }, {
        action: "set_recruitment_vacancy_status",
        vacancy_id: vacancyId,
        status: "PUBLISHED",
      }),
    Error,
    "INVALID_RECRUITMENT_VACANCY_RESPONSE",
  );
  for (
    const invalid of [{}, { enabled: "true" }, { enabled: true, owner: true }]
  ) {
    await assertRejects(
      () =>
        executeRecruitmentVacancyTransport({
          rpc: () => Promise.resolve({ data: invalid, error: null }),
        }, { action: "get_recruitment_publication_state" }),
      Error,
      "INVALID_RECRUITMENT_PUBLICATION_RESPONSE",
    );
  }
});

Deno.test("recruitment vacancy index dispatch constructs only a caller JWT client", async () => {
  const clientJwts: string[] = [];
  const result = await executeCallerJwtRecruitmentVacancyAction(jwt, {
    action: "list_recruitment_vacancies",
  }, (token) => {
    clientJwts.push(token);
    return {
      rpc: () => Promise.resolve({ data: [recruitmentVacancy()], error: null }),
    };
  });
  assertEquals(clientJwts, [jwt]);
  assertEquals(result, [recruitmentVacancy()]);
});

Deno.test("recruitment vacancy failures expose stable authorization and conflict envelopes", async () => {
  for (
    const [databaseCode, status, publicCode] of [
      ["RECRUITMENT_OWNER_REQUIRED", 403, "OPERATOR_NOT_AUTHORIZED"],
      ["RECRUITMENT_VACANCY_NOT_FOUND", 404, "RECRUITMENT_VACANCY_NOT_FOUND"],
      [
        'duplicate key value violates unique constraint "recruitment_vacancies_slug_key"',
        409,
        "RECRUITMENT_VACANCY_SLUG_CONFLICT",
      ],
    ] as const
  ) {
    const response = await handleCommercialOperator(
      request({ action: "list_recruitment_vacancies" }),
      dependencies({
        executeApplicationAction: async () => {
          throw new Error(databaseCode);
        },
      }).deps,
    );
    assertEquals(response.status, status);
    assertEquals((await response.json()).code, publicCode);
  }
});
