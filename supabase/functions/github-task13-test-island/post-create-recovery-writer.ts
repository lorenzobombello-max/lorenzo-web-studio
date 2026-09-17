import {
  hasValidatedGitHubLabPostCreateDiagnosticError,
} from "../_shared/repository-provisioning-diagnostics.ts";
import type {
  GitHubRepositoryStateClassification,
} from "../_shared/github-repository-state-inspector.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const SHA256 = /^[0-9a-f]{64}$/;
const CLASSIFICATIONS: readonly GitHubRepositoryStateClassification[] = [
  "EMPTY_OR_UNINITIALIZED",
  "ALREADY_COMPLETE",
  "MARKER_MISSING",
  "CONFLICT",
];
const AUTHORITY_KEYS = [
  "operationId",
  "websiteWorkContextId",
  "websiteWorkspaceId",
  "repositoryId",
  "owner",
  "repository",
  "installationId",
  "starterSource",
  "starterVersion",
  "starterCommitSha",
  "starterTreeSha256",
  "markerContent",
] as const;

export type Task13PostCreateRecoveryInput = Readonly<{
  operationId: string;
  websiteWorkContextId: string;
  websiteWorkspaceId: string;
}>;

export type Task13PostCreateRecoveryAuthority = Readonly<{
  operationId: string;
  websiteWorkContextId: string;
  websiteWorkspaceId: string;
  repositoryId: string;
  owner: string;
  repository: string;
  installationId: string;
  starterSource: string;
  starterVersion: string;
  starterCommitSha: string;
  starterTreeSha256: string;
  markerContent: string;
}>;

type Inspection = Readonly<{
  state: GitHubRepositoryStateClassification;
  authority: Task13PostCreateRecoveryAuthority;
}>;

type WriteOutcome = Readonly<{ outcome: "WRITTEN" | "RACE" }>;

export type Task13PostCreateRecoveryDependencies = Readonly<{
  inspect(input: Task13PostCreateRecoveryInput): Promise<Inspection>;
  writeCanonicalSnapshotToEmptyRepository(
    authority: Task13PostCreateRecoveryAuthority,
  ): Promise<WriteOutcome>;
  writeMissingMarker(
    authority: Task13PostCreateRecoveryAuthority,
  ): Promise<WriteOutcome>;
}>;

export type Task13PostCreateRecoveryResult = Readonly<{
  status:
    | "ALREADY_COMPLETE"
    | "RECOVERED_FROM_EMPTY"
    | "RECOVERED_MARKER_ONLY";
}>;

function fail(): never {
  throw new Error("GITHUB_LAB_POST_CREATE_FAILED");
}

function exactDataRecord(
  value: unknown,
  keys: readonly string[],
): value is Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) return false;
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (
    actual.length !== expected.length ||
    !actual.every((key, index) => key === expected[index])
  ) return false;
  const descriptors = Object.getOwnPropertyDescriptors(value);
  return keys.every((key) =>
    descriptors[key]?.enumerable === true &&
    Object.hasOwn(descriptors[key], "value")
  );
}

function validInput(value: unknown): value is Task13PostCreateRecoveryInput {
  return exactDataRecord(value, [
    "operationId",
    "websiteWorkContextId",
    "websiteWorkspaceId",
  ]) && UUID.test(String(value.operationId)) &&
    UUID.test(String(value.websiteWorkContextId)) &&
    UUID.test(String(value.websiteWorkspaceId));
}

function expectedRepository(websiteWorkContextId: string): string {
  return `lws-web-${websiteWorkContextId.toLowerCase().replaceAll("-", "")}`;
}

function projectAuthority(
  value: unknown,
  input: Task13PostCreateRecoveryInput,
): Task13PostCreateRecoveryAuthority {
  if (
    !exactDataRecord(value, AUTHORITY_KEYS) ||
    value.operationId !== input.operationId ||
    value.websiteWorkContextId !== input.websiteWorkContextId ||
    value.websiteWorkspaceId !== input.websiteWorkspaceId ||
    typeof value.repositoryId !== "string" ||
    !NUMERIC_ID.test(value.repositoryId) ||
    value.owner !== "lorenzo-web-solutions-lab" ||
    value.repository !== expectedRepository(input.websiteWorkContextId) ||
    value.installationId !== "161461160" ||
    value.starterSource !== "lorenzo-web-solutions/lws-website-starter" ||
    value.starterVersion !== "1.0.0" ||
    typeof value.starterCommitSha !== "string" ||
    !SHA.test(value.starterCommitSha) ||
    typeof value.starterTreeSha256 !== "string" ||
    !SHA256.test(value.starterTreeSha256) ||
    typeof value.markerContent !== "string" ||
    value.markerContent.length === 0 || value.markerContent.length > 64 * 1024
  ) fail();
  return Object.freeze({
    operationId: value.operationId,
    websiteWorkContextId: value.websiteWorkContextId,
    websiteWorkspaceId: value.websiteWorkspaceId,
    repositoryId: value.repositoryId,
    owner: value.owner,
    repository: value.repository,
    installationId: value.installationId,
    starterSource: value.starterSource,
    starterVersion: value.starterVersion,
    starterCommitSha: value.starterCommitSha,
    starterTreeSha256: value.starterTreeSha256,
    markerContent: value.markerContent,
  } as Task13PostCreateRecoveryAuthority);
}

