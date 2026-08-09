export type VatValidationStatus = "valid" | "invalid" | "unavailable" | "not_checked";

export interface VatValidationResult {
  status: VatValidationStatus;
  validatedAt: string | null;
}

interface ViesValidationOptions {
  fetchImpl?: typeof fetch;
  endpoint?: string;
  timeoutMs?: number;
  now?: () => Date;
}

export const VIES_PRODUCTION_ENDPOINT = "https://ec.europa.eu/taxation_customs/vies/services/checkVatService";
export const VIES_TEST_ENDPOINT = "https://ec.europa.eu/taxation_customs/vies/test-services/checkVatTestService";

function elementValue(xml: string, name: string): string | null {
  const match = xml.match(new RegExp(`<(?:[\\w-]+:)?${name}(?:\\s[^>]*)?>([^<]*)<\\/(?:[\\w-]+:)?${name}>`, "i"));
  return match?.[1]?.trim() ?? null;
}

export async function validateVatWithVies(
  normalizedVatNumber: string,
  options: ViesValidationOptions = {},
): Promise<VatValidationResult> {
  const countryCode = normalizedVatNumber.slice(0, 2);
  const vatNumber = normalizedVatNumber.slice(2);
  const checkedAt = () => (options.now ?? (() => new Date()))().toISOString();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), options.timeoutMs ?? 6_000);

  try {
    const response = await (options.fetchImpl ?? fetch)(options.endpoint ?? VIES_PRODUCTION_ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "text/xml; charset=utf-8", SOAPAction: "" },
      body: `<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:ec.europa.eu:taxud:vies:services:checkVat:types"><soapenv:Header/><soapenv:Body><urn:checkVat><urn:countryCode>${countryCode}</urn:countryCode><urn:vatNumber>${vatNumber}</urn:vatNumber></urn:checkVat></soapenv:Body></soapenv:Envelope>`,
      signal: controller.signal,
    });
    const xml = await response.text();
    const valid = elementValue(xml, "valid");
    if (!response.ok || (valid !== "true" && valid !== "false")) {
      return { status: "unavailable", validatedAt: checkedAt() };
    }
    return {
      status: valid === "true" ? "valid" : "invalid",
      validatedAt: checkedAt(),
    };
  } catch {
    return { status: "unavailable", validatedAt: checkedAt() };
  } finally {
    clearTimeout(timeout);
  }
}