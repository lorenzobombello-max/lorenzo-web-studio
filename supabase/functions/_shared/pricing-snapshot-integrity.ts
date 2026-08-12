import { canonicalizePricingConfig } from "./pricing-config.ts";

export const PRICING_SNAPSHOT_INTEGRITY_VERSION = "hmac-sha256-v1";
export const PRICING_SNAPSHOT_INTEGRITY_DOMAIN = "lws-pricing-snapshot-v1";

export interface PricingSnapshotIntegrity {
  algorithmVersion: typeof PRICING_SNAPSHOT_INTEGRITY_VERSION;
  keyId: string;
  mac: string;
}

export interface PricingSnapshotIntegrityRoot {
  snapshotContractVersion: unknown;
  pricingConfigVersion: unknown;
  pricingConfigHash: unknown;
  normalizedScope: unknown;
  calculation: unknown;
  packageAdvice: unknown;
  budgetEvaluation: unknown;
  packageDefinition?: unknown;
  recurringServices?: unknown;
}

function toHex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function fromHex(value: string): ArrayBuffer | null {
  if (!/^[0-9a-f]{64}$/.test(value)) return null;
  return Uint8Array.from(
    value.match(/.{2}/g) ?? [],
    (byte) => parseInt(byte, 16),
  ).buffer as ArrayBuffer;
}

function integritySecret(keyId: string): string {
  if (!/^v[1-9][0-9]*$/.test(keyId)) {
    throw new Error("Invalid pricing snapshot integrity key id");
  }
  const secret = Deno.env.get(
    `PRICING_SNAPSHOT_INTEGRITY_KEY_${keyId.toUpperCase()}`,
  );
  if (!secret || new TextEncoder().encode(secret).byteLength < 32) {
    throw new Error("Missing pricing snapshot integrity key");
  }
  return secret;
}

function integrityKey(secret: string, usages: KeyUsage[]): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    usages,
  );
}

export function pricingSnapshotIntegrityRoot(
  snapshot: object,
): PricingSnapshotIntegrityRoot {
  const value = snapshot as Record<string, unknown>;
  const root: PricingSnapshotIntegrityRoot = {
    snapshotContractVersion: value.snapshotContractVersion,
    pricingConfigVersion: value.pricingConfigVersion,
    pricingConfigHash: value.pricingConfigHash,
    normalizedScope: value.normalizedScope,
    calculation: value.calculation,
    packageAdvice: value.packageAdvice,
    budgetEvaluation: value.budgetEvaluation,
  };
  if (value.snapshotContractVersion === 3) {
    root.packageDefinition = value.packageDefinition;
  }
  if (value.recurringServices !== undefined) {
    root.recurringServices = value.recurringServices;
  }
  return root;
}

export function canonicalizePricingSnapshot(
  snapshot: object,
  context: string,
  keyId: string,
): string {
  return canonicalizePricingConfig({
    integrityDomain: PRICING_SNAPSHOT_INTEGRITY_DOMAIN,
    algorithmVersion: PRICING_SNAPSHOT_INTEGRITY_VERSION,
    keyId,
    context,
    snapshot: pricingSnapshotIntegrityRoot(snapshot),
  });
}

export async function createPricingSnapshotIntegrity(
  snapshot: object,
  context: string,
  keyId = Deno.env.get("PRICING_SNAPSHOT_INTEGRITY_ACTIVE_KEY_ID") || "v1",
  secret = integritySecret(keyId),
): Promise<PricingSnapshotIntegrity> {
  const mac = await crypto.subtle.sign(
    "HMAC",
    await integrityKey(secret, ["sign"]),
    new TextEncoder().encode(
      canonicalizePricingSnapshot(snapshot, context, keyId),
    ),
  );
  return {
    algorithmVersion: PRICING_SNAPSHOT_INTEGRITY_VERSION,
    keyId,
    mac: toHex(mac),
  };
}

export async function verifyPricingSnapshotIntegrity(
  snapshot: object,
  context: string,
  integrity: unknown,
  resolveSecret: (keyId: string) => string = integritySecret,
): Promise<boolean> {
  if (
    !integrity || typeof integrity !== "object" || Array.isArray(integrity)
  ) return false;
  const metadata = integrity as Record<string, unknown>;
  const metadataKeys = Object.keys(metadata).sort();
  if (
    metadataKeys.length !== 3 ||
    metadataKeys[0] !== "algorithmVersion" || metadataKeys[1] !== "keyId" ||
    metadataKeys[2] !== "mac" ||
    metadata.algorithmVersion !== PRICING_SNAPSHOT_INTEGRITY_VERSION ||
    typeof metadata.keyId !== "string" ||
    !/^v[1-9][0-9]*$/.test(metadata.keyId) ||
    typeof metadata.mac !== "string"
  ) return false;
  const mac = fromHex(metadata.mac);
  if (!mac) return false;

  try {
    return await crypto.subtle.verify(
      "HMAC",
      await integrityKey(resolveSecret(metadata.keyId), ["verify"]),
      mac,
      new TextEncoder().encode(
        canonicalizePricingSnapshot(snapshot, context, metadata.keyId),
      ),
    );
  } catch {
    return false;
  }
}
