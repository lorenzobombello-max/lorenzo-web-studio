import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

export const C3_COMMIT_SHA = "1f19bf01c61c6da79fa4c7374333a91b70f9bf48";
export const C3_REPOSITORY = "lorenzo-web-solutions/lws-web-a88b1e8792714ad199ccb385b7982a8b";
export const C3_REPOSITORY_ID = "1378797607";
export const C3_ACTOR_ID = "c9bcd3ef-1e7e-4889-8a12-db827f1b97b0";

const C3_QUOTE_REQUEST_ID = "a1e5c3e8-27a6-47c3-8ec1-75653bd2e8ac";
const C3_CONTEXT_ID = "b41c307f-899f-4ac3-9bd2-c99789bb78df";
const C3_CONCEPT_ID = "69d450e4-3110-4625-a0a8-0488348a96d3";
const C3_WORKSPACE_ID = "75655da3-fab3-4347-9099-041d8e1a0729";
const OPERATOR_WORKSPACE_ID = "22222222-2222-4222-8222-222222222222";
const SUPABASE_URL = "https://xcsptvntvrizwhskaphr.supabase.co";
const SESSION_STORAGE_KEY = "sb-xcsptvntvrizwhskaphr-auth-token";
const DB_CONTAINER = "supabase_db_xcsptvntvrizwhskaphr";
const PREVIEW_ORIGIN = "https://preview.local";
const rootPath = fileURLToPath(new URL("../", import.meta.url));

export function assertC3SourceBinding(value) {
  const [repositoryOwner, repositoryName] = C3_REPOSITORY.split("/");
  if (value?.repositoryOwner !== repositoryOwner
    || value?.repositoryName !== repositoryName
    || String(value?.repositoryExternalId) !== C3_REPOSITORY_ID) {
    throw new Error("C3_SOURCE_BINDING_INVALID");
  }
  return Object.freeze({ repositoryOwner, repositoryName, repositoryExternalId: C3_REPOSITORY_ID });
}

export function selectC3Build(rows) {
  const eligible = (Array.isArray(rows) ? rows : [])
    .filter((row) => row?.commitSha === C3_COMMIT_SHA
      && ["PASS", "PASS_WITH_WARNINGS"].includes(row?.status)
      && Number(row?.artifactCount) > 0
      && typeof row?.buildId === "string")
    .sort((left, right) => Date.parse(right.builtAt) - Date.parse(left.builtAt));
  if (!eligible[0]) throw new Error("C3_BUILD_NOT_AVAILABLE");
  return Object.freeze({ ...eligible[0] });
}

export function authorizeC3OperatorSession(value, nowSeconds = Math.floor(Date.now() / 1000)) {
  if (value?.actorId !== C3_ACTOR_ID || value?.role !== "owner" || value?.status !== "ACTIVE") {
    throw new Error("C3_OPERATOR_NOT_AUTHORIZED");
  }
  if (value?.aal !== "aal2") throw new Error("C3_AAL2_REQUIRED");
  if (!Number.isFinite(value?.expiresAt) || value.expiresAt <= nowSeconds + 15) {
    throw new Error("C3_OPERATOR_SESSION_EXPIRED");
  }
  return true;
}

export function translateC3HandoffUrl(handoffUrl, gatewayOrigin, previewOrigin = PREVIEW_ORIGIN) {
  const handoff = new URL(String(handoffUrl));
  const gateway = new URL(String(gatewayOrigin));
  const preview = new URL(String(previewOrigin));
  if (handoff.origin !== gateway.origin || handoff.pathname !== "/__preview-session"
    || preview.protocol !== "https:" || preview.pathname !== "/"
    || !handoff.searchParams.get("build") || !handoff.searchParams.get("token")) {
    throw new Error("C3_HANDOFF_URL_INVALID");
  }
  return new URL(`${handoff.pathname}${handoff.search}`, preview).href;
}

export function createC3BrowserLaunchOptions() {
  return {
    headless: false,
    ignoreDefaultArgs: ["--disable-popup-blocking"],
    args: ["--start-maximized"],
  };
}

