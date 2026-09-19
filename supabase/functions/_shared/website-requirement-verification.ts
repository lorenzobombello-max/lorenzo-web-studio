import {
  classifyWebsiteProjectPath,
  inspectWebsiteProjectFile,
  normalizeWebsiteProjectPath,
  WebsiteProjectFilesPolicyError,
} from "./website-project-files-policy.ts";
import type {
  WebsiteProjectFilesAuthority,
  WebsiteProjectFilesProvider,
  WebsiteProjectFilesProviderFile,
} from "./website-project-files-provider.ts";
import { WebsiteProjectFilesProviderError } from "./website-project-files-provider.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA1 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const SUITE_ID = /^[a-z][a-z0-9_-]{0,79}$/;
const ZERO_SHA1 = "0".repeat(40);
const FIVE_MINUTES_MS = 5 * 60 * 1000;
const TWENTY_FOUR_HOURS_MS = 24 * 60 * 60 * 1000;

export type WebsiteRequirementVerificationResult = "PASS" | "FAIL" | "UNKNOWN";
export type WebsiteRequirementCompletionMode = "AUTO" | "HYBRID";
export type WebsiteRequirementEvidenceType =
  | "REPOSITORY_ROUTE"
  | "REPOSITORY_FILE"
  | "TEST_RUN"
  | "CONTENT_MARKER";

export type WebsiteRequirementVerificationAuthority = Readonly<{
  contract_version: 1;
  quote_request_id: string;
  website_work_context_id: string;
  requirements_board_id: string;
  requirement_id: string;
  requirement_revision: number;
  completion_mode: WebsiteRequirementCompletionMode | "OPERATOR" | "EXTERNAL";
  rule_key: string;
  rule_version: number;
  source_value_sha256: string;
  source_review_state: string;
  verification_target: Readonly<{
    kind: "DIRECTORY_PATH" | "FILE_PATH" | "SUITE_ID";
    value: string;
  }>;
  workspace: Readonly<{
    website_workspace_id: string;
    binding_revision: number;
    repository_provider: "GITHUB";
    repository_owner: string;
    repository_name: string;
    repository_external_id: string;
    repository_node_id: string;
    repository_ref: string;
    ref_label: string;
    last_commit_sha: string;
    workspace_state: string;
    repository_operation_state: string;
  }>;
}>;

export type TrustedWebsiteTestRunSource = Readonly<{
  read(input: Readonly<{
    websiteWorkContextId: string;
    websiteWorkspaceId: string;
    bindingRevision: number;
    repositoryRef: string;
    commitSha: string;
    suiteId: string;
    suiteVersion: 1;
  }>): Promise<Readonly<{
    suiteId: string;
    suiteVersion: 1;
    runId: string;
    result: WebsiteRequirementVerificationResult;
    observedAt: string;
  }>>;
}>;

export type WebsiteRequirementEvidenceReference = Readonly<{
  contract_version: 1;
  evidence_type: WebsiteRequirementEvidenceType;
  website_work_context_id: string;
  website_workspace_id: string;
  binding_revision: number;
  repository_ref: string;
  commit_sha: string;
  requirement_source_sha256: string;
  observed_at: string;
  details: Readonly<Record<string, string | number>>;
}>;

export type WebsiteRequirementEvaluation = Readonly<{
  result: WebsiteRequirementVerificationResult;
  evidenceReference: WebsiteRequirementEvidenceReference;
  evidenceSha256: string;
  expiresAt: string | null;
}>;

type Rule = Readonly<{
  evidenceType: WebsiteRequirementEvidenceType;
  modes: readonly WebsiteRequirementCompletionMode[];
  targetKind: "DIRECTORY_PATH" | "FILE_PATH" | "SUITE_ID";
}>;

const RULES: Readonly<Record<string, Rule>> = Object.freeze({
  "website_route_present:1": Object.freeze({
    evidenceType: "REPOSITORY_ROUTE",
    modes: Object.freeze(["HYBRID"] as const),
    targetKind: "DIRECTORY_PATH",
  }),
  "website_module_present:1": Object.freeze({
    evidenceType: "REPOSITORY_FILE",
    modes: Object.freeze(["HYBRID"] as const),
    targetKind: "FILE_PATH",
  }),
  "website_test_suite_passed:1": Object.freeze({
    evidenceType: "TEST_RUN",
    modes: Object.freeze(["AUTO", "HYBRID"] as const),
    targetKind: "SUITE_ID",
  }),
  "approved_content_present:1": Object.freeze({
    evidenceType: "CONTENT_MARKER",
    modes: Object.freeze(["HYBRID"] as const),
    targetKind: "FILE_PATH",
  }),
});

