import {
  type GitHubHttpClient,
  GitHubHttpError,
} from "../_shared/github-http.ts";

export type RepositoryInstallationVisibilityAuthority = Readonly<{
  appId: string;
  installationId: string;
  organization: string;
  repository: string;
}>;

export type RepositoryInstallationVisibilityDependencies = Readonly<{
  signAppJwt(appId: string): Promise<string>;
  http: GitHubHttpClient;
}>;

export class RepositoryInstallationVisibilityProofError extends Error {
  constructor() {
    super("REPOSITORY_INSTALLATION_VISIBILITY_PROOF_FAILED");
    this.name = "RepositoryInstallationVisibilityProofError";
  }
}

function isPositiveProof(value: unknown): boolean {
  return value !== null && typeof value === "object" &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype &&
    Reflect.ownKeys(value).length === 1 &&
    Object.hasOwn(value, "proven") &&
    (value as { proven?: unknown }).proven === true;
}

export function createExactRepositoryInstallationVisibilityProof(
  authority: RepositoryInstallationVisibilityAuthority,
  dependencies: RepositoryInstallationVisibilityDependencies,
): () => Promise<boolean> {
  return async () => {
    try {
      const appJwt = await dependencies.signAppJwt(authority.appId);
      const result = await dependencies.http.execute({
        kind: "REPOSITORY_INSTALLATION_PROOF",
        owner: authority.organization,
        repository: authority.repository,
        expectedInstallationId: authority.installationId,
        expectedOrganization: authority.organization,
        appJwt,
      });
      if (!isPositiveProof(result)) {
        throw new RepositoryInstallationVisibilityProofError();
      }
      return true;
    } catch (error) {
      if (
        error instanceof GitHubHttpError &&
        error.code === "GITHUB_HTTP_NOT_FOUND"
      ) return false;
      if (error instanceof GitHubHttpError) throw error;
      if (error instanceof RepositoryInstallationVisibilityProofError) {
        throw error;
      }
      throw new RepositoryInstallationVisibilityProofError();
    }
  };
}
