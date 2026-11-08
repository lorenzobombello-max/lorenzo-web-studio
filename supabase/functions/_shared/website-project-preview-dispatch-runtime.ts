import { loadWebsiteProjectPreviewDispatchAppConfig } from "./github-app-config.ts";
import { createGitHubAppTokenBroker } from "./github-app-token.ts";
import { createGitHubHttpClient } from "./github-http.ts";
import { initializeGitHubAppInputSigner } from "../github-app-gate6-probe/runtime.ts";
import { createWebsiteProjectPreviewDispatch, type PreviewDispatchRpc } from "./website-project-preview-dispatch.ts";

export function createPreviewPlatformTokenProvider(
  operation: "WEBSITE_PROJECT_PREVIEW_DISPATCH" | "WEBSITE_PROJECT_PREVIEW_MONITOR" = "WEBSITE_PROJECT_PREVIEW_DISPATCH",
) {
  const config = loadWebsiteProjectPreviewDispatchAppConfig();
  return async (leaseId: string) => {
    const signer = await initializeGitHubAppInputSigner(config.privateKey);
    const http = createGitHubHttpClient({ fetch });
    const broker = createGitHubAppTokenBroker({
      now: Date.now,
      sign: (_key, input) => signer(input),
      exchange: async (input) => {
        const result = await http.execute({ kind: "TOKEN_EXCHANGE",
          installationId: input.installationId, appJwt: input.appJwt,
          repositoryIds: input.repositoryIds, permissions: input.permissions });
        if (!("token" in result) || !("expiresAt" in result)) throw new Error("GITHUB_TOKEN_EXCHANGE_FAILED");
        return result;
      },
    });
    const authority = { websiteWorkContextId: leaseId, target: "PRODUCTION" as const,
      organization: config.organization, repositoryIds: [config.repositoryId] };
    return await broker.issue(config, { ...authority, operation }, authority);
  };
}

export function createWebsiteProjectPreviewRuntimeDispatch(client: PreviewDispatchRpc) {
  return createWebsiteProjectPreviewDispatch({
    client,
    workflowSha: Deno.env.get("LWS_PREVIEW_WORKFLOW_SHA") ?? "",
    acquireToken: createPreviewPlatformTokenProvider(),
    fetch: (request) => fetch(request),
  });
}
