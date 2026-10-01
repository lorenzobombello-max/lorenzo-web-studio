type Binding = Readonly<{
  taskId: string;
  executionId: string;
  workflowRunId: string;
  workflowRunAttempt: string;
}>;

function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function decodeBase64Url(value: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("WEBSITE_DELIVERY_PDF_SESSION_INVALID");
  try {
    const decoded = atob(value.replaceAll("-", "+").replaceAll("_", "/").padEnd(Math.ceil(value.length / 4) * 4, "="));
    return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
  } catch {
    throw new Error("WEBSITE_DELIVERY_PDF_SESSION_INVALID");
  }
}

async function key(secret: string): Promise<CryptoKey> {
  if (secret.length < 32) throw new Error("WEBSITE_DELIVERY_PDF_SESSION_SECRET_INVALID");
  return await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

export async function issueWebsiteDeliveryPdfSession(
  binding: Binding,
  secret: string,
  options: Readonly<{ now?: () => number; ttlSeconds?: number }> = {},
): Promise<string> {
  const ttlSeconds = options.ttlSeconds ?? 600;
  if (!binding.taskId || !binding.executionId || !/^[1-9][0-9]*$/.test(binding.workflowRunId)
    || !/^[1-9][0-9]*$/.test(binding.workflowRunAttempt)
    || !Number.isInteger(ttlSeconds) || ttlSeconds < 1 || ttlSeconds > 900) {
    throw new Error("WEBSITE_DELIVERY_PDF_SESSION_BINDING_INVALID");
  }
  const payload = base64Url(new TextEncoder().encode(JSON.stringify({
    ...binding,
    exp: Math.floor((options.now?.() ?? Date.now()) / 1000) + ttlSeconds,
  })));
  const signature = await crypto.subtle.sign("HMAC", await key(secret), new TextEncoder().encode(payload));
  return `${payload}.${base64Url(new Uint8Array(signature))}`;
}

export async function verifyWebsiteDeliveryPdfSession(
  token: string,
  expected: Binding,
  secret: string,
  options: Readonly<{ now?: () => number }> = {},
): Promise<Binding> {
  const [payload, signature, extra] = String(token || "").split(".");
  if (!payload || !signature || extra !== undefined) throw new Error("WEBSITE_DELIVERY_PDF_SESSION_INVALID");
  const valid = await crypto.subtle.verify(
    "HMAC",
    await key(secret),
    Uint8Array.from(decodeBase64Url(signature)).buffer,
    new TextEncoder().encode(payload),
  );
  if (!valid) throw new Error("WEBSITE_DELIVERY_PDF_SESSION_SIGNATURE_INVALID");
  let claims: Record<string, unknown>;
  try {
    claims = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(decodeBase64Url(payload)));
  } catch {
    throw new Error("WEBSITE_DELIVERY_PDF_SESSION_INVALID");
  }
  if (claims.taskId !== expected.taskId || claims.executionId !== expected.executionId
    || claims.workflowRunId !== expected.workflowRunId || claims.workflowRunAttempt !== expected.workflowRunAttempt) {
    throw new Error("WEBSITE_DELIVERY_PDF_SESSION_BINDING_INVALID");
  }
  if (!Number.isInteger(claims.exp) || Number(claims.exp) <= Math.floor((options.now?.() ?? Date.now()) / 1000)) {
    throw new Error("WEBSITE_DELIVERY_PDF_SESSION_EXPIRED");
  }
  return Object.freeze({ ...expected });
}