import { assertEquals } from "jsr:@std/assert@1";
import { handleSubmitQuoteRequest } from "./index.ts";

const payload = {
  request_kind: "website",
  name: "Lorenzo Bombello",
  customer_type: "business",
  company: "Lorenzo Web Solutions",
  enterprise_number: "0742.361.487",
  has_vat_number: true,
  vat_number: "BE0742361487",
  billing_address: "Grote Baan 164",
  billing_postal_code: "9920",
  billing_city: "Lievegem",
  billing_country: "Belgie",
  billing_email: "billing@example.com",
  email: "hello@example.com",
  phone: "+32 470 00 00 00",
  website_type: "Bedrijfswebsite",
  budget: "EUR 1.800 tot minder dan EUR 3.500",
  timing: "Flexibel / nog te bepalen",
  description: "Een veilige testaanvraag voor een nieuwe website.",
  privacy_consent: true,
  website: "",
};

function soapResponse(valid: boolean): string {
  return `<?xml version="1.0"?><soap:Envelope><soap:Body><checkVatResponse><valid>${valid}</valid></checkVatResponse></soap:Body></soap:Envelope>`;
}

Deno.test({
  name: "invalid and unavailable VAT stop before request creation and email",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const originalFetch = globalThis.fetch;
    const previousEnvironment = new Map<string, string | undefined>();
    for (const [name, value] of [
      ["SUPABASE_URL", "https://supabase.test"],
      ["SUPABASE_SERVICE_ROLE_KEY", "service-role-test-key"],
      ["RESEND_API_KEY", "resend-test-key"],
      ["ADMIN_EMAIL", "admin@example.com"],
      ["FROM_EMAIL", "sender@example.com"],
      ["APPROVAL_TOKEN_SECRET", "approval-token-secret-with-sufficient-test-entropy"],
    ]) {
      previousEnvironment.set(name, Deno.env.get(name));
      Deno.env.set(name, value);
    }

    let viesMode: "invalid" | "unavailable" = "invalid";
    let createRpcCalls = 0;
    let emailCalls = 0;
    const requests: string[] = [];
    globalThis.fetch = (async (input, init) => {
      const url = input instanceof Request ? input.url : String(input);
      const method = input instanceof Request ? input.method : init?.method || "GET";
      requests.push(`${method} ${url}`);
      if (url.includes("ec.europa.eu")) {
        return viesMode === "invalid"
          ? new Response(soapResponse(false), { status: 200 })
          : new Response("<soap:Fault>SERVICE_UNAVAILABLE</soap:Fault>", { status: 500 });
      }
      if (url.includes("/rest/v1/quote_requests")) {
        if (method === "HEAD") {
          return new Response(null, { status: 200, headers: { "Content-Range": "*/0" } });
        }
        return Response.json([], { status: 200 });
      }
      if (url.includes("/rest/v1/rpc/create_quote_request_idempotent")) {
        createRpcCalls += 1;
        return Response.json({}, { status: 200 });
      }
      if (url.includes("api.resend.com")) {
        emailCalls += 1;
        return Response.json({}, { status: 200 });
      }
      throw new Error(`Unexpected fetch: ${method} ${url}`);
    }) as typeof fetch;

    try {
      for (const scenario of [
        { mode: "invalid" as const, status: 422, code: "VAT_NUMBER_INVALID" },
        { mode: "unavailable" as const, status: 503, code: "VAT_VALIDATION_UNAVAILABLE" },
      ]) {
        viesMode = scenario.mode;
        const response = await handleSubmitQuoteRequest(new Request("https://functions.test/submit-quote-request", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Idempotency-Key": crypto.randomUUID(),
          },
          body: JSON.stringify(payload),
        }));
        const responseBody = await response.json();
        assertEquals(response.status, scenario.status, JSON.stringify({ responseBody, requests }));
        assertEquals(responseBody.code, scenario.code);
      }
      assertEquals(createRpcCalls, 0);
      assertEquals(emailCalls, 0);
    } finally {
      globalThis.fetch = originalFetch;
      for (const [name, value] of previousEnvironment) {
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
    }
  },
});