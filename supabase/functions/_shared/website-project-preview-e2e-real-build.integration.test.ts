import { assert, assertEquals, assertMatch, assertRejects } from "jsr:@std/assert@1";
import { fromFileUrl } from "jsr:@std/path@1";
import type { WebsiteProjectPreviewAsyncRpcClient } from "./website-project-preview-async-build.ts";
import { buildWebsiteProjectPreviewArtifactManifest } from "./website-project-preview-artifact-manifest.ts";
import { createWebsiteProjectPreviewArtifactRuntime } from "../website-project-preview-artifact/index.ts";
import { handleWebsiteProjectPreviewArtifact } from "../website-project-preview-artifact/handler.ts";
import { runWebsiteProjectPreviewUpload } from "../../../scripts/website-project-preview-upload.ts";

const ACTOR_AUTH_USER_ID = "c9bcd3ef-1e7e-4889-8a12-db827f1b97b0";
const CUSTOMER_REPOSITORY = "lorenzo-web-solutions/lws-web-a88b1e8792714ad199ccb385b7982a8b";
const CUSTOMER_REPOSITORY_URL = `https://github.com/${CUSTOMER_REPOSITORY}`;
const COMMIT_SHA = "1f19bf01c61c6da79fa4c7374333a91b70f9bf48";
const DB_CONTAINER = "supabase_db_xcsptvntvrizwhskaphr";
const STORAGE_BUCKET = "website-project-previews";
const WORKFLOW_REPOSITORY = "lorenzobombello-max/lorenzo-web-studio";
const WORKFLOW_REPOSITORY_ID = "9001";
const WORKFLOW_REF_NAME = "refs/heads/main";
const WORKFLOW_REF = `${WORKFLOW_REPOSITORY}/.github/workflows/build-website-project-preview.yml@${WORKFLOW_REF_NAME}`;
const WORKFLOW_RUN_ID = "998877";
const OIDC_AUDIENCE = "lws-preview-artifact-receipt-local-test";
const PROXY_ROOT = fromFileUrl(new URL("../../../scripts/preview-build-proxy/", import.meta.url));

type CommandResult = Readonly<{ success: boolean; stdout: string; stderr: string }>;

async function command(program: string, args: string[]): Promise<CommandResult> {
  const result = await new Deno.Command(program, { args }).output();
  return {
    success: result.success,
    stdout: new TextDecoder().decode(result.stdout).trim(),
    stderr: new TextDecoder().decode(result.stderr).trim(),
  };
}

async function dockerAvailable(): Promise<boolean> {
  try {
    return (await command("docker", ["info"])).success;
  } catch {
    return false;
  }
}

async function checkoutExactCustomerSource(sourceRoot: string): Promise<void> {
  const clone = await command("git", ["clone", "--quiet", "--no-checkout", CUSTOMER_REPOSITORY_URL, sourceRoot]);
  if (!clone.success) throw new Error(`CUSTOMER_SOURCE_CLONE_FAILED:${clone.stderr}`);
  const checkout = await command("git", ["-C", sourceRoot, "checkout", "--quiet", "--detach", COMMIT_SHA]);
  if (!checkout.success) throw new Error(`CUSTOMER_SOURCE_CHECKOUT_FAILED:${checkout.stderr}`);
  const head = await command("git", ["-C", sourceRoot, "rev-parse", "HEAD"]);
  assertEquals(head.stdout, COMMIT_SHA);
  const remote = await command("git", ["-C", sourceRoot, "remote", "get-url", "origin"]);
  assertEquals(remote.stdout.replace(/[.]git$/, ""), CUSTOMER_REPOSITORY_URL);
  await Deno.remove(`${sourceRoot}/.git`, { recursive: true });
}

function sqlLiteral(value: string): string {
  return `'${value.replaceAll("'", "''")}'`;
}

async function psql(sql: string): Promise<string> {
  const result = await command("docker", [
    "exec", "-i", DB_CONTAINER, "psql", "-U", "postgres", "-d", "postgres",
    "-v", "ON_ERROR_STOP=1", "-qAt", "-c", sql,
  ]);
  if (!result.success) throw new Error(result.stderr || result.stdout);
  return result.stdout.split(/\r?\n/).filter(Boolean).at(-1) ?? "";
}

