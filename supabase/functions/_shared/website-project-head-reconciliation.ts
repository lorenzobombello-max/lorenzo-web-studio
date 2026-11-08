import type {
  WebsiteProjectFilesAuthority,
  WebsiteProjectFilesProvider,
} from "./website-project-files-provider.ts";

type Rpc = {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { message: string } | null }>;
};
export const RECONCILIATION_QUOTE_ID = "7458c346-dfc9-40f3-ad0e-cb94a16636bf";

export async function reconcileWebsiteProjectHead(
  quoteRequestId: string,
  expectedCommitSha: string,
  dependencies: {
    caller: Rpc;
    finalizer: Rpc;
    provider: Pick<WebsiteProjectFilesProvider, "resolveSnapshot">;
  },
): Promise<string> {
  if (quoteRequestId !== RECONCILIATION_QUOTE_ID) {
    throw new Error("PROJECT_HEAD_RECONCILIATION_NOT_ENABLED");
  }
  const acquired = await dependencies.caller.rpc(
    "acquire_website_project_files_read_v1",
    {
      p_quote_request_id: quoteRequestId,
      p_read_kind: "DIRECTORY",
    },
  );
  if (acquired.error) throw new Error(acquired.error.message);
  const authority = acquired.data as WebsiteProjectFilesAuthority;
  if (!authority?.leaseId) {
    throw new Error("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
  try {
    const snapshot = await dependencies.provider.resolveSnapshot(authority);
    const finalized = await dependencies.finalizer.rpc(
      "reconcile_website_project_repository_head_v1",
      {
        p_lease_id: authority.leaseId,
        p_expected_commit_sha: expectedCommitSha,
        p_verified_commit_sha: snapshot.commitSha,
      },
    );
    if (finalized.error) throw new Error(finalized.error.message);
    if (!finalized.data || typeof finalized.data !== "object"
      || !("commitSha" in finalized.data)
      || finalized.data.commitSha !== snapshot.commitSha) {
      throw new Error("PROJECT_HEAD_RESPONSE_INVALID");
    }
    return snapshot.commitSha;
  } finally {
    // Finalization consumes the lease; release also covers provider/CAS failures.
    const released = await dependencies.caller.rpc("release_website_project_files_read_v1", {
      p_lease_id: authority.leaseId,
    });
    if (released.error) throw new Error("PROJECT_FILES_LEASE_RELEASE_FAILED");
  }
}
