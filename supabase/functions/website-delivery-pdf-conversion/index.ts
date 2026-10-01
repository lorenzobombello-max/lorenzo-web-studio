import { createClient } from "npm:@supabase/supabase-js@2";
import { getSupabaseServerSecretKey, type SupabaseKeyBindingEnvironment } from "../_shared/supabase-key-bindings.ts";
import { verifyWebsiteDeliveryPdfOidcToken } from "../_shared/website-delivery-pdf-oidc.ts";
import { issueWebsiteDeliveryPdfSession, verifyWebsiteDeliveryPdfSession } from "../_shared/website-delivery-pdf-session.ts";
import { completeWebsiteDeliveryPdfTransfer } from "../_shared/website-delivery-pdf-transfer.ts";
import { validateWebsiteDeliveryPdf } from "../_shared/website-delivery-pdf-validation.ts";
import { handleWebsiteDeliveryPdfConversion } from "./handler.ts";

type Claim = Readonly<{
  execution_id: string;
  task_id: string;
  artifact_id: string;
  project_id: string;
  document_version: number;
  source_bucket_id: string;
  source_object_path: string;
  source_docx_sha256: string;
  source_docx_bytes: number;
  generation_payload_sha256: string;
  generation_payload: unknown;
  expires_at: string;
}>;

type C3HoldConfiguration = Readonly<{
  projectId: string;
  internalE2ERunId: string;
}>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function resolveWebsiteDeliveryPdfC3HoldConfiguration(
  environment: Pick<SupabaseKeyBindingEnvironment, "get">,
): C3HoldConfiguration | null {
  const mode = environment.get("LWS_DELIVERY_PDF_C3_TEST_HOLD_MODE") ?? "";
  const projectId = environment.get("LWS_DELIVERY_PDF_C3_TEST_HOLD_PROJECT_ID") ?? "";
  const internalE2ERunId = environment.get("LWS_DELIVERY_PDF_C3_TEST_HOLD_RUN_ID") ?? "";
  if (mode !== "TEST_ONLY_C3" || !UUID.test(projectId) || !UUID.test(internalE2ERunId)) {
    return null;
  }
  return { projectId, internalE2ERunId };
}

export async function resolveWebsiteDeliveryPdfC3TestHold(
  configuration: C3HoldConfiguration | null,
  input: Readonly<{
    projectId: string;
    taskId: string;
    workflowRunAttempt: string;
  }>,
  resolve: (args: Record<string, unknown>) => Promise<string | null>,
): Promise<string | undefined> {
  if (
    !configuration || input.workflowRunAttempt !== "1" ||
    input.projectId !== configuration.projectId
  ) return undefined;
  const holdUntil = await resolve({
    p_configured_project_id: configuration.projectId,
    p_configured_internal_e2e_run_id: configuration.internalE2ERunId,
    p_task_id: input.taskId,
    p_workflow_run_attempt: 1,
  });
  return holdUntil ?? undefined;
}

function equalBytes(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left[index] ^ right[index];
  return difference === 0;
}

