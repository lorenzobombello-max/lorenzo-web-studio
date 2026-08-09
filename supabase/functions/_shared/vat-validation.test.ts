import { assertEquals } from "jsr:@std/assert@1";
import { validateVatWithVies } from "./vat-validation.ts";

const checkedAt = new Date("2026-08-09T12:00:00.000Z");
const soapResponse = (valid: boolean) => `<?xml version="1.0"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><ns2:checkVatResponse xmlns:ns2="urn:ec.europa.eu:taxud:vies:services:checkVat:types"><ns2:countryCode>BE</ns2:countryCode><ns2:vatNumber>0123456749</ns2:vatNumber><ns2:requestDate>2026-08-09</ns2:requestDate><ns2:valid>${valid}</ns2:valid><ns2:name>SHOULD NOT BE STORED</ns2:name><ns2:address>SHOULD NOT BE STORED</ns2:address></ns2:checkVatResponse></soap:Body></soap:Envelope>`;

Deno.test("VIES maps an official valid response without retaining trader data", async () => {
  let requestBody = "";
  const result = await validateVatWithVies("BE0123456749", {
    fetchImpl: async (_input, init) => {
      requestBody = String(init?.body);
      return new Response(soapResponse(true), { status: 200 });
    },
    now: () => checkedAt,
  });
  assertEquals(result, { status: "valid", validatedAt: checkedAt.toISOString() });
  assertEquals(requestBody.includes("<urn:countryCode>BE</urn:countryCode>"), true);
  assertEquals(requestBody.includes("<urn:vatNumber>0123456749</urn:vatNumber>"), true);
});

Deno.test("VIES maps an official invalid response neutrally", async () => {
  const result = await validateVatWithVies("BE0123456749", {
    fetchImpl: async () => new Response(soapResponse(false), { status: 200 }),
    now: () => checkedAt,
  });
  assertEquals(result, { status: "invalid", validatedAt: checkedAt.toISOString() });
});

Deno.test("VIES faults and network failures are non-blocking unavailable results", async () => {
  const fault = await validateVatWithVies("BE0123456749", {
    fetchImpl: async () => new Response("<soap:Fault><faultstring>SERVICE_UNAVAILABLE</faultstring></soap:Fault>", { status: 500 }),
    now: () => checkedAt,
  });
  const network = await validateVatWithVies("BE0123456749", {
    fetchImpl: async () => { throw new TypeError("network unavailable"); },
    now: () => checkedAt,
  });
  assertEquals(fault, { status: "unavailable", validatedAt: checkedAt.toISOString() });
  assertEquals(network, { status: "unavailable", validatedAt: checkedAt.toISOString() });
});