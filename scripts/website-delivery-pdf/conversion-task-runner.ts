type Input = Readonly<{
  taskId: string;
  workflowRunId: string;
  workflowRunAttempt: string;
  oidcToken: string;
  idempotencyKey: string;
}>;

type Claim = Readonly<{
  executionId: string;
  taskId: string;
  sourceUrl: string;
  sourceDocxSha256: string;
  sourceDocxBytes: number;
  sessionToken: string;
  testHoldUntil?: string;
}>;

type Dependencies = Readonly<{
  claim: (input: Input) => Promise<Claim>;
  download: (signedUrl: string) => Promise<Uint8Array>;
  convert: (docxBytes: Uint8Array) => Promise<Uint8Array>;
  complete: (input: Readonly<{
    oidcToken: string;
    sessionToken: string;
    taskId: string;
    executionId: string;
    workflowRunId: string;
    workflowRunAttempt: string;
    idempotencyKey: string;
    pdfBytes: Uint8Array;
  }>) => Promise<unknown>;
  waitUntil?: (deadline: string) => Promise<void>;
}>;

async function waitUntil(deadline: string): Promise<void> {
  const deadlineMs = Date.parse(deadline);
  if (!Number.isFinite(deadlineMs)) {
    throw new Error("WEBSITE_DELIVERY_PDF_TEST_HOLD_INVALID");
  }
  await new Promise((resolve) => setTimeout(resolve, Math.max(0, deadlineMs - Date.now())));
}

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes).buffer);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function runWebsiteDeliveryPdfConversionTask(input: Input, dependencies: Dependencies) {
  const claim = await dependencies.claim(input);
  if (claim.taskId !== input.taskId) throw new Error("WEBSITE_DELIVERY_PDF_TASK_BINDING_INVALID");
  if (claim.testHoldUntil && input.workflowRunAttempt === "1") {
    await (dependencies.waitUntil ?? waitUntil)(claim.testHoldUntil);
    throw new Error("WEBSITE_DELIVERY_PDF_TEST_HOLD_EXPIRED");
  }
  const docxBytes = await dependencies.download(claim.sourceUrl);
  if (docxBytes.length !== claim.sourceDocxBytes || await sha256(docxBytes) !== claim.sourceDocxSha256) {
    throw new Error("WEBSITE_DELIVERY_PDF_SOURCE_IDENTITY_MISMATCH");
  }
  const pdfBytes = await dependencies.convert(docxBytes);
  return await dependencies.complete({
    oidcToken: input.oidcToken,
    sessionToken: claim.sessionToken,
    taskId: input.taskId,
    executionId: claim.executionId,
    workflowRunId: input.workflowRunId,
    workflowRunAttempt: input.workflowRunAttempt,
    idempotencyKey: input.idempotencyKey,
    pdfBytes,
  });
}