import type { GitHubTask13RuntimeConfig } from "../_shared/github-app-config.ts";
import {
  GitHubHttpError,
  type GitHubRepositoryMetadata,
} from "../_shared/github-http.ts";
import {
  GitHubLabPrivateVisibilityUnprovenError,
  GitHubLabRepositoryTokenError,
} from "../_shared/github-repository-runtime.ts";

export const TASK13_SYNTHETIC_AUTHORITY = Object.freeze({
  websiteWorkContextId: "33a61b58-1d55-4624-bdb7-3c724d35ebcc",
  websiteWorkspaceId: "4dfe44a5-60d0-4728-b62b-ef87aa838976",
  recordClassification: "internal_e2e" as const,
  environment: "TEST" as const,
  customerBinding: null,
  dossierBinding: null,
  organization: "lorenzo-web-solutions-lab",
  repository: "lws-web-33a61b581d554624bdb73c724d35ebcc",
  installationId: "161461160",
});

export type Task13LabReadonlyResult = Readonly<{
  principal_type: "GITHUB_APP_INSTALLATION";
  installation_id_match: true;
  private_lab_visibility_proven: true;
  found: boolean;
  repository_id?: string;
  node_id_present?: true;
  owner?: "lorenzo-web-solutions-lab";
  name?: "lws-web-33a61b581d554624bdb73c724d35ebcc";
  private?: true;
  visibility?: "PRIVATE";
  default_branch_present?: boolean;
  created_at_present?: true;
}>;

export type Task13LabReadonlyErrorCode =
  | "TASK13_LAB_PRIVATE_VISIBILITY_UNPROVEN"
  | "TASK13_LAB_RECONCILIATION_TOKEN_FAILED"
  | "TASK13_LAB_RECONCILIATION_READ_FAILED"
  | "TASK13_LAB_RECONCILIATION_RESPONSE_INVALID";

export class Task13LabReadonlyError extends Error {
  constructor(readonly code: Task13LabReadonlyErrorCode) {
    super(code);
    this.name = "Task13LabReadonlyError";
  }
}

export type Task13LabReadonlyDependencies = Readonly<{
  readRepository(
    input: Readonly<{
      websiteWorkContextId: string;
      organization: string;
      repository: string;
    }>,
  ): Promise<GitHubRepositoryMetadata>;
}>;

function projectFound(
  metadata: GitHubRepositoryMetadata,
): Task13LabReadonlyResult {
  if (
    metadata.owner !== TASK13_SYNTHETIC_AUTHORITY.organization ||
    metadata.name !== TASK13_SYNTHETIC_AUTHORITY.repository ||
    metadata.private !== true || !metadata.repositoryId || !metadata.nodeId ||
    !Number.isFinite(Date.parse(metadata.createdAt))
  ) {
    throw new Task13LabReadonlyError(
      "TASK13_LAB_RECONCILIATION_RESPONSE_INVALID",
    );
  }
  return Object.freeze({
    principal_type: "GITHUB_APP_INSTALLATION",
    installation_id_match: true,
    private_lab_visibility_proven: true,
    found: true,
    repository_id: metadata.repositoryId,
    node_id_present: true,
    owner: TASK13_SYNTHETIC_AUTHORITY.organization,
    name: TASK13_SYNTHETIC_AUTHORITY.repository,
    private: true,
    visibility: "PRIVATE",
    default_branch_present: metadata.defaultBranch.length > 0,
    created_at_present: true,
  });
}

export function createTask13LabReadonlyReconciler(
  config: GitHubTask13RuntimeConfig,
  dependencies: Task13LabReadonlyDependencies,
) {
  if (
    config.lab.target !== "TEST" ||
    config.lab.installationId !== TASK13_SYNTHETIC_AUTHORITY.installationId ||
    config.lab.organization !== TASK13_SYNTHETIC_AUTHORITY.organization
  ) throw new Task13LabReadonlyError("TASK13_LAB_RECONCILIATION_TOKEN_FAILED");

  return async (): Promise<Task13LabReadonlyResult> => {
    try {
      const result = await dependencies.readRepository({
        websiteWorkContextId: TASK13_SYNTHETIC_AUTHORITY.websiteWorkContextId,
        organization: TASK13_SYNTHETIC_AUTHORITY.organization,
        repository: TASK13_SYNTHETIC_AUTHORITY.repository,
      });
      return projectFound(result);
    } catch (error) {
      if (error instanceof Task13LabReadonlyError) throw error;
      if (error instanceof GitHubLabPrivateVisibilityUnprovenError) {
        throw new Task13LabReadonlyError(
          "TASK13_LAB_PRIVATE_VISIBILITY_UNPROVEN",
        );
      }
      if (error instanceof GitHubLabRepositoryTokenError) {
        throw new Task13LabReadonlyError(
          "TASK13_LAB_RECONCILIATION_TOKEN_FAILED",
        );
      }
      if (
        error instanceof GitHubHttpError &&
        error.code === "GITHUB_HTTP_NOT_FOUND"
      ) {
        return Object.freeze({
          principal_type: "GITHUB_APP_INSTALLATION",
          installation_id_match: true,
          private_lab_visibility_proven: true,
          found: false,
        });
      }
      if (
        error instanceof GitHubHttpError &&
        error.code === "GITHUB_HTTP_RESPONSE_INVALID"
      ) {
        throw new Task13LabReadonlyError(
          "TASK13_LAB_RECONCILIATION_RESPONSE_INVALID",
        );
      }
      throw new Task13LabReadonlyError("TASK13_LAB_RECONCILIATION_READ_FAILED");
    }
  };
}
