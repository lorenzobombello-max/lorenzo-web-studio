import { createClient } from "npm:@supabase/supabase-js@2";
import { loadGitHubTask13RuntimeConfig } from "../_shared/github-app-config.ts";
import { createGitHubAppTokenBroker } from "../_shared/github-app-token.ts";
import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";
import { createGitHubHttpClient } from "../_shared/github-http.ts";
import {
  createGitHubRepositoryCompletionProofCapability,
  createGitHubRepositoryStateInspectionCapability,
} from "../_shared/github-repository-state-inspector.ts";
import {
  createGitHubLabRepositoryMetadataReader,
  createGitHubRepositoryProviderForRuntime,
  createGitHubRepositoryRuntimeFromProvider,
} from "../_shared/github-repository-runtime.ts";
import { createRepositoryProvisioningStoreV2 } from "../_shared/repository-provisioning-store-v2.ts";
import {
  initializeGitHubAppInputSigner,
  initializeGitHubAppJwtSigner,
} from "../github-app-gate6-probe/runtime.ts";
import { handleGitHubTask13TestIsland } from "./handler.ts";
import { createTask13PostRecoveryFinalizer } from "./post-recovery-finalizer.ts";
import { createTask13PostCreateRecoveryWriteCapability } from "./post-create-recovery-write-capability.ts";
import {
  createTask13PostCreateRecoveryWriter,
  type Task13PostCreateRecoveryInput,
  type Task13PostCreateRecoveryResult,
} from "./post-create-recovery-writer.ts";
import { createTask13PreclaimExecutor } from "./runtime.ts";
import {
  createTask13LabReadonlyReconciler,
  TASK13_SYNTHETIC_AUTHORITY,
} from "./readonly-reconciliation.ts";
import { createExactRepositoryInstallationVisibilityProof } from "./repository-installation-visibility.ts";
import {
  createTask13RecoveryAuthorityInspection,
  createTask13RecoveryPrerequisiteInspection,
} from "./recovery-prerequisite-inspection.ts";

const EXPECTED_SUPABASE_URL = "https://xcsptvntvrizwhskaphr.supabase.co";

function withCors(request: Request, response: Response): Response {
  const headers = new Headers(response.headers);
  for (
    const [key, value] of Object.entries(
      corsHeaders(request.headers.get("origin")),
    )
  ) headers.set(key, value);
  return new Response(response.body, { status: response.status, headers });
}

export function createTask13RecoveryHandler(
  createWriter: (jwt: string) => Promise<
    Readonly<{
      recover(
        input: Task13PostCreateRecoveryInput,
      ): Promise<Task13PostCreateRecoveryResult>;
    }>
  >,
) {
  return async (jwt: string, input: Task13PostCreateRecoveryInput) => {
    const writer = await createWriter(jwt);
    return await writer.recover(input);
  };
}