export function createC3BrowserContextOptions() {
  return { viewport: null };
}

function base64urlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function sessionPayload(nowSeconds = Math.floor(Date.now() / 1000)) {
  const expiresAt = nowSeconds + 3600;
  authorizeC3OperatorSession({
    actorId: C3_ACTOR_ID,
    role: "owner",
    status: "ACTIVE",
    aal: "aal2",
    expiresAt,
  }, nowSeconds);
  return {
    access_token: `${base64urlJson({ alg: "HS256", typ: "JWT" })}.${base64urlJson({
      sub: C3_ACTOR_ID,
      role: "authenticated",
      aal: "aal2",
      amr: [{ method: "totp", timestamp: nowSeconds }],
      exp: expiresAt,
    })}.local-c3-signature`,
    refresh_token: "local-c3-refresh-token",
    user: { id: C3_ACTOR_ID, aud: "authenticated", role: "authenticated", email: "owner@local.test" },
    token_type: "bearer",
    expires_in: 3600,
    expires_at: expiresAt,
  };
}

async function command(program, args) {
  const result = await new Deno.Command(program, { args }).output();
  const stdout = new TextDecoder().decode(result.stdout).trim();
  const stderr = new TextDecoder().decode(result.stderr).trim();
  if (!result.success) throw new Error(stderr || stdout || `${program} failed`);
  return stdout;
}

async function psql(sql) {
  const stdout = await command("docker", [
    "exec", "-i", DB_CONTAINER, "psql", "-U", "postgres", "-d", "postgres",
    "-v", "ON_ERROR_STOP=1", "-qAt", "-c", sql,
  ]);
  return stdout.split(/\r?\n/).filter(Boolean).at(-1) ?? "";
}

async function localSupabaseEnvironment() {
  const status = await command("npx", ["supabase", "status", "-o", "env"]);
  const apiUrl = /API_URL="([^"]+)"/.exec(status)?.[1];
  const serviceRoleKey = /SERVICE_ROLE_KEY="([^"]+)"/.exec(status)?.[1];
  if (!apiUrl || !serviceRoleKey) throw new Error("C3_LOCAL_SUPABASE_UNAVAILABLE");
  return { apiUrl, serviceRoleKey };
}

async function readC3State() {
  const binding = JSON.parse(await psql(`
    select jsonb_build_object(
      'repositoryOwner', repository_owner,
      'repositoryName', repository_name,
      'repositoryExternalId', repository_external_id
    )::text
    from public.website_execution_workspaces
    where website_workspace_id='${C3_WORKSPACE_ID}'::uuid;
  `));
  assertC3SourceBinding(binding);
  const builds = JSON.parse(await psql(`
    select coalesce(jsonb_agg(candidate order by (candidate->>'builtAt') desc), '[]'::jsonb)::text
    from (
      select jsonb_build_object(
        'buildId', lease.authorized_build_id,
        'previewBuildId', build.preview_build_id,
        'commitSha', build.commit_sha,
        'status', build.build_status,
        'builtAt', build.built_at,
        'artifactCount', count(artifact.*)
      ) candidate
      from lws_internal.website_project_preview_builds build
      join lws_internal.website_project_preview_build_leases lease on lease.preview_lease_id=build.lease_id
      join lws_internal.website_project_preview_build_artifacts artifact on artifact.preview_build_id=build.preview_build_id
      where build.commit_sha='${C3_COMMIT_SHA}'
      group by build.preview_build_id, lease.authorized_build_id
    ) candidates;
  `));
  const build = selectC3Build(builds);
  const artifacts = JSON.parse(await psql(`
    select jsonb_agg(jsonb_build_object(
      'path', artifact.relative_path,
      'contentType', artifact.content_type,
      'sha256', artifact.sha256,
      'bytes', artifact.bytes
    ) order by artifact.relative_path)::text
    from lws_internal.website_project_preview_builds build
    join lws_internal.website_project_preview_build_artifacts artifact on artifact.preview_build_id=build.preview_build_id
    where build.preview_build_id='${build.previewBuildId}'::uuid;
  `));
  return { binding, build, artifacts };
}

