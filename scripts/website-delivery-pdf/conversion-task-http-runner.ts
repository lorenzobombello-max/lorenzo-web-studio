import { join } from "jsr:@std/path@1";
import { runWebsiteDeliveryPdfConversionTask } from "./conversion-task-runner.ts";
import { exportWithLibreOffice } from "./libreoffice-pdf-exporter.ts";

type Input = Readonly<{
  endpoint: string;
  taskId: string;
  workflowRunId: string;
  workflowRunAttempt: string;
  oidcToken: string;
  idempotencyKey: string;
}>;

type Dependencies = Readonly<{
  fetch?: typeof fetch;
  convert?: (docxBytes: Uint8Array) => Promise<Uint8Array>;
  waitUntil?: (deadline: string) => Promise<void>;
}>;

async function responseJson(response: Response): Promise<Record<string, unknown>> {
  const body = await response.json().catch(() => null) as Record<string, unknown> | null;
  if (!response.ok || !body || body.ok !== true) {
    throw new Error(String(body?.code ?? `WEBSITE_DELIVERY_PDF_HTTP_${response.status}`));
  }
  return body;
}

export async function convertWebsiteDeliveryDocxWithLibreOffice(
  docxBytes: Uint8Array,
): Promise<Uint8Array> {
  const directory = await Deno.makeTempDir({ prefix: "lws-website-delivery-runner-" });
  try {
    const inputPath = join(directory, "source.docx");
    const outputPath = join(directory, "result.pdf");
    await Deno.writeFile(inputPath, docxBytes);
    await exportWithLibreOffice(inputPath, outputPath);
    return await Deno.readFile(outputPath);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}

export async function runWebsiteDeliveryPdfConversionOverHttp(
  input: Input,
  dependencies: Dependencies = {},
): Promise<unknown> {
  const fetcher = dependencies.fetch ?? fetch;
  return await runWebsiteDeliveryPdfConversionTask(input, {
    claim: async ({ taskId, workflowRunId, workflowRunAttempt, oidcToken }) => {
      const response = await fetcher(input.endpoint, {
        method: "POST",
        headers: { authorization: `Bearer ${oidcToken}`, "content-type": "application/json" },
        body: JSON.stringify({ action: "claim", taskId, workflowRunId, workflowRunAttempt }),
      });
      const body = await responseJson(response);
      return {
        executionId: String(body.executionId ?? ""),
        taskId: String(body.taskId ?? ""),
        sourceUrl: String(body.sourceUrl ?? ""),
        sourceDocxSha256: String(body.sourceDocxSha256 ?? ""),
        sourceDocxBytes: Number(body.sourceDocxBytes),
        sessionToken: String(body.sessionToken ?? ""),
        testHoldUntil: typeof body.testHoldUntil === "string" ? body.testHoldUntil : undefined,
      };
    },
    waitUntil: dependencies.waitUntil,
    download: async (signedUrl) => {
      const response = await fetcher(signedUrl);
      if (!response.ok) throw new Error(`WEBSITE_DELIVERY_PDF_DOWNLOAD_${response.status}`);
      return new Uint8Array(await response.arrayBuffer());
    },
    convert: dependencies.convert ?? convertWebsiteDeliveryDocxWithLibreOffice,
    complete: async (completion) => {
      const response = await fetcher(`${input.endpoint}?action=complete`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${completion.oidcToken}`,
          "content-type": "application/pdf",
          "x-lws-conversion-session": completion.sessionToken,
          "x-lws-task-id": completion.taskId,
          "x-lws-execution-id": completion.executionId,
          "x-lws-workflow-run-id": completion.workflowRunId,
          "x-lws-workflow-run-attempt": completion.workflowRunAttempt,
          "x-lws-idempotency-key": completion.idempotencyKey,
        },
        body: Uint8Array.from(completion.pdfBytes).buffer,
      });
      return await responseJson(response);
    },
  });
}