if (import.meta.main) {
  Deno.serve(async (request) => {
    const originRejection = rejectIfOriginNotAllowed(request);
    if (originRejection) return originRejection;
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(request.headers.get("origin")),
      });
    }
    try {
      const url = Deno.env.get("SUPABASE_URL");
      const publishableKeys = JSON.parse(
        Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "null",
      ) as Record<string, unknown> | null;
      const publishableKey = publishableKeys?.default;
      const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (
        url !== EXPECTED_SUPABASE_URL || typeof publishableKey !== "string" ||
        !/^sb_publishable_[A-Za-z0-9_-]+$/.test(publishableKey) ||
        typeof serviceRoleKey !== "string" || serviceRoleKey.length < 32 ||
        serviceRoleKey === publishableKey
      ) throw new Error("SERVER_CONFIGURATION_ERROR");

      const clientFor = (jwt: string) =>
        createClient(url, publishableKey, {
          global: { headers: { Authorization: `Bearer ${jwt}` } },
          auth: { persistSession: false, autoRefreshToken: false },
        });
      const serviceClient = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const createTokenBroker = ({ signer, http }: Readonly<{
        signer: (signingInput: string) => Promise<Uint8Array>;
        http: ReturnType<typeof createGitHubHttpClient>;
      }>) =>
        createGitHubAppTokenBroker({
          now: Date.now,
          sign: (_privateKey, signingInput) => signer(signingInput),
          exchange: async (exchange) => {
            const result = await http.execute({
              kind: "TOKEN_EXCHANGE",
              installationId: exchange.installationId,
              appJwt: exchange.appJwt,
              repositoryIds: exchange.repositoryIds,
              permissions: exchange.permissions,
            });
            if (!("expiresAt" in result) || !("token" in result)) {
              throw new Error("GITHUB_TOKEN_EXCHANGE_FAILED");
            }
            return {
              token: result.token,
              expiresAt: result.expiresAt,
              ...("repositorySelection" in result
                ? { repositorySelection: result.repositorySelection }
                : {}),
              permissions: result.permissions,
            };
          },
        });
      const execute = createTask13PreclaimExecutor({
        loadConfig: loadGitHubTask13RuntimeConfig,
        loadStarterProvenance: (config) =>
          Object.freeze({
            source:
              `${config.production.templateOwner}/${config.production.templateName}`,
            version: config.production.starterVersion,
            commitSha: config.production.starterCommitSha,
            templateRepositoryId: config.production.templateRepositoryId,
          }),
        initializeSigner: (config) =>
          initializeGitHubAppInputSigner(config.production.privateKey),
        createHttpClient: () => createGitHubHttpClient({ fetch }),
        createProductionTokenBroker: createTokenBroker,
        createLabTokenBroker: createTokenBroker,
        createStore: (jwt) => {
          const rpcClient = clientFor(jwt);
          return createRepositoryProvisioningStoreV2({
            rpc: async (name, arguments_) =>
              await rpcClient.rpc(name, arguments_),
          });
        },
        createProvider: createGitHubRepositoryProviderForRuntime,
        createRuntime: createGitHubRepositoryRuntimeFromProvider,
        validateCommand: (input, starter) =>
          Object.freeze({
            ...input,
            starter,
          }),
      });
      const createReadonlyReconciler = async () => {
        const config = loadGitHubTask13RuntimeConfig();
        const signer = await initializeGitHubAppInputSigner(
          config.production.privateKey,
        );
        const signAppJwt = await initializeGitHubAppJwtSigner(
          config.production.privateKey,
        );
        const http = createGitHubHttpClient({ fetch });
        const tokenBroker = createTokenBroker({ signer, http });
        const proveVisibility =
          createExactRepositoryInstallationVisibilityProof(
            {
              appId: config.lab.appId,
              installationId: TASK13_SYNTHETIC_AUTHORITY.installationId,
              organization: TASK13_SYNTHETIC_AUTHORITY.organization,
              repository: TASK13_SYNTHETIC_AUTHORITY.repository,
            },
            { signAppJwt, http },
          );
        return createTask13LabReadonlyReconciler(config, {
          readRepository: createGitHubLabRepositoryMetadataReader(
            config,
            { tokenBroker, http },
            async ({ config: lab, organization, repository }) => {
              if (
                lab.installationId !==
                  TASK13_SYNTHETIC_AUTHORITY.installationId ||
                organization !== TASK13_SYNTHETIC_AUTHORITY.organization ||
                repository !== TASK13_SYNTHETIC_AUTHORITY.repository
              ) return false;
              return await proveVisibility();
            },
          ),
        });
      };
      const createRecoveryPrerequisiteInspector = async (jwt: string) => {
        const config = loadGitHubTask13RuntimeConfig();
        const signer = await initializeGitHubAppInputSigner(
          config.production.privateKey,
        );
        const http = createGitHubHttpClient({ fetch });
        const tokenBroker = createTokenBroker({ signer, http });
        const rpcClient = clientFor(jwt);
        return createTask13RecoveryPrerequisiteInspection(config, {
          rpc: async (name, parameters) =>
            await rpcClient.rpc(name, parameters),
          inspectRepository: async (authority) => {
            const inspect = createGitHubRepositoryStateInspectionCapability(
              config.lab,
              authority,
              { tokenBroker, http },
            );
            return await inspect();
          },
        });
      };
      const finalizePostRecoveryRepository = async (
        jwt: string,
        input: Readonly<{
          operationId: string;
          websiteWorkContextId: string;
          websiteWorkspaceId: string;
        }>,
        actor: Readonly<{ authUserId: string; aal: "aal2" }>,
      ) => {
        const config = loadGitHubTask13RuntimeConfig();
        const signer = await initializeGitHubAppInputSigner(
          config.production.privateKey,
        );
        const http = createGitHubHttpClient({ fetch });
        const tokenBroker = createTokenBroker({ signer, http });
        const authorityClient = clientFor(jwt);
        const store = createRepositoryProvisioningStoreV2({
          rpc: async (name, arguments_) =>
            await serviceClient.rpc(name, arguments_),
        });
        const finalize = createTask13PostRecoveryFinalizer(
          Object.freeze({
            actorAuthUserId: actor.authUserId,
            actorAal: actor.aal,
            starterSource:
              `${config.production.templateOwner}/${config.production.templateName}`,
            starterVersion: config.lab.starterVersion,
            starterCommitSha: config.lab.starterCommitSha,
            starterTreeSha256: config.lab.starterTreeSha256,
            markerContent: `${
              JSON.stringify(
                {
                  schema_version: 1,
                  environment: "TEST",
                  organization: config.lab.organization,
                  website_work_context_id: input.websiteWorkContextId,
                  repository_provisioning_operation_id: input.operationId,
                  starter_source:
                    `${config.production.templateOwner}/${config.production.templateName}`,
                  starter_version: `v${config.lab.starterVersion}`,
                  starter_commit_sha: config.lab.starterCommitSha,
                  starter_tree_sha256: config.lab.starterTreeSha256,
                },
                null,
                2,
              )
            }\n`,
          }),
          {
            readAuthority: async (authorityInput) => {
              const { data, error } = await authorityClient.rpc(
                "get_task13_repository_recovery_authority_v1",
                {
                  p_operation_id: authorityInput.operationId,
                  p_website_work_context_id:
                    authorityInput.websiteWorkContextId,
                  p_website_workspace_id: authorityInput.websiteWorkspaceId,
                },
              );
              if (error || data === null) {
                throw new Error("TASK13_FINALIZATION_AUTHORITY_FAILED");
              }
              return data;
            },
            inspectCompletion: async (authority) => {
              const inspect = createGitHubRepositoryCompletionProofCapability(
                config.lab,
                authority,
                { tokenBroker, http },
              );
              return await inspect();
            },
            finalize: (operationId, expected, binding, verifiedActor) =>
              store.finalizeRecoveredRepository(
                operationId,
                expected,
                binding,
                verifiedActor,
              ),
          },
        );
        return await finalize(input);
      };
      const createRecoveryWriter = async (jwt: string) => {
        const config = loadGitHubTask13RuntimeConfig();
        const signer = await initializeGitHubAppInputSigner(
          config.production.privateKey,
        );
        const http = createGitHubHttpClient({ fetch });
        const tokenBroker = createTokenBroker({ signer, http });
        const rpcClient = clientFor(jwt);
        const inspect = createTask13RecoveryAuthorityInspection(config, {
          rpc: async (name, parameters) =>
            await rpcClient.rpc(name, parameters),
          inspectRepository: async (authority) => {
            const inspectRepository =
              createGitHubRepositoryStateInspectionCapability(
                config.lab,
                authority,
                { tokenBroker, http },
              );
            return await inspectRepository();
          },
        });
        const writeCapability = createTask13PostCreateRecoveryWriteCapability(
          config,
          {
            tokenBroker,
            http,
          },
        );
        return createTask13PostCreateRecoveryWriter(Object.freeze({
          inspect,
          writeCanonicalSnapshotToEmptyRepository:
            writeCapability.writeCanonicalSnapshotToEmptyRepository,
          writeMissingMarker: writeCapability.writeMissingMarker,
        }));
      };
      const recoverPostCreateExistingRepository = createTask13RecoveryHandler(
        createRecoveryWriter,
      );
      const response = await handleGitHubTask13TestIsland(request, {
        now: Date.now,
        verifyUser: async (jwt) => {
          const { data, error } = await clientFor(jwt).auth.getUser(jwt);
          return error || !data.user ? null : { id: data.user.id };
        },
        authorizeOwner: async (jwt) => {
          const { data, error } = await clientFor(jwt).rpc(
            "get_current_operator_identity_v1",
            {},
          );
          if (
            error || !data || typeof data !== "object" ||
            Array.isArray(data) || data.role !== "owner" ||
            data.status !== "ACTIVE"
          ) throw new Error("OWNER_REQUIRED");
        },
        verifySyntheticAuthority: async (input) => {
          const jwt = (request.headers.get("authorization") || "").replace(
            /^Bearer\s+/i,
            "",
          );
          const { data, error } = await clientFor(jwt).rpc(
            "verify_task13_synthetic_context_authority_v1",
            {
              p_website_work_context_id: input.websiteWorkContextId,
              p_website_workspace_id: input.websiteWorkspaceId,
            },
          );
          return !error && data === true;
        },
        execute: async (input) => {
          const authorization = request.headers.get("authorization") || "";
          const jwt = authorization.replace(/^Bearer\s+/i, "");
          return await execute(input, jwt);
        },
        reconcileReadonly: async () => {
          const reconcile = await createReadonlyReconciler();
          return await reconcile();
        },
        inspectRecoveryPrerequisites: async (input) => {
          const authorization = request.headers.get("authorization") || "";
          const jwt = authorization.replace(/^Bearer\s+/i, "");
          const inspect = await createRecoveryPrerequisiteInspector(jwt);
          return await inspect(input);
        },
        recoverPostCreateExistingRepository: async (input) => {
          const authorization = request.headers.get("authorization") || "";
          const jwt = authorization.replace(/^Bearer\s+/i, "");
          return await recoverPostCreateExistingRepository(jwt, input);
        },
        finalizePostRecoveryRepository: async (input, actor) => {
          const authorization = request.headers.get("authorization") || "";
          const jwt = authorization.replace(/^Bearer\s+/i, "");
          return await finalizePostRecoveryRepository(jwt, input, actor);
        },
      });
      return withCors(request, response);
    } catch {
      return withCors(
        request,
        Response.json(
          { ok: false, code: "SERVER_CONFIGURATION_ERROR" },
          { status: 500, headers: { "Cache-Control": "no-store" } },
        ),
      );
    }
  });
}