function callerClaims(role = "authenticated"): string {
  return JSON.stringify({ sub: ACTOR_AUTH_USER_ID, role, aal: "aal2" });
}

function createRealRpcClient(): WebsiteProjectPreviewAsyncRpcClient {
  return {
    async rpc<T>(name: string, args: Record<string, unknown>) {
      let invocation: string;
      if (name === "acquire_website_project_preview_build_v1") {
        invocation = `public.${name}(${sqlLiteral(String(args.p_quote_request_id))}::uuid,${sqlLiteral(String(args.p_expected_commit_sha))},${sqlLiteral(String(args.p_idempotency_key))}::uuid)`;
      } else if (name === "finalize_website_project_preview_build_v2") {
        invocation = `public.${name}(${sqlLiteral(String(args.p_lease_id))}::uuid,${sqlLiteral(String(args.p_expected_commit_sha))},${sqlLiteral(String(args.p_build_status))},${args.p_primary_relative_path === null ? "null" : sqlLiteral(String(args.p_primary_relative_path))},${args.p_manifest === null ? "null" : `${sqlLiteral(JSON.stringify(args.p_manifest))}::jsonb`})`;
      } else if (name === "get_website_project_preview_build_status_v1") {
        invocation = `public.${name}(${sqlLiteral(String(args.p_lease_id))}::uuid)`;
      } else if (name === "create_website_project_preview_session_v1") {
        invocation = `public.${name}(${sqlLiteral(String(args.p_preview_build_id))}::uuid,${sqlLiteral(String(args.p_session_token_hash))})`;
      } else {
        return { data: null, error: { message: `UNKNOWN_RPC:${name}` } };
      }
      try {
        const output = await psql(`set role authenticated; select set_config('request.jwt.claims',${sqlLiteral(callerClaims())},false); select ${invocation}::text;`);
        return { data: JSON.parse(output) as T, error: null };
      } catch (error) {
        return { data: null, error: { message: error instanceof Error ? error.message : String(error) } };
      }
    },
  };
}

async function sha256HexBytes(value: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", Uint8Array.from(value).buffer);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function localSupabaseEnvironment(): Promise<Readonly<{
  apiUrl: string;
  secretKey: string;
  serviceRoleKey: string;
}>> {
  const status = await command("npx", ["supabase", "status", "-o", "env"]);
  if (!status.success) throw new Error(status.stderr || status.stdout);
  const apiUrl = /API_URL="([^"]+)"/.exec(status.stdout)?.[1];
  const secretKey = /SECRET_KEY="([^"]+)"/.exec(status.stdout)?.[1];
  const serviceRoleKey = /SERVICE_ROLE_KEY="([^"]+)"/.exec(status.stdout)?.[1];
  if (!apiUrl || !secretKey || !serviceRoleKey) throw new Error("LOCAL_SUPABASE_ENV_UNAVAILABLE");
  return { apiUrl, secretKey, serviceRoleKey };
}

function storageHeaders(serviceRoleKey: string, contentType?: string): HeadersInit {
  return {
    apikey: serviceRoleKey,
    authorization: `Bearer ${serviceRoleKey}`,
    ...(contentType ? { "content-type": contentType.split(";", 1)[0], "x-upsert": "false" } : {}),
  };
}

function storageObjectUrl(apiUrl: string, prefix: string, relativePath: string): string {
  return `${apiUrl}/storage/v1/object/${STORAGE_BUCKET}/${prefix}/${relativePath}`;
}

