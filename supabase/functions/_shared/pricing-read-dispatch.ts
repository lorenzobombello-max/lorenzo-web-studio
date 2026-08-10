import { corsHeaders } from "./cors.ts";
import {
  adminPricingReadResponse,
  customerPricingReadResponse,
  type PricingReadResponse,
} from "./pricing-read-response.ts";
import { verifyPricingSnapshotIntegrity } from "./pricing-snapshot-integrity.ts";
import { hashAdminIntakeToken, hashIntakeToken } from "./security.ts";
import { validateToken } from "./validation.ts";

type PricingReadActor = "customer" | "admin";

interface PricingReadRpcResult {
  data: unknown;
  error: unknown;
}

export interface PricingReadRpcClient {
  rpc(
    functionName: string,
    parameters: Record<string, unknown>,
  ): PromiseLike<PricingReadRpcResult>;
}

interface PricingReadDispatchDependencies {
  hashCustomerToken: (token: string) => Promise<string>;
  hashAdminToken: (token: string) => Promise<string>;
  verifyIntegrity?: (
    snapshot: object,
    context: string,
    integrity: unknown,
  ) => Promise<boolean>;
}

const DEFAULT_DEPENDENCIES: PricingReadDispatchDependencies = {
  hashCustomerToken: hashIntakeToken,
  hashAdminToken: hashAdminIntakeToken,
  verifyIntegrity: verifyPricingSnapshotIntegrity,
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

async function authenticatePricingReadRow(
  actor: PricingReadActor,
  rowValue: unknown,
  verifyIntegrity: (
    snapshot: object,
    context: string,
    integrity: unknown,
  ) => Promise<boolean>,
): Promise<unknown> {
  if (!isRecord(rowValue)) return rowValue;
  if (actor === "admin" && rowValue.snapshot_contract_version === null) {
    return rowValue;
  }
  const verified = isRecord(rowValue.integrity_snapshot) &&
    typeof rowValue.integrity_context === "string" &&
    await verifyIntegrity(
      rowValue.integrity_snapshot,
      rowValue.integrity_context,
      rowValue.integrity_metadata,
    );
  return verified ? rowValue : { ...rowValue, snapshot_present: false };
}

function jsonPricingResponse(
  response: PricingReadResponse,
  origin: string | null,
): Response {
  return new Response(JSON.stringify(response.body), {
    status: response.status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
    },
  });
}

function unauthorizedPricingRead(actor: PricingReadActor): PricingReadResponse {
  return actor === "customer"
    ? customerPricingReadResponse(null, false)
    : adminPricingReadResponse(null, false);
}

function failedPricingRead(actor: PricingReadActor): PricingReadResponse {
  return actor === "customer"
    ? customerPricingReadResponse(null, true)
    : adminPricingReadResponse(null, true);
}

export async function dispatchPricingRead(
  actor: PricingReadActor,
  rawToken: unknown,
  origin: string | null,
  supabase: PricingReadRpcClient,
  dependencies: PricingReadDispatchDependencies = DEFAULT_DEPENDENCIES,
): Promise<Response> {
  let tokenHash: string;
  try {
    const token = validateToken(rawToken);
    tokenHash = actor === "customer"
      ? await dependencies.hashCustomerToken(token)
      : await dependencies.hashAdminToken(token);
  } catch {
    return jsonPricingResponse(unauthorizedPricingRead(actor), origin);
  }

  try {
    const functionName = actor === "customer"
      ? "inspect_customer_pricing_read_v3"
      : "inspect_admin_pricing_read_v3";
    const parameterName = actor === "customer"
      ? "p_access_token_hash"
      : "p_admin_access_token_hash";
    const { data, error } = await supabase.rpc(functionName, {
      [parameterName]: tokenHash,
    });
    const row = await authenticatePricingReadRow(
      actor,
      Array.isArray(data) ? data[0] : null,
      dependencies.verifyIntegrity ?? verifyPricingSnapshotIntegrity,
    );
    const response = actor === "customer"
      ? customerPricingReadResponse(row, Boolean(error))
      : adminPricingReadResponse(row, Boolean(error));
    return jsonPricingResponse(response, origin);
  } catch {
    return jsonPricingResponse(failedPricingRead(actor), origin);
  }
}