export class WebsiteRequirementVerificationError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "WebsiteRequirementVerificationError";
  }
}

function fail(code: string): never {
  throw new WebsiteRequirementVerificationError(code);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  return actual.length === sortedExpected.length &&
    actual.every((key, index) => key === sortedExpected[index]);
}

function canonicalize(value: unknown): unknown {
  if (typeof value === "string") return value.normalize("NFKC");
  if (Array.isArray(value)) return value.map(canonicalize);
  if (isRecord(value)) {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]),
    );
  }
  return value;
}

async function digestHex(algorithm: "SHA-1" | "SHA-256", bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(algorithm, Uint8Array.from(bytes).buffer);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function canonicalEvidenceSha256(value: unknown): Promise<string> {
  return await digestHex(
    "SHA-256",
    new TextEncoder().encode(JSON.stringify(canonicalize(value))),
  );
}

async function textSha256(value: string): Promise<string> {
  return await digestHex("SHA-256", new TextEncoder().encode(value.normalize("NFKC")));
}

async function gitBlobSha(bytes: Uint8Array): Promise<string> {
  const header = new TextEncoder().encode(`blob ${bytes.byteLength}\0`);
  const input = new Uint8Array(header.byteLength + bytes.byteLength);
  input.set(header);
  input.set(bytes, header.byteLength);
  return await digestHex("SHA-1", input);
}

function validateAuthority(
  authority: WebsiteRequirementVerificationAuthority,
  projectFilesAuthority: WebsiteProjectFilesAuthority,
): Rule {
  if (!isRecord(authority) || !exactKeys(authority, [
    "contract_version",
    "quote_request_id",
    "website_work_context_id",
    "requirements_board_id",
    "requirement_id",
    "requirement_revision",
    "completion_mode",
    "rule_key",
    "rule_version",
    "source_value_sha256",
    "source_review_state",
    "verification_target",
    "workspace",
  ])) return fail("INVALID_WEBSITE_REQUIREMENT_VERIFICATION_AUTHORITY");
  if (
    authority.contract_version !== 1 ||
    !UUID.test(authority.quote_request_id) ||
    !UUID.test(authority.website_work_context_id) ||
    !UUID.test(authority.requirements_board_id) ||
    !UUID.test(authority.requirement_id) ||
    !Number.isSafeInteger(authority.requirement_revision) || authority.requirement_revision < 1 ||
    !SHA256.test(authority.source_value_sha256) ||
    authority.source_review_state !== "CURRENT" ||
    !isRecord(authority.verification_target) ||
    !exactKeys(authority.verification_target, ["kind", "value"]) ||
    !isRecord(authority.workspace) ||
    !exactKeys(authority.workspace, [
      "website_workspace_id",
      "binding_revision",
      "repository_provider",
      "repository_owner",
      "repository_name",
      "repository_external_id",
      "repository_node_id",
      "repository_ref",
      "ref_label",
      "last_commit_sha",
      "workspace_state",
      "repository_operation_state",
    ]) ||
    authority.workspace.workspace_state !== "REPOSITORY_READY" ||
    authority.workspace.repository_operation_state !== "COMPLETE" ||
    authority.workspace.repository_provider !== "GITHUB" ||
    !UUID.test(authority.workspace.website_workspace_id) ||
    !Number.isSafeInteger(authority.workspace.binding_revision) ||
    authority.workspace.binding_revision < 1 ||
    !SHA1.test(authority.workspace.last_commit_sha)
  ) return fail("INVALID_WEBSITE_REQUIREMENT_VERIFICATION_AUTHORITY");

  const rule = RULES[`${authority.rule_key}:${authority.rule_version}`];
  if (!rule) return fail("UNKNOWN_WEBSITE_REQUIREMENT_RULE");
  if (!rule.modes.includes(authority.completion_mode as WebsiteRequirementCompletionMode)) {
    return fail("WEBSITE_REQUIREMENT_VERIFICATION_MODE_UNSUPPORTED");
  }
  if (authority.verification_target.kind !== rule.targetKind) {
    return fail("WEBSITE_REQUIREMENT_RULE_MISMATCH");
  }
  if (
    projectFilesAuthority.quoteRequestId !== authority.quote_request_id ||
    projectFilesAuthority.websiteWorkContextId !== authority.website_work_context_id ||
    projectFilesAuthority.websiteWorkspaceId !== authority.workspace.website_workspace_id ||
    projectFilesAuthority.bindingRevision !== authority.workspace.binding_revision ||
    projectFilesAuthority.repositoryProvider !== authority.workspace.repository_provider ||
    projectFilesAuthority.repositoryOwner !== authority.workspace.repository_owner ||
    projectFilesAuthority.repositoryName !== authority.workspace.repository_name ||
    projectFilesAuthority.repositoryExternalId !== authority.workspace.repository_external_id ||
    projectFilesAuthority.repositoryNodeId !== authority.workspace.repository_node_id ||
    projectFilesAuthority.repositoryRef !== authority.workspace.repository_ref ||
    projectFilesAuthority.refLabel !== authority.workspace.ref_label
  ) return fail("WEBSITE_REQUIREMENT_WORKSPACE_MISMATCH");
  return rule;
}

function observedAt(value: string, now: Date, allowAgeMs: number): Date {
  const date = new Date(value);
  if (
    !Number.isFinite(date.getTime()) ||
    date.getTime() > now.getTime() + FIVE_MINUTES_MS ||
    date.getTime() < now.getTime() - allowAgeMs
  ) return fail("WEBSITE_REQUIREMENT_VERIFICATION_STALE");
  return date;
}

function providerFailureResult(error: unknown): WebsiteRequirementVerificationResult | never {
  const code = error instanceof WebsiteProjectFilesProviderError ||
      error instanceof WebsiteProjectFilesPolicyError
    ? error.code
    : "";
  if (code === "PROJECT_FILE_NOT_FOUND" || code === "PROJECT_PATH_KIND_MISMATCH") return "FAIL";
  if (
    code.includes("TIMEOUT") || code.includes("THROTTLE") ||
    code.includes("UNAVAILABLE") || code.includes("SENSITIVE") ||
    code === "FILE_TOO_LARGE" || code === "BINARY_UNSUPPORTED" ||
    code === "UNSUPPORTED_ENCODING"
  ) return "UNKNOWN";
  throw error;
}

function inspectReadableFile(file: WebsiteProjectFilesProviderFile): string {
  return inspectWebsiteProjectFile({
    path: file.path,
    canonicalPath: file.canonicalPath,
    mode: file.mode,
    objectType: file.objectType,
    declaredSize: file.declaredSize,
    bytes: file.bytes,
    mediaType: "text/plain",
  }).content;
}

async function finish(
  result: WebsiteRequirementVerificationResult,
  evidenceReference: WebsiteRequirementEvidenceReference,
  expiresAt: string | null,
): Promise<WebsiteRequirementEvaluation> {
  return Object.freeze({
    result,
    evidenceReference: Object.freeze(evidenceReference),
    evidenceSha256: await canonicalEvidenceSha256(evidenceReference),
    expiresAt,
  });
}

export async function evaluateWebsiteRequirement(
  input: Readonly<{
    authority: WebsiteRequirementVerificationAuthority;
    projectFilesAuthority: WebsiteProjectFilesAuthority;
  }>,
  dependencies: Readonly<{
    provider: WebsiteProjectFilesProvider;
    testRunSource?: TrustedWebsiteTestRunSource;
    now?: () => Date;
  }>,
): Promise<WebsiteRequirementEvaluation> {
  if (!isRecord(input) || !exactKeys(input, ["authority", "projectFilesAuthority"])) {
    return fail("INVALID_WEBSITE_REQUIREMENT_VERIFICATION_AUTHORITY");
  }
  const now = dependencies.now?.() ?? new Date();
  const rule = validateAuthority(input.authority, input.projectFilesAuthority);
  const leaseExpiresAt = Date.parse(input.projectFilesAuthority.expiresAt);
  if (!Number.isFinite(leaseExpiresAt) || leaseExpiresAt <= now.getTime()) {
    return fail("WEBSITE_REQUIREMENT_VERIFICATION_STALE");
  }
  const snapshot = await dependencies.provider.resolveSnapshot(input.projectFilesAuthority);
  if (snapshot.commitSha !== input.authority.workspace.last_commit_sha) {
    return fail("WEBSITE_REQUIREMENT_COMMIT_MISMATCH");
  }

  const common = {
    contract_version: 1 as const,
    evidence_type: rule.evidenceType,
    website_work_context_id: input.authority.website_work_context_id,
    website_workspace_id: input.authority.workspace.website_workspace_id,
    binding_revision: input.authority.workspace.binding_revision,
    repository_ref: input.authority.workspace.repository_ref,
    commit_sha: snapshot.commitSha,
    requirement_source_sha256: input.authority.source_value_sha256,
  };

  if (rule.evidenceType === "TEST_RUN") {
    if (!SUITE_ID.test(input.authority.verification_target.value) || !dependencies.testRunSource) {
      return fail("INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE");
    }
    const run = await dependencies.testRunSource.read({
      websiteWorkContextId: input.authority.website_work_context_id,
      websiteWorkspaceId: input.authority.workspace.website_workspace_id,
      bindingRevision: input.authority.workspace.binding_revision,
      repositoryRef: input.authority.workspace.repository_ref,
      commitSha: snapshot.commitSha,
      suiteId: input.authority.verification_target.value,
      suiteVersion: 1,
    });
    if (
      !isRecord(run) || !exactKeys(run, ["suiteId", "suiteVersion", "runId", "result", "observedAt"]) ||
      run.suiteId !== input.authority.verification_target.value || run.suiteVersion !== 1 ||
      typeof run.runId !== "string" || run.runId.length < 1 || run.runId.length > 120 ||
      !["PASS", "FAIL", "UNKNOWN"].includes(run.result)
    ) return fail("INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE");
    const observed = observedAt(run.observedAt, now, TWENTY_FOUR_HOURS_MS);
    const evidenceReference = {
      ...common,
      observed_at: observed.toISOString(),
      details: Object.freeze({ suite_id: run.suiteId, suite_version: 1, run_id: run.runId }),
    };
    return await finish(
      run.result,
      evidenceReference,
      new Date(observed.getTime() + TWENTY_FOUR_HOURS_MS).toISOString(),
    );
  }

  const path = normalizeWebsiteProjectPath(input.authority.verification_target.value, { allowRoot: false });
  const blockedPath = classifyWebsiteProjectPath(path) === "BLOCKED_CREDENTIAL";
  const observed = now.toISOString();
  if (rule.evidenceType === "REPOSITORY_ROUTE") {
    let result: WebsiteRequirementVerificationResult = blockedPath ? "UNKNOWN" : "PASS";
    let objectSha = ZERO_SHA1;
    if (!blockedPath) {
      try {
        const directory = await dependencies.provider.listDirectory({
          authority: input.projectFilesAuthority,
          commitSha: snapshot.commitSha,
          rootTreeSha: snapshot.rootTreeSha,
          directoryTreeSha: null,
          path,
        });
        if (!SHA1.test(directory.directoryTreeSha)) {
          return fail("INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE");
        }
        objectSha = directory.directoryTreeSha;
      } catch (error) {
        result = error instanceof WebsiteProjectFilesProviderError &&
            error.code === "PROJECT_FILES_SNAPSHOT_UNAVAILABLE"
          ? "FAIL"
          : providerFailureResult(error);
      }
    }
    return await finish(result, {
      ...common,
      observed_at: observed,
      details: Object.freeze({ path, object_type: "tree", object_sha: objectSha }),
    }, null);
  }

  let result: WebsiteRequirementVerificationResult = blockedPath ? "UNKNOWN" : "PASS";
  let file: WebsiteProjectFilesProviderFile | null = null;
  let text = "";
  if (!blockedPath) {
    try {
      file = await dependencies.provider.readFile({
        authority: input.projectFilesAuthority,
        commitSha: snapshot.commitSha,
        rootTreeSha: snapshot.rootTreeSha,
        path,
      });
      text = inspectReadableFile(file);
    } catch (error) {
      result = providerFailureResult(error);
    }
  }

  if (rule.evidenceType === "REPOSITORY_FILE") {
    const objectSha = file ? await gitBlobSha(file.bytes) : ZERO_SHA1;
    return await finish(result, {
      ...common,
      observed_at: observed,
      details: Object.freeze({ path, object_type: "blob", object_sha: objectSha }),
    }, null);
  }

  const markerLine = `LWS_APPROVED_CONTENT_V1:${input.authority.source_value_sha256}`;
  if (result === "PASS" && !text.split(/\r?\n/u).some((line) => line.trim() === markerLine)) {
    result = "FAIL";
  }
  return await finish(result, {
    ...common,
    observed_at: observed,
    details: Object.freeze({
      path,
      marker_key: "LWS_APPROVED_CONTENT",
      marker_version: 1,
      marker_sha256: await textSha256(markerLine),
    }),
  }, null);
}