async function seedPreviewAuthority(): Promise<Readonly<{ quoteRequestId: string; repositoryExternalId: string }>> {
  const repositorySuffix = crypto.randomUUID().slice(0, 8);
  const repositoryName = `lws-web-a88b1e8792714ad199ccb385b7982a8b-e2e-${repositorySuffix}`;
  const repositoryNodeId = `R_local_${repositorySuffix}`;
  const repositoryExternalId = 7_300_000_000 + Number.parseInt(repositorySuffix, 16);
  const sql = `
    begin;
    select set_config('request.jwt.claims',${sqlLiteral(callerClaims())},true);
    set local session_replication_role=replica;
    update public.commercial_operators set role='owner',status='ACTIVE',revoked_at=null where auth_user_id=${sqlLiteral(ACTOR_AUTH_USER_ID)}::uuid;
    set local session_replication_role=origin;
    create temporary table preview_e2e_fixture as
      select (value->>'website_work_context_id')::uuid website_work_context_id,
             (value->>'workspace_id')::uuid website_workspace_id,
             null::uuid quote_request_id
      from (select public.create_task13_synthetic_context_v1() value) created;
    update preview_e2e_fixture fixture set quote_request_id=context.quote_request_id
      from public.website_work_contexts context where context.website_work_context_id=fixture.website_work_context_id;
    set local session_replication_role=replica;
    update public.website_execution_workspaces workspace set
      workspace_state='REPOSITORY_READY',repository_owner='lorenzo-web-solutions',repository_name=${sqlLiteral(repositoryName)},
      repository_external_id=${repositoryExternalId},repository_node_id=${sqlLiteral(repositoryNodeId)},repository_visibility='private',
      repository_state='BOUND',starter_source='lws-local-fixtures/website-starter',starter_version='1.0.0',
      starter_commit_sha=${sqlLiteral(COMMIT_SHA)},repository_marker_commit_sha=repeat('d',40),repository_bound_at=clock_timestamp(),
      binding_revision=1,default_branch='main',last_commit_sha=${sqlLiteral(COMMIT_SHA)}
    from preview_e2e_fixture fixture where workspace.website_workspace_id=fixture.website_workspace_id;
    set local session_replication_role=origin;
    select set_config('lws.website_repository_command','on',true);
    insert into public.website_repository_provisioning_operations(
      operation_id,website_workspace_id,website_work_context_id,actor_id,idempotency_key,request_fingerprint,
      repository_owner,repository_name,starter_source,starter_version,starter_commit_sha,state,attempt_count,
      repository_external_id,repository_node_id,claimed_at,updated_at,external_created_at,bound_at)
    select gen_random_uuid(),fixture.website_workspace_id,fixture.website_work_context_id,operator.operator_id,
      gen_random_uuid(),repeat('1',64),'lorenzo-web-solutions',${sqlLiteral(repositoryName)},'lorenzo-web-solutions/website-starter',
      '1.0.0',${sqlLiteral(COMMIT_SHA)},'BOUND',1,${repositoryExternalId},${sqlLiteral(repositoryNodeId)},clock_timestamp(),
      clock_timestamp(),clock_timestamp(),clock_timestamp()
    from preview_e2e_fixture fixture join public.commercial_operators operator on operator.auth_user_id=${sqlLiteral(ACTOR_AUTH_USER_ID)}::uuid;
    select jsonb_build_object(
      'quoteRequestId', quote_request_id,
      'repositoryExternalId', ${repositoryExternalId}::bigint
    )::text from preview_e2e_fixture;
    commit;`;
  return JSON.parse(await psql(sql));
}

async function releasePreviewLease(leaseId: string): Promise<void> {
  await psql(`set role authenticated; select set_config('request.jwt.claims',${sqlLiteral(callerClaims())},false); select public.release_website_project_preview_build_v1(${sqlLiteral(leaseId)}::uuid);`);
}

function base64Url(value: Uint8Array | string): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

