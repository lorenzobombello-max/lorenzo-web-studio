import { createClient } from "npm:@supabase/supabase-js@2";
import { loadGitHubAppConfig } from "../_shared/github-app-config.ts";
import {
  createGitHubAppTokenBroker,
  type GitHubTokenExchangeInput,
} from "../_shared/github-app-token.ts";
import { verifyGitHubActionsOidcToken } from "../_shared/website-project-preview-oidc-broker.ts";
import { getSupabaseServerSecretKey, type SupabaseKeyBindingEnvironment } from "../_shared/supabase-key-bindings.ts";
import { initializeGitHubAppInputSigner } from "../github-app-gate6-probe/runtime.ts";
import { handleWebsiteProjectPreviewSourceToken } from "./handler.ts";
import { createWebsiteProjectPreviewSourceTokenService } from "./service.ts";

export function createWebsiteProjectPreviewGitHubTokenExchange(
  runtimeFetch: typeof fetch,
) {
  return async (input: GitHubTokenExchangeInput, signal?: AbortSignal) => {
    const response = await runtimeFetch(
      `https://api.github.com/app/installations/${input.installationId}/access_tokens`,
      {
        method: "POST",
        redirect: "error",
        signal: signal ?? AbortSignal.timeout(10_000),
        headers: {
          accept: "application/vnd.github+json",
          authorization: `Bearer ${input.appJwt}`,
          "content-type": "application/json",
          "x-github-api-version": "2022-11-28",
        },
        body: JSON.stringify({
          repository_ids: input.repositoryIds.map(Number),
          permissions: input.permissions,
        }),
      },
    );
    if (!response.ok) throw new Error("GITHUB_TOKEN_EXCHANGE_FAILED");
    const body = await response.json() as Record<string, unknown>;
    return {
      token: body.token,
      expiresAt: body.expires_at,
      repositorySelection: body.repository_selection,
      permissions: body.permissions,
    };
  };
}

export async function createWebsiteProjectPreviewSourceTokenRuntime(
  environment: SupabaseKeyBindingEnvironment = Deno.env,
  runtimeFetch: typeof fetch = fetch,
) {
  const supabaseUrl = environment.get("SUPABASE_URL") ?? "";
  const audience = environment.get("LWS_PREVIEW_OIDC_AUDIENCE") ?? "";
  const workflowRepository = environment.get("LWS_PREVIEW_WORKFLOW_REPOSITORY") ?? "";
  const workflowRepositoryId = environment.get("LWS_PREVIEW_WORKFLOW_REPOSITORY_ID") ?? "";
  const workflowRef = environment.get("LWS_PREVIEW_WORKFLOW_REF") ?? "";
  const workflowRefName = environment.get("LWS_PREVIEW_WORKFLOW_REF_NAME") ?? "";
  if (!supabaseUrl || !audience || !workflowRepository || !workflowRepositoryId || !workflowRef || !workflowRefName) {
    throw new Error("SERVER_CONFIGURATION_ERROR");
  }

  const config = loadGitHubAppConfig(environment);
  if (config.target !== "PRODUCTION") throw new Error("GITHUB_TOKEN_AUTHORITY_INVALID");
  const signer = await initializeGitHubAppInputSigner(config.privateKey);
  const client = createClient(supabaseUrl, getSupabaseServerSecretKey("default", environment), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const broker = createGitHubAppTokenBroker({
    now: Date.now,
    sign: (_privateKey, signingInput) => signer(signingInput),
    exchange: createWebsiteProjectPreviewGitHubTokenExchange(runtimeFetch),
  });

  return createWebsiteProjectPreviewSourceTokenService({
    resolveAuthority: async (input) => {
      const { data, error } = await client.rpc("resolve_website_project_preview_artifact_authority_v1", {
        p_lease_id: input.leaseId,
        p_build_id: input.buildId,
        p_workflow_run_id: Number(input.workflowRunId),
      });
      if (error || !data) throw new Error(error?.message || "PROJECT_PREVIEW_ARTIFACT_AUTHORITY_INVALID");
      const resolved = data as Record<string, unknown>;
      return {
        audience,
        workflowRepository,
        workflowRepositoryId,
        workflowRef,
        workflowRefName,
        customerRepository: String(resolved.repository ?? ""),
        customerRepositoryId: String(resolved.repositoryId ?? ""),
        customerCommitSha: String(resolved.commitSha ?? ""),
        runId: String(resolved.runId ?? ""),
        leaseId: String(resolved.leaseId ?? ""),
        buildId: String(resolved.buildId ?? ""),
      };
    },
    verifyOidc: (token, authority) => verifyGitHubActionsOidcToken(token, authority, { fetch: runtimeFetch }),
    issueInstallationToken: async (input) => {
      const [owner] = input.repository.split("/");
      if (owner !== config.organization || input.repositoryIds.length !== 1 || input.permissions.contents !== "read") {
        throw new Error("GITHUB_TOKEN_AUTHORITY_INVALID");
      }
      return await broker.issue(
        config,
        {
          websiteWorkContextId: input.leaseId,
          target: "PRODUCTION",
          organization: owner,
          operation: "WEBSITE_PROJECT_FILES_READ",
          repositoryIds: input.repositoryIds,
        },
        {
          websiteWorkContextId: input.leaseId,
          target: "PRODUCTION",
          organization: owner,
          repositoryIds: input.repositoryIds,
        },
      );
    },
  });
}

if (import.meta.main) {
  const service = await createWebsiteProjectPreviewSourceTokenRuntime();
  Deno.serve((request) => handleWebsiteProjectPreviewSourceToken(request, service));
}