function mimeType(path) {
  return {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".ico": "image/x-icon",
    ".png": "image/png",
    ".svg": "image/svg+xml",
  }[extname(path).toLowerCase()] || "application/octet-stream";
}

function serveRepository() {
  const server = createServer(async (request, response) => {
    const requestUrl = new URL(request.url || "/", `http://${request.headers.host}`);
    if (requestUrl.pathname === "/assets/config/operator-auth.json") {
      response.setHeader("content-type", "application/json; charset=utf-8");
      response.end(JSON.stringify({
        supabaseUrl: SUPABASE_URL,
        callbackUrl: `${requestUrl.origin}/operator/auth/callback/`,
        publishableKey: "local-c3-publishable-key",
      }));
      return;
    }
    let relative = normalize(decodeURIComponent(requestUrl.pathname)).replace(/^[/\\]+/, "");
    if (relative.includes("..")) {
      response.writeHead(403).end();
      return;
    }
    if (!relative || requestUrl.pathname.endsWith("/")) relative = join(relative, "index.html");
    try {
      const body = await readFile(join(rootPath, relative));
      response.setHeader("content-type", mimeType(relative));
      response.end(body);
    } catch {
      response.writeHead(404).end();
    }
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

function websiteExecutionProjection(build) {
  const [repositoryOwner, repositoryName] = C3_REPOSITORY.split("/");
  return {
    contract_version: 5,
    mode: "PRE_PROJECT",
    quote_request_id: C3_QUOTE_REQUEST_ID,
    concept_id: C3_CONCEPT_ID,
    project_id: null,
    website_work_context_id: C3_CONTEXT_ID,
    context_revision: 1,
    briefing_status: "COMPLETE",
    commercially_released: false,
    project: null,
    start_gate: null,
    workspace: {
      website_workspace_id: C3_WORKSPACE_ID,
      website_work_context_id: C3_CONTEXT_ID,
      project_id: null,
      quote_request_id: C3_QUOTE_REQUEST_ID,
      workspace_state: "REPOSITORY_READY",
      repository_operation_state: "COMPLETE",
      repository_failure_category: null,
      repository_recovery_guidance: null,
      repository_provider: "GITHUB",
      repository_owner: repositoryOwner,
      repository_name: repositoryName,
      repository_navigation_url: `https://github.com/${C3_REPOSITORY}`,
      default_branch: "main",
      preview_branch: null,
      preview_url: null,
      last_commit_sha: C3_COMMIT_SHA,
      last_commit_at: build.builtAt,
      last_build_result: build.status === "PASS_WITH_WARNINGS" ? "PASS" : build.status,
      last_build_at: build.builtAt,
      binding_revision: 1,
      provisioned_by: C3_ACTOR_ID,
      provisioned_at: build.builtAt,
      created_at: build.builtAt,
      updated_at: build.builtAt,
      capabilities: {
        project_files_read: true,
        project_files_write: true,
        repository_retry_allowed: false,
        repository_recovery_required: false,
      },
      repository_recovery_operation_id: null,
    },
    requirements: { state: "NOT_AVAILABLE", message: "Requirements volgen na intake-sync." },
  };
}

export function createC3DetailProjection() {
  return {
    quote_request_id: C3_QUOTE_REQUEST_ID,
    request_kind: "website",
    name: "0006 klantpreview",
    application_reference: "LWS-0006",
    support_reference: "#00000006",
    organization: "0006 klantpreview",
    customer: {
      name: "0006 klantpreview",
      company: "0006 klantpreview",
      email: "preview@local.test",
      phone: null,
      full_name: "0006 klantpreview",
    },
    application: null,
    acceptance: null,
    quotation: null,
    project: null,
    dossier_lifecycle: { state: "ACTIVE", revision: 0 },
    website_work: {
      state: "PRE_PROJECT",
      quote_request_id: C3_QUOTE_REQUEST_ID,
      concept_id: C3_CONCEPT_ID,
      project_id: null,
      website_work_context_id: C3_CONTEXT_ID,
      mode: "PRE_PROJECT",
      briefing_status: "COMPLETE",
      commercially_released: false,
      revision: 1,
      permitted_actions: ["OPEN_WEBSITE"],
    },
  };
}

export function createC3DossierSubstance() {
  return Object.freeze({
    quote_request_id: C3_QUOTE_REQUEST_ID,
    request_kind: "website",
    request: {
      reference: "#GIT-001C3",
      requested_at: "2026-09-23T08:00:00Z",
      original_text: "Lokale 0006 klantpreview.",
    },
    customer: {
      name: "0006 klantpreview",
      company: "0006 klantpreview",
      email: "preview@local.test",
      phone: null,
    },
    intake: {
      intake_id: "77777777-7777-4777-8777-777777777777",
      status: "submitted",
      invited_at: "2026-09-23T07:00:00Z",
      started_at: "2026-09-23T07:15:00Z",
      submitted_at: "2026-09-23T07:30:00Z",
      structured_answers: {
        business_description: "Bestaande 0006-bronbinding",
        website_goals: ["Lokale klantpreview"],
      },
    },
    documents: { customer_request_count: 0, uploaded_document_count: 0 },
  });
}

function requirementsProjection() {
  return {
    contract_version: 1,
    quote_request_id: C3_QUOTE_REQUEST_ID,
    website_work_context_id: C3_CONTEXT_ID,
    project_id: null,
    phase: "PRE_PROJECT",
    context: { customer: "0006 klantpreview", dossier_reference: "LWS-0006", assigned_operator: null },
    board: null,
    items: [],
    progress: {
      required_total: 0,
      required_completed: 0,
      required_open: 0,
      required_blocked: 0,
      review_pending: 0,
    },
    readiness: { ready_for_preview: false, readiness: "UNKNOWN", reason: "Nog geen requirements-board." },
    empty_state: "NO_BOARD",
  };
}

function routeJson(route, status, body) {
  return route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
}

async function configureBrowserRoutes(context, runtime) {
  let statusPolls = 0;
  await context.route(`${SUPABASE_URL}/**`, async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const body = request.postDataJSON?.() ?? {};
    const rpcName = url.pathname.startsWith("/rest/v1/rpc/") ? url.pathname.split("/").at(-1) : null;
    if (url.pathname === "/auth/v1/user") return routeJson(route, 200, sessionPayload().user);
    if (url.pathname.startsWith("/auth/v1/token")) return routeJson(route, 200, sessionPayload());
    if (rpcName === "get_current_operator_identity_v1") {
      return routeJson(route, 200, { display_name: "Lorenzo Owner", role: "owner", status: "ACTIVE" });
    }
    if (rpcName === "join_operator_workspace_v1") {
      const valid = body.p_workspace_id === OPERATOR_WORKSPACE_ID && body.p_module_key === "dossiers"
        && body.p_slot_key === `website-${C3_QUOTE_REQUEST_ID}`;
      return routeJson(route, valid ? 200 : 403, valid ? {
        joined: true,
        window_id: body.p_window_id,
        module_key: body.p_module_key,
        slot_key: body.p_slot_key,
        lease_expires_at: new Date(Date.now() + 60_000).toISOString(),
      } : { code: "WORKSPACE_JOIN_REJECTED" });
    }
    if (rpcName === "get_operator_workspace_status_v1") {
      return routeJson(route, 200, { valid: true, lease_expires_at: new Date(Date.now() + 60_000).toISOString() });
    }
    if (url.pathname === "/functions/v1/commercial-operator-command") {
      const action = body.action;
      let result;
      if (action === "get_application_detail") result = createC3DetailProjection();
      else if (action === "get_dossier_substance") result = createC3DossierSubstance();
      else if (action === "get_dossier_assignment") {
        result = { revision: 0, assignee_operator_id: null, assignee_display_name: null };
      } else if (action === "get_website_execution_workspace") result = websiteExecutionProjection(runtime.build);
      else if (action === "get_website_requirements_board") result = requirementsProjection();
      else if (action === "request_website_project_preview_build") {
        if (body.quote_request_id !== C3_QUOTE_REQUEST_ID || body.expected_commit_sha !== C3_COMMIT_SHA) {
          return routeJson(route, 403, { ok: false, code: "PROJECT_PREVIEW_AUTHORITY_MISMATCH" });
        }
        statusPolls = 0;
        result = { lease_id: runtime.leaseId };
      } else if (action === "get_website_project_preview_build_status") {
        statusPolls += 1;
        result = statusPolls < 2
          ? { status: "BUILD_IN_PROGRESS", preview_build_id: null }
          : { status: runtime.build.status, preview_build_id: runtime.build.previewBuildId };
      } else if (action === "create_website_project_preview_session") {
        if (body.preview_build_id !== runtime.build.previewBuildId) {
          return routeJson(route, 403, { ok: false, code: "PROJECT_PREVIEW_BUILD_FORBIDDEN" });
        }
        result = { handoff_url: await runtime.createHandoff() };
      } else {
        return routeJson(route, 400, { ok: false, code: `C3_ACTION_NOT_AVAILABLE_${action}` });
      }
      return routeJson(route, 200, { ok: true, result });
    }
    return routeJson(route, 404, { code: "C3_ROUTE_NOT_AVAILABLE" });
  });

  await context.route(`${PREVIEW_ORIGIN}/**`, async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const gatewayUrl = new URL(`${url.pathname}${url.search}`, runtime.gateway.baseUrl);
    const response = await runtime.gateway.handleRequest(new Request(gatewayUrl, {
      method: request.method(),
      headers: request.headers(),
    }));
    const headers = Object.fromEntries(response.headers.entries());
    const body = response.body ? Buffer.from(await response.arrayBuffer()) : undefined;
    await route.fulfill({ status: response.status, headers, body });
  });
}

async function createRuntime() {
  const [{ chromium }, { createLocalWebsiteProjectPreviewHostingGateway }] = await Promise.all([
    import("npm:@playwright/test@1.63.0"),
    import("../supabase/functions/_shared/website-project-preview-local-hosting-gateway.ts"),
  ]);
  const [{ apiUrl, serviceRoleKey }, state] = await Promise.all([
    localSupabaseEnvironment(),
    readC3State(),
  ]);
  const gateway = await createLocalWebsiteProjectPreviewHostingGateway();
  gateway.registerBuild({ previewBuildId: state.build.previewBuildId, actorAuthUserId: C3_ACTOR_ID });
  for (const artifact of state.artifacts) {
    const response = await fetch(
      `${apiUrl}/storage/v1/object/website-project-previews/${state.build.buildId}/${artifact.path}`,
      { headers: { apikey: serviceRoleKey, authorization: `Bearer ${serviceRoleKey}` } },
    );
    if (!response.ok) throw new Error(`C3_STORAGE_OBJECT_UNAVAILABLE:${artifact.path}`);
    gateway.putAsset({
      previewBuildId: state.build.previewBuildId,
      relativePath: artifact.path,
      contentType: artifact.contentType,
      bytes: new Uint8Array(await response.arrayBuffer()),
    });
  }
  const server = await serveRepository();
  const address = server.address();
  const operatorOrigin = `http://127.0.0.1:${address.port}`;
  const browser = await chromium.launch(createC3BrowserLaunchOptions());
  const leaseId = crypto.randomUUID();
  return {
    ...state,
    browser,
    gateway,
    leaseId,
    operatorOrigin,
    server,
    async createHandoff() {
      const session = await gateway.publish({
        previewBuildId: state.build.previewBuildId,
        actorAuthUserId: C3_ACTOR_ID,
        manifest: { root: "private-storage", accepted: [], rejected: [], totalBytes: 0 },
        buildStatus: state.build.status,
      });
      return translateC3HandoffUrl(session.handoffUrl, gateway.baseUrl);
    },
  };
}

async function validateDeniedAccess(runtime) {
  const noSession = await runtime.gateway.handleRequest(new Request(`${runtime.gateway.baseUrl}/`));
  if (noSession.status !== 401) throw new Error("C3_MISSING_PREVIEW_ACCESS_NOT_REJECTED");
  authorizeC3OperatorSession({
    actorId: C3_ACTOR_ID,
    role: "owner",
    status: "ACTIVE",
    aal: "aal2",
    expiresAt: 1,
  }, 1_000);
}

async function run() {
  const runtime = await createRuntime();
  let context;
  try {
    try {
      await validateDeniedAccess(runtime);
      throw new Error("C3_EXPIRED_OPERATOR_ACCESS_NOT_REJECTED");
    } catch (error) {
      if (error.message !== "C3_OPERATOR_SESSION_EXPIRED") throw error;
    }
    context = await runtime.browser.newContext(createC3BrowserContextOptions());
    await configureBrowserRoutes(context, runtime);
    const seededSession = JSON.stringify(sessionPayload());
    await context.addInitScript(({ key, value }) => localStorage.setItem(key, value), {
      key: SESSION_STORAGE_KEY,
      value: seededSession,
    });
    const windowId = crypto.randomUUID();
    const launchNonce = crypto.randomUUID();
    const slot = `website-${C3_QUOTE_REQUEST_ID}`;
    const operatorUrl = `${runtime.operatorOrigin}/operator/window/?module=dossiers`
      + `#workspace=${OPERATOR_WORKSPACE_ID}&epoch=1&window=${windowId}&launch=${launchNonce}&slot=${slot}`;
    const page = await context.newPage();
    await page.goto(operatorUrl, { waitUntil: "domcontentloaded" });
    const previewButton = page.getByRole("button", { name: "Preview bouwen / vernieuwen" });
    await previewButton.waitFor({ state: "visible", timeout: 30_000 });
    await page.waitForTimeout(1_000);
    await previewButton.click();
    await page.locator("[data-website-message]").filter({ hasText: "Preview gereed" })
      .waitFor({ state: "visible", timeout: 30_000 });
    const previewLink = page.getByRole("link", { name: "Preview openen" });
    await previewLink.waitFor({ state: "visible" });
    const previewPagePromise = context.waitForEvent("page");
    await previewLink.click();
    const previewPage = await previewPagePromise;
    await previewPage.waitForLoadState("domcontentloaded");
    await previewPage.getByRole("heading", { name: "Make the important thing unmistakable." })
      .waitFor({ state: "visible", timeout: 20_000 });
    const styled = await previewPage.locator("body").evaluate((element) => getComputedStyle(element).backgroundColor !== "rgba(0, 0, 0, 0)");
    if (!styled) throw new Error("C3_PREVIEW_CSS_NOT_APPLIED");
    await previewPage.getByRole("link", { name: "Principles" }).click();
    if (!previewPage.url().endsWith("#principles")) throw new Error("C3_PREVIEW_NAVIGATION_FAILED");
    await page.bringToFront();
    console.log(JSON.stringify({
      ready: true,
      operatorUrl: `${runtime.operatorOrigin}/operator/window/?module=dossiers`,
      previewUrl: `${PREVIEW_ORIGIN}/#principles`,
      repository: C3_REPOSITORY,
      repositoryId: C3_REPOSITORY_ID,
      commitSha: C3_COMMIT_SHA,
      buildId: runtime.build.buildId,
      buildStatus: runtime.build.status,
      artifacts: runtime.artifacts.map((artifact) => artifact.path),
      simulated: ["operator session/AAL2 responses", "build dispatch and polling", "preview.local DNS/TLS route"],
      real: ["operator page and controllers", "private Storage bytes", "hosting gateway handoff/session", "CSS and navigation"],
    }));
    console.log("C3 demo blijft actief. Sluit het Chromium-venster of stop dit proces om af te sluiten.");
    await new Promise((resolve) => {
      const finish = () => resolve();
      Deno.addSignalListener("SIGINT", finish);
      runtime.browser.on("disconnected", finish);
    });
  } finally {
    await context?.close().catch(() => {});
    await runtime.browser.close().catch(() => {});
    await runtime.gateway.close().catch(() => {});
    runtime.server.closeAllConnections?.();
    await new Promise((resolve) => runtime.server.close(resolve));
  }
}

if (import.meta.main) await run();