export async function completeRegisteredWebsiteDeliveryPdfReplay(
  input: Readonly<{
    executionId: string;
    workflowRunId: string;
    workflowRunAttempt: string;
    idempotencyKey: string;
    actor: string;
    pdfBytes: Uint8Array;
  }>,
  rpc: (name: string, args: Record<string, unknown>) => Promise<Record<string, unknown>>,
): Promise<Record<string, unknown>> {
  const digest = await crypto.subtle.digest("SHA-256", Uint8Array.from(input.pdfBytes).buffer);
  const pdfSha256 = [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return await rpc("complete_website_delivery_pdf_conversion_v2", {
    p_execution_id: input.executionId,
    p_workflow_run_id: input.workflowRunId,
    p_workflow_run_attempt: Number(input.workflowRunAttempt),
    p_pdf_sha256: pdfSha256,
    p_pdf_bytes: input.pdfBytes.byteLength,
    p_idempotency_key: input.idempotencyKey,
    p_actor: input.actor,
  });
}

export function createWebsiteDeliveryPdfConversionRuntime(
  environment: SupabaseKeyBindingEnvironment = Deno.env,
  oidcFetch: typeof fetch = fetch,
) {
  const url = environment.get("SUPABASE_URL") ?? "";
  const key = getSupabaseServerSecretKey("default", environment);
  const audience = environment.get("LWS_DELIVERY_PDF_OIDC_AUDIENCE") ?? "";
  const workflowRepository = environment.get("LWS_DELIVERY_PDF_WORKFLOW_REPOSITORY") ?? "";
  const workflowRepositoryId = environment.get("LWS_DELIVERY_PDF_WORKFLOW_REPOSITORY_ID") ?? "";
  const workflowRef = environment.get("LWS_DELIVERY_PDF_WORKFLOW_REF") ?? "";
  const workflowRefName = environment.get("LWS_DELIVERY_PDF_WORKFLOW_REF_NAME") ?? "";
  const sessionSecret = environment.get("LWS_DELIVERY_PDF_SESSION_SECRET") ?? "";
  const c3HoldConfiguration = resolveWebsiteDeliveryPdfC3HoldConfiguration(environment);
  if (!url || !audience || !workflowRepository || !workflowRepositoryId || !workflowRef || !workflowRefName || sessionSecret.length < 32) {
    throw new Error("SERVER_CONFIGURATION_ERROR");
  }
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const rpc = async <T>(name: string, args: Record<string, unknown>): Promise<T> => {
    const { data, error } = await client.rpc(name, args);
    if (error || !data) throw new Error(error?.message || "RPC_FAILED");
    return data as T;
  };
  const authority = (runId: string, runAttempt: string) => ({
    audience, workflowRepository, workflowRepositoryId, workflowRef, workflowRefName, runId, runAttempt,
  });
  const verify = (token: string, runId: string, runAttempt: string) =>
    verifyWebsiteDeliveryPdfOidcToken(token, authority(runId, runAttempt), { fetch: oidcFetch });
  const resolveClaim = (taskId: string, runId: string, runAttempt: string) =>
    rpc<Claim>("claim_website_delivery_pdf_conversion_v2", {
    p_task_id: taskId,
    p_workflow_repository: workflowRepository,
    p_workflow_repository_id: workflowRepositoryId,
    p_workflow_ref_name: workflowRefName,
    p_workflow_ref: workflowRef,
    p_workflow_run_id: runId,
    p_workflow_run_attempt: Number(runAttempt),
    p_actor: `GITHUB_ACTIONS:${workflowRepository}:${runId}:${runAttempt}`,
  });
  return {
    claim: async (input: Readonly<{
      oidcToken: string;
      taskId: string;
      workflowRunId: string;
      workflowRunAttempt: string;
    }>) => {
      await verify(input.oidcToken, input.workflowRunId, input.workflowRunAttempt);
      const claim = await resolveClaim(input.taskId, input.workflowRunId, input.workflowRunAttempt);
      const testHoldUntil = await resolveWebsiteDeliveryPdfC3TestHold(
        c3HoldConfiguration,
        {
          projectId: claim.project_id,
          taskId: claim.task_id,
          workflowRunAttempt: input.workflowRunAttempt,
        },
        async (args) => {
          const { data, error } = await client.rpc(
            "resolve_website_delivery_pdf_c3_test_hold_v1",
            args,
          );
          if (error) throw new Error(error.message);
          return typeof data === "string" ? data : null;
        },
      );
      const { data, error } = await client.storage.from(claim.source_bucket_id)
        .createSignedUrl(claim.source_object_path, 600, { download: true });
      if (error || !data?.signedUrl) throw new Error(error?.message || "WEBSITE_DELIVERY_PDF_SOURCE_TRANSFER_FAILED");
      const sessionToken = await issueWebsiteDeliveryPdfSession({
        taskId: claim.task_id,
        executionId: claim.execution_id,
        workflowRunId: input.workflowRunId,
        workflowRunAttempt: input.workflowRunAttempt,
      }, sessionSecret, { ttlSeconds: 600 });
      return {
        executionId: claim.execution_id,
        taskId: claim.task_id,
        sourceUrl: data.signedUrl,
        sourceDocxSha256: claim.source_docx_sha256,
        sourceDocxBytes: claim.source_docx_bytes,
        generationPayloadSha256: claim.generation_payload_sha256,
        sessionToken,
        expiresAt: claim.expires_at,
        ...(testHoldUntil ? { testHoldUntil } : {}),
      };
    },
    complete: async (input: Readonly<{
      oidcToken: string;
      sessionToken: string;
      taskId: string;
      executionId: string;
      workflowRunId: string;
      workflowRunAttempt: string;
      idempotencyKey: string;
      pdfBytes: Uint8Array;
    }>) => {
      await verify(input.oidcToken, input.workflowRunId, input.workflowRunAttempt);
      await verifyWebsiteDeliveryPdfSession(input.sessionToken, {
        taskId: input.taskId,
        executionId: input.executionId,
        workflowRunId: input.workflowRunId,
        workflowRunAttempt: input.workflowRunAttempt,
      }, sessionSecret);
      const views = client.storage.from("website-delivery-document-views");
      const actor = `GITHUB_ACTIONS:${workflowRepository}:${input.workflowRunId}:${input.workflowRunAttempt}`;
      try {
        return await completeWebsiteDeliveryPdfTransfer({
        taskId: input.taskId,
        executionId: input.executionId,
        workflowRunId: input.workflowRunId,
        workflowRunAttempt: input.workflowRunAttempt,
        pdfBytes: input.pdfBytes,
        idempotencyKey: input.idempotencyKey,
        actor,
      }, {
        resolveClaim,
        validatePdf: validateWebsiteDeliveryPdf,
        upload: async (path, bytes) => {
          const { error } = await views.upload(path, bytes, { contentType: "application/pdf", upsert: false });
          if (!error) return true;
          const existing = await views.download(path);
          if (existing.error || !equalBytes(new Uint8Array(await existing.data.arrayBuffer()), bytes)) {
            throw new Error("WEBSITE_DELIVERY_PDF_UPLOAD_CONFLICT");
          }
          return false;
        },
        readback: async (path) => {
          const { data, error } = await views.download(path);
          if (error || !data) throw new Error(error?.message || "WEBSITE_DELIVERY_PDF_READBACK_FAILED");
          return new Uint8Array(await data.arrayBuffer());
        },
        remove: async (path) => {
          const { error } = await views.remove([path]);
          if (error) throw new Error(error.message);
        },
        register: (registration) => rpc("complete_website_delivery_pdf_conversion_v2", {
          p_execution_id: registration.executionId,
          p_workflow_run_id: registration.workflowRunId,
          p_workflow_run_attempt: Number(registration.workflowRunAttempt),
          p_pdf_sha256: registration.pdfSha256,
          p_pdf_bytes: registration.pdfBytes,
          p_idempotency_key: registration.idempotencyKey,
          p_actor: registration.actor,
        }),
        });
      } catch (error) {
        if (
          !(error instanceof Error) ||
          ![
            "WEBSITE_DELIVERY_PDF_VIEW_ALREADY_REGISTERED",
            "WEBSITE_DELIVERY_ALREADY_ACCEPTED",
          ].includes(error.message)
        ) throw error;
        return await completeRegisteredWebsiteDeliveryPdfReplay({
          executionId: input.executionId,
          workflowRunId: input.workflowRunId,
          workflowRunAttempt: input.workflowRunAttempt,
          idempotencyKey: input.idempotencyKey,
          actor,
          pdfBytes: input.pdfBytes,
        }, rpc);
      }
    },
  };
}

if (import.meta.main) {
  const runtime = createWebsiteDeliveryPdfConversionRuntime();
  Deno.serve((request) => handleWebsiteDeliveryPdfConversion(request, runtime));
}