async function createLocalOidcProvider() {
  const keys = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const publicJwk = await crypto.subtle.exportKey("jwk", keys.publicKey);
  async function token(overrides: Record<string, unknown> = {}): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    const claims = {
      iss: "https://token.actions.githubusercontent.com",
      aud: OIDC_AUDIENCE,
      sub: `repo:${WORKFLOW_REPOSITORY}:ref:${WORKFLOW_REF_NAME}`,
      repository: WORKFLOW_REPOSITORY,
      repository_id: WORKFLOW_REPOSITORY_ID,
      sha: "c".repeat(40),
      ref: WORKFLOW_REF_NAME,
      run_id: WORKFLOW_RUN_ID,
      workflow_ref: WORKFLOW_REF,
      iat: now - 5,
      nbf: now - 5,
      exp: now + 60,
      ...overrides,
    };
    const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT", kid: "local-test-key" }));
    const payload = base64Url(JSON.stringify(claims));
    const signingInput = `${header}.${payload}`;
    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      keys.privateKey,
      new TextEncoder().encode(signingInput),
    );
    return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
  }
  let baseUrl = "";
  const server = Deno.serve({ hostname: "127.0.0.1", port: 0, onListen: () => {} }, async (request) => {
    const url = new URL(request.url);
    if (url.pathname === "/jwks") {
      return Response.json({ keys: [{ ...publicJwk, kid: "local-test-key", alg: "RS256", use: "sig" }] });
    }
    if (url.pathname === "/token"
      && request.headers.get("authorization") === "Bearer local-oidc-request-token"
      && url.searchParams.get("audience") === OIDC_AUDIENCE) {
      return Response.json({ value: await token() });
    }
    return new Response("OIDC_TEST_PROVIDER_REJECTED", { status: 403 });
  });
  baseUrl = `http://127.0.0.1:${(server.addr as Deno.NetAddr).port}`;
  return { baseUrl, server, token };
}

async function jsonRequest(
  endpoint: string,
  token: string,
  body: Record<string, unknown>,
): Promise<Readonly<{ status: number; body: Record<string, unknown> }>> {
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

async function uploadRequest(
  endpoint: string,
  sessionToken: string,
  binding: Readonly<{
    leaseId: string;
    buildId: string;
    repositoryId: string;
    commitSha: string;
    workflowRunId: string;
  }>,
  entry: Readonly<{ path: string; contentType: string; sha256: string; bytes: number }>,
  bytes: Uint8Array,
): Promise<Readonly<{ status: number; body: Record<string, unknown> }>> {
  const response = await fetch(`${endpoint}?action=upload`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "content-type": entry.contentType,
      "content-length": String(bytes.byteLength),
      "x-lws-lease-id": binding.leaseId,
      "x-lws-build-id": binding.buildId,
      "x-lws-repository-id": binding.repositoryId,
      "x-lws-commit-sha": binding.commitSha,
      "x-lws-workflow-run-id": binding.workflowRunId,
      "x-lws-relative-path": entry.path,
      "x-lws-sha256": entry.sha256,
    },
    body: Uint8Array.from(bytes).buffer,
  });
  return { status: response.status, body: await response.json() };
}

