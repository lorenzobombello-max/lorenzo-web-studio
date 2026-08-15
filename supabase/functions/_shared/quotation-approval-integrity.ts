import { canonicalizePricingConfig } from "./pricing-config.ts";

export const QUOTATION_APPROVAL_INTEGRITY_VERSION = "hmac-sha256-v1";
export const QUOTATION_APPROVAL_INTEGRITY_DOMAIN =
  "lws-quotation-approval-v1";

export interface QuotationApprovalIntegrityRoot {
  approvalId: string;
  contractVersion: number;
  intakeId: string;
  integrityRootVersion: 1;
  payloadSha256: string;
  pricingSnapshotId: string;
  quoteRequestId: string;
}

export interface QuotationApprovalIntegrity {
  algorithmVersion: typeof QUOTATION_APPROVAL_INTEGRITY_VERSION;
  keyId: string;
  mac: string;
  root: QuotationApprovalIntegrityRoot;
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

function integrityKey(secret: string, usages: KeyUsage[]): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    usages,
  );
}

export function canonicalizeQuotationApprovalIntegrity(
  root: QuotationApprovalIntegrityRoot,
  keyId: string,
): string {
  if (!/^v[1-9][0-9]*$/.test(keyId)) {
    throw new TypeError("INVALID_QUOTATION_APPROVAL_INTEGRITY_KEY_ID");
  }
  return canonicalizePricingConfig({
    integrityDomain: QUOTATION_APPROVAL_INTEGRITY_DOMAIN,
    algorithmVersion: QUOTATION_APPROVAL_INTEGRITY_VERSION,
    keyId,
    root,
  });
}

export async function createQuotationApprovalIntegrity(
  root: QuotationApprovalIntegrityRoot,
  keyId: string,
  secret: string,
): Promise<QuotationApprovalIntegrity> {
  if (new TextEncoder().encode(secret).byteLength < 32) {
    throw new TypeError("INVALID_QUOTATION_APPROVAL_INTEGRITY_SECRET");
  }
  const mac = await crypto.subtle.sign(
    "HMAC",
    await integrityKey(secret, ["sign"]),
    new TextEncoder().encode(
      canonicalizeQuotationApprovalIntegrity(root, keyId),
    ),
  );
  return {
    algorithmVersion: QUOTATION_APPROVAL_INTEGRITY_VERSION,
    keyId,
    mac: toHex(mac),
    root: structuredClone(root),
  };
}

export async function verifyQuotationApprovalIntegrity(
  integrity: QuotationApprovalIntegrity,
  secret: string,
): Promise<boolean> {
  const mac = fromHex(integrity.mac);
  if (!mac) return false;
  try {
    return await crypto.subtle.verify(
      "HMAC",
      await integrityKey(secret, ["verify"]),
      mac,
      new TextEncoder().encode(
        canonicalizeQuotationApprovalIntegrity(integrity.root, integrity.keyId),
      ),
    );
  } catch {
    return false;
  }
}