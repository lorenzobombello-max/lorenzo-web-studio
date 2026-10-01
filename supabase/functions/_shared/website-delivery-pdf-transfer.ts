type Claim = Readonly<{
  execution_id: string;
  task_id: string;
  artifact_id: string;
  project_id: string;
  document_version: number;
  source_docx_sha256: string;
  generation_payload: unknown;
}>;

type Input = Readonly<{
  taskId: string;
  executionId: string;
  workflowRunId: string;
  workflowRunAttempt: string;
  pdfBytes: Uint8Array;
  idempotencyKey: string;
  actor: string;
}>;

type Dependencies = Readonly<{
  resolveClaim: (taskId: string, workflowRunId: string, workflowRunAttempt: string) => Promise<Claim>;
  validatePdf: (bytes: Uint8Array, generationPayload: unknown) => Promise<Readonly<{
    sha256: string;
    byteLength: number;
    pageCount: number;
  }>>;
  upload: (path: string, bytes: Uint8Array) => Promise<boolean>;
  readback: (path: string) => Promise<Uint8Array>;
  remove: (path: string) => Promise<void>;
  register: (input: Readonly<{
    executionId: string;
    workflowRunId: string;
    workflowRunAttempt: string;
    pdfSha256: string;
    pdfBytes: number;
    idempotencyKey: string;
    actor: string;
  }>) => Promise<Record<string, unknown>>;
}>;

function equalBytes(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left[index] ^ right[index];
  return difference === 0;
}

export async function completeWebsiteDeliveryPdfTransfer(input: Input, dependencies: Dependencies) {
  const claim = await dependencies.resolveClaim(input.taskId, input.workflowRunId, input.workflowRunAttempt);
  if (claim.task_id !== input.taskId || claim.execution_id !== input.executionId) {
    throw new Error("WEBSITE_DELIVERY_PDF_EXECUTION_BINDING_INVALID");
  }
  const validated = await dependencies.validatePdf(input.pdfBytes, claim.generation_payload);
  if (validated.byteLength !== input.pdfBytes.length || !/^[0-9a-f]{64}$/.test(validated.sha256)) {
    throw new Error("WEBSITE_DELIVERY_PDF_VALIDATION_RESULT_INVALID");
  }
  const storageObjectPath = `projects/${claim.project_id}/versions/${claim.document_version}/views/` +
    `${claim.source_docx_sha256}/${validated.sha256}.pdf`;
  const uploadCreated = await dependencies.upload(storageObjectPath, input.pdfBytes);
  try {
    const readback = await dependencies.readback(storageObjectPath);
    if (!equalBytes(readback, input.pdfBytes)) throw new Error("WEBSITE_DELIVERY_PDF_READBACK_MISMATCH");
  } catch (error) {
    if (uploadCreated) await dependencies.remove(storageObjectPath).catch(() => undefined);
    throw error;
  }
  const registration = await dependencies.register({
    executionId: input.executionId,
    workflowRunId: input.workflowRunId,
    workflowRunAttempt: input.workflowRunAttempt,
    pdfSha256: validated.sha256,
    pdfBytes: validated.byteLength,
    idempotencyKey: input.idempotencyKey,
    actor: input.actor,
  });
  return Object.freeze({ ...registration, storageObjectPath });
}