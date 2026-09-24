import type { WebsiteProjectPreviewOidcAuthority } from "../_shared/website-project-preview-oidc-broker.ts";

type SourceTokenInput = Readonly<{
  oidcToken: string;
  leaseId: string;
  buildId: string;
  workflowRunId: string;
}>;

type SourceTokenLease = Readonly<{ token: string; expiresAt: string }>;

type SourceTokenDependencies = Readonly<{
  resolveAuthority(input: Omit<SourceTokenInput, "oidcToken">): PromiseLike<WebsiteProjectPreviewOidcAuthority>;
  verifyOidc(
    token: string,
    authority: WebsiteProjectPreviewOidcAuthority,
  ): PromiseLike<WebsiteProjectPreviewOidcAuthority>;
  issueInstallationToken(input: Readonly<{
    leaseId: string;
    repository: string;
    repositoryIds: readonly [string];
    permissions: Readonly<{ contents: "read" }>;
  }>): PromiseLike<SourceTokenLease>;
}>;

export function createWebsiteProjectPreviewSourceTokenService(
  dependencies: SourceTokenDependencies,
) {
  return Object.freeze({
    async issue(input: SourceTokenInput): Promise<SourceTokenLease> {
      const authority = await dependencies.resolveAuthority({
        leaseId: input.leaseId,
        buildId: input.buildId,
        workflowRunId: input.workflowRunId,
      });
      const verified = await dependencies.verifyOidc(input.oidcToken, authority);
      return await dependencies.issueInstallationToken(Object.freeze({
        leaseId: verified.leaseId,
        repository: verified.customerRepository,
        repositoryIds: Object.freeze([verified.customerRepositoryId]) as readonly [string],
        permissions: Object.freeze({ contents: "read" }),
      }));
    },
  });
}