Deno.test({
  name: "local full chain: authorized acquire -> OIDC -> artifact HTTP -> upload CLI -> finalize -> status",
  ignore: !(await dockerAvailable()),
  fn: async () => {
    const sourceRoot = await Deno.makeTempDir({ prefix: "lws-preview-source-" });
    const npmCache = await Deno.makeTempDir({ prefix: "lws-preview-npm-cache-" });
    const network = `lws-preview-${crypto.randomUUID().slice(0, 8)}`;
    const proxy = `${network}-proxy`;
    let artifactServer: Deno.HttpServer | null = null;
    let oidcServer: Deno.HttpServer | null = null;
    let environment: Awaited<ReturnType<typeof localSupabaseEnvironment>> | null = null;
    const previousEnvironment = new Map<string, string | undefined>();
    try {
      await checkoutExactCustomerSource(sourceRoot);
      await Deno.stat(`${sourceRoot}/package-lock.json`);
      await assertRejects(() => Deno.stat(`${sourceRoot}/.git`));
      environment = await localSupabaseEnvironment();
      const { apiUrl, secretKey, serviceRoleKey } = environment;
      const authority = await seedPreviewAuthority();
      const rpcClient = createRealRpcClient();
      const oidcProvider = await createLocalOidcProvider();
      oidcServer = oidcProvider.server;
      const runtimeEnvironment = new Map([
        ["SUPABASE_URL", apiUrl],
        ["SUPABASE_SECRET_KEYS", JSON.stringify({ default: secretKey })],
        ["LWS_PREVIEW_OIDC_AUDIENCE", OIDC_AUDIENCE],
        ["LWS_PREVIEW_WORKFLOW_REPOSITORY", WORKFLOW_REPOSITORY],
        ["LWS_PREVIEW_WORKFLOW_REPOSITORY_ID", WORKFLOW_REPOSITORY_ID],
        ["LWS_PREVIEW_WORKFLOW_REF", WORKFLOW_REF],
        ["LWS_PREVIEW_WORKFLOW_REF_NAME", WORKFLOW_REF_NAME],
      ]);
      const runtime = createWebsiteProjectPreviewArtifactRuntime(
        { get: (name) => runtimeEnvironment.get(name) },
        (input, init) => String(input) === "https://token.actions.githubusercontent.com/.well-known/jwks"
          ? fetch(`${oidcProvider.baseUrl}/jwks`, init)
          : fetch(input, init),
      );
      artifactServer = Deno.serve(
        { hostname: "127.0.0.1", port: 0, onListen: () => {} },
        (request) => handleWebsiteProjectPreviewArtifact(request, runtime),
      );
      const artifactEndpoint = `http://127.0.0.1:${(artifactServer.addr as Deno.NetAddr).port}`;
      const setEnvironment = (name: string, value: string) => {
        previousEnvironment.set(name, Deno.env.get(name));
        Deno.env.set(name, value);
      };

      assert((await command("docker", ["network", "create", "--internal", network])).success);
      const proxyStart = await command("docker", [
        "run", "-d", "--rm", "--name", proxy,
        "-v", `${PROXY_ROOT}/tinyproxy.conf:/etc/tinyproxy/tinyproxy.conf:ro`,
        "-v", `${PROXY_ROOT}/filter.allow:/etc/tinyproxy/filter.allow:ro`,
        "vimagick/tinyproxy:latest",
      ]);
      if (!proxyStart.success) throw new Error(proxyStart.stderr || proxyStart.stdout);
      assert((await command("docker", ["network", "connect", network, proxy])).success);

      const directEgress = await command("docker", [
        "run", "--rm", "--network", network, "node:24.21.0-slim",
        "node", "-e", "await fetch('https://example.com',{signal:AbortSignal.timeout(3000)})",
      ]);
      assertEquals(directEgress.success, false);

      const buildResult = await command("docker", [
        "run", "--rm", "--network", network,
        "-e", `HTTP_PROXY=http://${proxy}:8888`, "-e", `HTTPS_PROXY=http://${proxy}:8888`,
        "-e", `npm_config_proxy=http://${proxy}:8888`, "-e", `npm_config_https_proxy=http://${proxy}:8888`,
        "-e", "HOME=/tmp/home", "-e", "npm_config_cache=/npm-cache",
        "-v", `${sourceRoot}:/workspace:rw`, "-v", `${npmCache}:/npm-cache:rw`, "-w", "/workspace",
        "--cap-drop=ALL", "--security-opt=no-new-privileges", "--pids-limit=512", "--memory=2g", "--cpus=2",
        "node:24.21.0-slim", "sh", "-c", "npm ci --ignore-scripts --no-audit --no-fund --loglevel=error && npm run build --loglevel=error",
      ]);
      if (!buildResult.success) throw new Error(`isolated Astro build failed:\n${buildResult.stderr}`);
      const proxyLogs = await command("docker", ["logs", proxy]);
      assertMatch(`${proxyLogs.stdout}\n${proxyLogs.stderr}`, /registry[.]npmjs[.]org/i);

      const distRoot = `${sourceRoot}/dist`;
      const manifest = await buildWebsiteProjectPreviewArtifactManifest(distRoot);
      assert(manifest.rejected.some((entry) => entry.path === "favicon.svg" && entry.reason === "ASSET_TYPE_BLOCKED"));
      assert(manifest.rejected.some((entry) => entry.path === "social-card.svg" && entry.reason === "ASSET_TYPE_BLOCKED"));
      assert(manifest.accepted.some((entry) => entry.path.endsWith(".css")));
      assert(manifest.accepted.some((entry) => entry.path === "404.html"));
      const primary = manifest.accepted.find((entry) => entry.path === "index.html");
      assert(primary);
      const acquire = async () => {
        const acquired = await rpcClient.rpc<{ leaseId: string; buildId: string }>(
          "acquire_website_project_preview_build_v1",
          {
            p_quote_request_id: authority.quoteRequestId,
            p_expected_commit_sha: COMMIT_SHA,
            p_idempotency_key: crypto.randomUUID(),
          },
        );
        if (acquired.error || !acquired.data) throw new Error(acquired.error?.message ?? "ACQUIRE_FAILED");
        return acquired.data;
      };
      const bindingFor = (lease: { leaseId: string; buildId: string }) => ({
        leaseId: lease.leaseId,
        buildId: lease.buildId,
        repositoryId: authority.repositoryExternalId,
        commitSha: COMMIT_SHA,
        workflowRunId: WORKFLOW_RUN_ID,
      });
      const issueBody = (lease: { leaseId: string; buildId: string }) => ({
        action: "issue",
        leaseId: lease.leaseId,
        buildId: lease.buildId,
        workflowRunId: WORKFLOW_RUN_ID,
      });

      const rejectionLease = await acquire();
      const validOidcToken = await oidcProvider.token();
      const wrongBinding = await jsonRequest(artifactEndpoint, validOidcToken, {
        ...issueBody(rejectionLease),
        buildId: crypto.randomUUID(),
      });
      assertEquals(wrongBinding.status, 403);
      const expiredOidc = await oidcProvider.token({ iat: 1, nbf: 1, exp: 2 });
      const expired = await jsonRequest(artifactEndpoint, expiredOidc, issueBody(rejectionLease));
      assertEquals(expired.status, 403);
      await releasePreviewLease(rejectionLease.leaseId);

      const incompleteLease = await acquire();
      const incompleteReceipt = await jsonRequest(artifactEndpoint, validOidcToken, issueBody(incompleteLease));
      assertEquals(incompleteReceipt.status, 200, JSON.stringify(incompleteReceipt.body));
      const receiptToken = String(incompleteReceipt.body.token);
      const incompleteBegin = await jsonRequest(artifactEndpoint, receiptToken, {
        action: "begin",
        ...bindingFor(incompleteLease),
        primaryRelativePath: "index.html",
        buildStatus: "PASS_WITH_WARNINGS",
        manifest: manifest.accepted.map(({ path, contentType, sha256, bytes }) => ({
          relativePath: path,
          contentType,
          sha256,
          bytes,
        })),
      });
      assertEquals(incompleteBegin.status, 200, JSON.stringify(incompleteBegin.body));
      const sessionToken = String(incompleteBegin.body.sessionToken);
      const uploadedEntry = manifest.accepted[0];
      const incompleteUpload = await uploadRequest(
        artifactEndpoint,
        sessionToken,
        bindingFor(incompleteLease),
        uploadedEntry,
        await Deno.readFile(`${distRoot}/${uploadedEntry.path}`),
      );
      assertEquals(incompleteUpload.status, 200, JSON.stringify(incompleteUpload.body));
      const incompleteFinalize = await jsonRequest(artifactEndpoint, sessionToken, {
        action: "finalize",
        ...bindingFor(incompleteLease),
      });
      assertEquals(incompleteFinalize.status, 503);
      assertEquals(incompleteFinalize.body.code, "PROJECT_PREVIEW_UPLOAD_SESSION_INCOMPLETE");
      const cleanedObject = await fetch(
        storageObjectUrl(apiUrl, incompleteLease.buildId, uploadedEntry.path),
        { headers: storageHeaders(serviceRoleKey) },
      );
      assertEquals(cleanedObject.status, 400);
      await releasePreviewLease(incompleteLease.leaseId);

      const successLease = await acquire();
      setEnvironment("LWS_PREVIEW_ARTIFACT_ENDPOINT", artifactEndpoint);
      setEnvironment("LWS_PREVIEW_LEASE_ID", successLease.leaseId);
      setEnvironment("LWS_PREVIEW_BUILD_ID", successLease.buildId);
      setEnvironment("LWS_PREVIEW_REPOSITORY_ID", authority.repositoryExternalId);
      setEnvironment("LWS_PREVIEW_COMMIT_SHA", COMMIT_SHA);
      setEnvironment("GITHUB_RUN_ID", WORKFLOW_RUN_ID);
      setEnvironment("LWS_PREVIEW_DIST_ROOT", distRoot);
      setEnvironment("LWS_PREVIEW_OIDC_AUDIENCE", OIDC_AUDIENCE);
      setEnvironment("ACTIONS_ID_TOKEN_REQUEST_URL", `${oidcProvider.baseUrl}/token`);
      setEnvironment("ACTIONS_ID_TOKEN_REQUEST_TOKEN", "local-oidc-request-token");
      await runWebsiteProjectPreviewUpload();

      const replay = await jsonRequest(artifactEndpoint, validOidcToken, issueBody(successLease));
      assertEquals(replay.status, 403);
      const persisted = JSON.parse(await psql(`
        select jsonb_build_object(
          'build_id', lease.authorized_build_id, 'status', b.build_status,
          'artifact_path', b.artifact_path, 'artifact_sha256', b.artifact_sha256,
          'artifact_bytes', b.artifact_bytes,
          'manifest', jsonb_agg(jsonb_build_object(
            'relativePath', a.relative_path, 'contentType', a.content_type,
            'sha256', a.sha256, 'bytes', a.bytes
          ) order by a.relative_path)
        )::text
        from lws_internal.website_project_preview_builds b
        join lws_internal.website_project_preview_build_leases lease on lease.preview_lease_id=b.lease_id
        join lws_internal.website_project_preview_build_artifacts a on a.preview_build_id=b.preview_build_id
        where b.lease_id=${sqlLiteral(successLease.leaseId)}::uuid
        group by b.preview_build_id, lease.authorized_build_id;
      `));
      assertEquals(persisted.build_id, successLease.buildId);
      assertEquals(persisted.status, "PASS_WITH_WARNINGS");
      assertEquals(persisted.artifact_path, "index.html");
      assertEquals(persisted.artifact_sha256, primary.sha256);
      assertEquals(Number(persisted.artifact_bytes), manifest.totalBytes);
      const persistedByPath = Object.fromEntries(
        (persisted.manifest as Record<string, unknown>[]).map((entry) => [entry.relativePath, entry]),
      );
      assertEquals(persistedByPath, Object.fromEntries(
        manifest.accepted.map(({ path, contentType, sha256, bytes }) => [path, {
          relativePath: path,
          contentType,
          sha256,
          bytes,
        }]),
      ));
      for (const entry of manifest.accepted) {
        const stored = await fetch(storageObjectUrl(apiUrl, successLease.buildId, entry.path), {
          headers: storageHeaders(serviceRoleKey),
        });
        assertEquals(stored.status, 200);
        const storedBytes = new Uint8Array(await stored.arrayBuffer());
        assertEquals(storedBytes, await Deno.readFile(`${distRoot}/${entry.path}`));
        assertEquals(await sha256HexBytes(storedBytes), entry.sha256);
      }
      const status = await rpcClient.rpc<{ buildStatus: string; previewBuildId: string }>(
        "get_website_project_preview_build_status_v1",
        { p_lease_id: successLease.leaseId },
      );
      assertEquals(status.error, null);
      assertEquals(status.data?.buildStatus, "PASS_WITH_WARNINGS");
    } finally {
      for (const [name, value] of previousEnvironment) {
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
      if (artifactServer) await artifactServer.shutdown();
      if (oidcServer) await oidcServer.shutdown();
      await command("docker", ["rm", "-f", proxy]).catch(() => {});
      await command("docker", ["network", "rm", network]).catch(() => {});
      await Deno.remove(sourceRoot, { recursive: true }).catch(() => {});
      await Deno.remove(npmCache, { recursive: true }).catch(() => {});
    }
  },
});