function sameAuthority(
  left: Task13PostCreateRecoveryAuthority,
  right: Task13PostCreateRecoveryAuthority,
): boolean {
  return AUTHORITY_KEYS.every((key) => left[key] === right[key]);
}

function projectInspection(
  value: unknown,
  input: Task13PostCreateRecoveryInput,
  previous?: Task13PostCreateRecoveryAuthority,
): Inspection {
  if (
    !exactDataRecord(value, ["state", "authority"]) ||
    !CLASSIFICATIONS.includes(
      value.state as GitHubRepositoryStateClassification,
    )
  ) fail();
  const authority = projectAuthority(value.authority, input);
  if (previous && !sameAuthority(previous, authority)) fail();
  return Object.freeze({
    state: value.state as GitHubRepositoryStateClassification,
    authority,
  });
}

function projectWriteOutcome(value: unknown): WriteOutcome {
  if (
    !exactDataRecord(value, ["outcome"]) ||
    value.outcome !== "WRITTEN" && value.outcome !== "RACE"
  ) fail();
  return Object.freeze({ outcome: value.outcome });
}

async function closed<T>(action: () => Promise<T>): Promise<T> {
  try {
    return await action();
  } catch (error) {
    if (hasValidatedGitHubLabPostCreateDiagnosticError(error)) throw error;
    return fail();
  }
}

export function createTask13PostCreateRecoveryWriter(
  dependencies: Task13PostCreateRecoveryDependencies,
): Readonly<{
  recover(
    input: Task13PostCreateRecoveryInput,
  ): Promise<Task13PostCreateRecoveryResult>;
}> {
  if (
    !exactDataRecord(dependencies, [
      "inspect",
      "writeCanonicalSnapshotToEmptyRepository",
      "writeMissingMarker",
    ]) || typeof dependencies.inspect !== "function" ||
    typeof dependencies.writeCanonicalSnapshotToEmptyRepository !==
      "function" ||
    typeof dependencies.writeMissingMarker !== "function"
  ) fail();

  const inspect = async (
    safeInput: Task13PostCreateRecoveryInput,
    previous?: Task13PostCreateRecoveryAuthority,
  ) =>
    projectInspection(
      await closed(() => dependencies.inspect(safeInput)),
      safeInput,
      previous,
    );

  const completeMarker = async (
    safeInput: Task13PostCreateRecoveryInput,
    authority: Task13PostCreateRecoveryAuthority,
  ) => {
    projectWriteOutcome(
      await closed(() => dependencies.writeMissingMarker(authority)),
    );
    const final = await inspect(safeInput, authority);
    if (final.state !== "ALREADY_COMPLETE") fail();
  };

  return Object.freeze({
    async recover(input) {
      if (!validInput(input)) fail();
      const safeInput = Object.freeze({
        operationId: input.operationId,
        websiteWorkContextId: input.websiteWorkContextId,
        websiteWorkspaceId: input.websiteWorkspaceId,
      });
      const initial = await inspect(safeInput);
      if (initial.state === "ALREADY_COMPLETE") {
        return Object.freeze({ status: "ALREADY_COMPLETE" as const });
      }
      if (initial.state === "CONFLICT") fail();
      if (initial.state === "MARKER_MISSING") {
        await completeMarker(safeInput, initial.authority);
        return Object.freeze({ status: "RECOVERED_MARKER_ONLY" as const });
      }

      const write = projectWriteOutcome(
        await closed(() =>
          dependencies.writeCanonicalSnapshotToEmptyRepository(
            initial.authority,
          )
        ),
      );
      const readback = await inspect(safeInput, initial.authority);
      if (readback.state === "ALREADY_COMPLETE") {
        return Object.freeze({ status: "RECOVERED_FROM_EMPTY" as const });
      }
      if (write.outcome === "RACE" && readback.state === "MARKER_MISSING") {
        await completeMarker(safeInput, readback.authority);
        return Object.freeze({ status: "RECOVERED_FROM_EMPTY" as const });
      }
      return fail();
    },
  });
}
