import { assertEquals, assertMatch } from "jsr:@std/assert@1";
import {
  createUnsignedTestJwt,
  handleCommercialOperator,
} from "./handler.ts";

const userId = "a1000000-0000-4000-8000-000000000001";
const quoteRequestId = "a1800000-0000-4000-8000-000000000001";
const callerJwt = createUnsignedTestJwt({
  sub: userId,
  role: "authenticated",
  aal: "aal1",
  exp: 4102444800,
});

function substanceResponse() {
  return {
    quote_request_id: quoteRequestId,
    request_kind: "slimme_documentenflow",
    request: {
      reference: "LWS-AAN-2099-0001",
      original_text: "Synthetic detail request",
      requested_service: "Slimme Documentenflow - groei",
      requested_at: "2099-01-01T10:00:00Z",
    },
    customer: {
      name: "Synthetic Customer",
      company: null,
      email: "synthetic@example.test",
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
          currentWorkflow: "Manual",
          desiredWorkflow: "Automated",
          volumeBand: null,
          frequency: null,
          relevantDocumentTypes: [],
          rolesUsers: [],
        },
        sampleDocumentMetadata: {
          available: false,
          requestedByLws: false,
          uploadRequiredLater: true,
        },
        commercialQualification: {
          packageDirection: "groei",
          customComplexity: null,
          documentVolumes: [],
          flowCount: 1,
          userCount: 2,
        },
      },
    },
    documents: { customer_request_count: 0, uploaded_document_count: 0 },
  };
}

Deno.test("production dossier substance request contract reaches caller-JWT detail transport", async () => {
  const body = {
    action: "get_dossier_substance",
    quote_request_id: quoteRequestId,
  };
  const observedJwts: string[] = [];
  assertEquals(Object.keys(body).sort(), ["action", "quote_request_id"]);
  assertMatch(body.quote_request_id, /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);

  const response = await handleCommercialOperator(
    new Request("https://example.test", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${callerJwt}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    }),
    {
      now: () => Date.now(),
      verifyUser: async () => ({ id: userId }),
      authorizeApplicationReader: async () => undefined,
      verifyOperatorCursor: async () => null,
      executeApplicationListV2: async () => ({ items: [], has_more: false, next_position: null }),
      executePendingIntakes: async () => ({ items: [] }),
      executePendingIntakeCount: async () => ({ active_count: 0 }),
      executeDossierSubstance: async (jwt: string, actorAuthUserId: string, receivedQuoteRequestId: string) => {
        observedJwts.push(jwt);
        assertEquals(actorAuthUserId, userId);
        assertEquals(receivedQuoteRequestId, quoteRequestId);
        return substanceResponse();
      },
      executeMarkDossierSeen: async () => ({}),
      signOperatorCursor: async () => "unused",
      executeApplicationFacetsV2: async () => ({}),
      executeApplicationAction: async () => ({}),
      consumeRateLimit: async () => ({ allowed: true, retry_after_seconds: 0 }),
      executeCommand: async () => ({}),
    },
  );

  assertEquals(response.status, 200);
  assertEquals(observedJwts, [callerJwt]);
  assertEquals((await response.json()).result.quote_request_id, quoteRequestId);
});
