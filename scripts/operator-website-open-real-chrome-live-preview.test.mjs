import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";
import test from "node:test";
import { chromium } from "@playwright/test";

const root = new URL("../", import.meta.url);
const rootPath = decodeURIComponent(root.pathname).replace(/^\/(?:([A-Za-z]:))/, "$1");
const supabaseUrl = "https://xcsptvntvrizwhskaphr.supabase.co";
const sessionStorageKey = "sb-xcsptvntvrizwhskaphr-auth-token";
const operatorId = "11111111-1111-4111-8111-111111111111";
const workspaceId = "22222222-2222-4222-8222-222222222222";
const renewalToken = "33333333-3333-4333-8333-333333333333";
const quoteRequestId = "44444444-4444-4444-8444-444444444444";
const conceptId = "55555555-5555-4555-8555-555555555555";
const websiteWorkContextId = "66666666-6666-4666-8666-666666666666";
const intakeId = "77777777-7777-4777-8777-777777777777";
const operatorAuthConfigKey = "/assets/config/operator-auth.json";

function base64urlJson(value) {
  return Buffer.from(JSON.stringify(value))
    .toString("base64")
    .replace(/=+$/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function sessionPayload(nowSeconds = Math.floor(Date.now() / 1000)) {
  const accessToken = `${base64urlJson({ alg: "HS256", typ: "JWT" })}.${base64urlJson({
    sub: operatorId,
    role: "authenticated",
    exp: nowSeconds + 3600,
  })}.signature`;
  return {
    access_token: accessToken,
    refresh_token: "refresh-token-test-value",
    user: {
      id: operatorId,
      aud: "authenticated",
      role: "authenticated",
      email: "owner@example.test",
    },
    token_type: "bearer",
    expires_in: 3600,
    expires_at: nowSeconds + 3600,
  };
}

function operatorIdentity() {
  return {
    display_name: "Lorenzo Owner",
    role: "owner",
    status: "ACTIVE",
  };
}

function dossierSummary() {
  return {
    quote_request_id: quoteRequestId,
    application_reference: "LWS-AAN-2099-0001",
    support_reference: "#5C19F9DD",
    name: "Preview customer",
    organization: "Preview customer",
    request_kind: "website",
    dossier_date: "2099-01-05T10:00:00Z",
    operational_status: "PRE_PROJECT",
    zone: "ACTIVE",
    seen_at: null,
  };
}

function dossierDetail() {
  return {
    quote_request_id: quoteRequestId,
    request_kind: "website",
    name: "Preview customer",
    application_reference: "LWS-AAN-2099-0001",
    support_reference: "#5C19F9DD",
    organization: "Preview customer",
    customer: {
      name: "Preview customer",
      company: "Preview customer",
      email: "preview@example.test",
      phone: null,
      full_name: "Preview customer",
    },
    application: null,
    acceptance: null,
    quotation: null,
    project: null,
    dossier_lifecycle: { state: "ACTIVE", revision: 0 },
    website_work: {
      state: "PRE_PROJECT",
      quote_request_id: quoteRequestId,
      concept_id: conceptId,
      project_id: null,
      website_work_context_id: websiteWorkContextId,
      mode: "PRE_PROJECT",
      briefing_status: "COMPLETE",
      commercially_released: false,
      revision: 1,
      permitted_actions: ["OPEN_WEBSITE"],
    },
  };
}

function dossierSubstance() {
  return {
    quote_request_id: quoteRequestId,
    request_kind: "website",
    request: {
      reference: "#5C19F9DD",
      requested_at: "2099-01-05T10:00:00Z",
      original_text: "Website voor live preview reproduceren.",
    },
    customer: {
      name: "Preview customer",
      company: "Preview customer",
      email: "preview@example.test",
      phone: null,
    },
    intake: {
      intake_id: intakeId,
      status: "submitted",
      invited_at: "2099-01-05T09:00:00Z",
      started_at: "2099-01-05T09:15:00Z",
      submitted_at: "2099-01-05T09:30:00Z",
      structured_answers: {
        business_description: "Preview business",
        website_goals: ["Leads"],
      },
    },
    documents: {
      customer_request_count: 0,
      uploaded_document_count: 0,
    },
  };
}

function websiteExecutionProjection() {
  return {
    contract_version: 5,
    mode: "PRE_PROJECT",
    quote_request_id: quoteRequestId,
    concept_id: conceptId,
    project_id: null,
    website_work_context_id: websiteWorkContextId,
    context_revision: 1,
    briefing_status: "COMPLETE",
    commercially_released: false,
    project: null,
    start_gate: null,
    workspace: null,
    requirements: {
      state: "NOT_AVAILABLE",
      message: "Requirements volgen na intake-sync.",
    },
  };
}

function websiteRequirementsBoard() {
  return {
    contract_version: 1,
    quote_request_id: quoteRequestId,
    website_work_context_id: websiteWorkContextId,
    project_id: null,
    phase: "PRE_PROJECT",
    context: {
      customer: "Preview customer",
      dossier_reference: "LWS-AAN-2099-0001",
      assigned_operator: null,
    },
    board: null,
    items: [],
    progress: {
      required_total: 0,
      required_completed: 0,
      required_open: 0,
      required_blocked: 0,
      review_pending: 0,
    },
    readiness: {
      ready_for_preview: false,
      readiness: "UNKNOWN",
      reason: "Nog geen requirements-board.",
    },
    empty_state: "NO_BOARD",
  };
}

function nextLeaseIso() {
  return new Date(Date.now() + 60_000).toISOString();
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
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
  }[extname(path).toLowerCase()] || "application/octet-stream";
}

function serveRepo() {
  const server = createServer(async (request, response) => {
    const requestUrl = new URL(request.url || "/", "http://127.0.0.1");
    const origin = `http://${request.headers.host}`;
    if (requestUrl.pathname === operatorAuthConfigKey) {
      response.setHeader("content-type", "application/json; charset=utf-8");
      response.end(JSON.stringify({
        supabaseUrl,
        callbackUrl: `${origin}/operator/auth/callback/`,
        publishableKey: "sb_publishable_test_1234567890abcdef",
      }));
      return;
    }
    let relative = normalize(decodeURIComponent(requestUrl.pathname)).replace(/^[/\\]+/, "");
    if (relative.includes("..")) {
      response.writeHead(403).end();
      return;
    }
    if (!relative || requestUrl.pathname.endsWith("/")) relative = join(relative, "index.html");
    const absolute = join(rootPath, relative);
    try {
      const body = await readFile(absolute);
      response.setHeader("content-type", mimeType(absolute));
      response.end(body);
    } catch {
      response.writeHead(404).end();
    }
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

function parseJson(value) {
  if (!value) return null;
  try { return JSON.parse(value); } catch { return null; }
}

function createSupabaseMock() {
  const state = {
    activeMasterWindowId: null,
    epoch: 1,
    leaseExpiresAt: nextLeaseIso(),
    acquireCalls: 0,
    renewCalls: 0,
    joinCalls: 0,
    workspaceStatusCalls: 0,
    functionCalls: [],
    rpcCalls: [],
  };

  const identity = operatorIdentity();
  const summary = dossierSummary();
  const detail = dossierDetail();
  const substance = dossierSubstance();
  const projection = websiteExecutionProjection();
  const requirements = websiteRequirementsBoard();

  return {
    state,
    async handleRoute(route) {
      const request = route.request();
      const url = new URL(request.url());
      const body = parseJson(request.postData());
      const path = url.pathname;
      if (path === "/auth/v1/user") {
        await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(sessionPayload().user) });
        return;
      }
      if (path.startsWith("/auth/v1/token") && request.method() === "POST") {
        await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(sessionPayload()) });
        return;
      }
      if (path.startsWith("/rest/v1/rpc/")) {
        const rpcName = path.split("/").at(-1);
        state.rpcCalls.push({ rpcName, body });
        if (rpcName === "get_current_operator_identity_v1") {
          await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(identity) });
          return;
        }
        if (rpcName === "acquire_operator_workspace_v1") {
          state.acquireCalls += 1;
          const masterWindowId = String(body?.p_master_window_id || "");
          if (!state.activeMasterWindowId) {
            state.activeMasterWindowId = masterWindowId;
            state.leaseExpiresAt = nextLeaseIso();
            await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({
              acquired: true,
              workspace_id: workspaceId,
              epoch: state.epoch,
              renewal_token: renewalToken,
              lease_expires_at: state.leaseExpiresAt,
            }) });
            return;
          }
          await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({
            acquired: false,
            lease_expires_at: new Date(Date.now() + 50).toISOString(),
          }) });
          return;
        }
        if (rpcName === "renew_operator_workspace_lease_v1") {
          state.renewCalls += 1;
          state.leaseExpiresAt = nextLeaseIso();
          await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({
            valid: true,
            lease_expires_at: state.leaseExpiresAt,
          }) });
          return;
        }
        if (rpcName === "join_operator_workspace_v1") {
          state.joinCalls += 1;
          const ok = body?.p_workspace_id === workspaceId
            && Number(body?.p_epoch) === state.epoch
            && typeof body?.p_window_id === "string"
            && body?.p_module_key === "dossiers"
            && typeof body?.p_slot_key === "string";
          state.leaseExpiresAt = nextLeaseIso();
          await route.fulfill({
            status: ok ? 200 : 409,
            contentType: "application/json",
            body: JSON.stringify(ok ? {
              joined: true,
              window_id: body.p_window_id,
              module_key: body.p_module_key,
              slot_key: body.p_slot_key,
              lease_expires_at: state.leaseExpiresAt,
            } : { code: "WORKSPACE_JOIN_REJECTED" }),
          });
          return;
        }
        if (rpcName === "get_operator_workspace_status_v1") {
          state.workspaceStatusCalls += 1;
          state.leaseExpiresAt = nextLeaseIso();
          await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({
            valid: true,
            lease_expires_at: state.leaseExpiresAt,
          }) });
          return;
        }
        if (rpcName === "resume_operator_workspace_v1") {
          await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ resumed: false }) });
          return;
        }
        if (rpcName === "revoke_operator_workspace_v1") {
          await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ revoked: true }) });
          return;
        }
        await route.fulfill({ status: 404, contentType: "application/json", body: JSON.stringify({ code: `UNHANDLED_RPC_${rpcName}` }) });
        return;
      }
      if (path === "/functions/v1/commercial-operator-command") {
        const action = body?.action;
        state.functionCalls.push(action);
        const result = action === "get_current_operator_identity"
          ? identity
          : action === "list_pending_intakes"
          ? { items: [] }
          : action === "count_pending_intakes"
          ? { active_count: 0 }
          : action === "get_application_facets_v2"
          ? { years: [{ year: 2099, count: body?.zone === "ACTIVE" ? 1 : 0 }] }
          : action === "list_applications_v2"
          ? { items: [summary], has_more: false, next_cursor: null }
          : action === "get_application_detail"
          ? detail
          : action === "get_dossier_substance"
          ? substance
          : action === "mark_dossier_seen"
          ? { quote_request_id: quoteRequestId, seen_at: new Date().toISOString() }
          : action === "get_dossier_assignment"
          ? { revision: 0, assignee_operator_id: null, assignee_display_name: null }
          : action === "get_assignment_operator_roster"
          ? []
          : action === "get_dossier_document_manifest"
          ? []
          : action === "list_customer_requests_for_dossier"
          ? { items: [] }
          : action === "get_website_execution_workspace"
          ? projection
          : action === "get_website_requirements_board"
          ? requirements
          : null;
        if (result === null) {
          await route.fulfill({ status: 400, contentType: "application/json", body: JSON.stringify({ ok: false, code: `UNHANDLED_ACTION_${action}` }) });
          return;
        }
        await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ ok: true, result }) });
        return;
      }
      await route.fulfill({ status: 404, contentType: "application/json", body: JSON.stringify({ code: "UNHANDLED_SUPABASE_ROUTE" }) });
    },
  };
}

function attachDiagnostics(context, sink) {
  let pageCount = 0;
  const attach = (page) => {
    pageCount += 1;
    const label = `page-${pageCount}`;
    page.on("pageerror", (error) => {
      sink.pageErrors.push(`${label} ${page.url() || "about:blank"}: ${error.message}`);
    });
    page.on("console", (msg) => {
      if (msg.type() === "error") {
        sink.consoleErrors.push(`${label} ${page.url() || "about:blank"}: ${msg.text()}`);
      }
    });
  };
  context.on("page", attach);
  return attach;
}

async function launchEnvironment() {
  const server = await serveRepo();
  const address = server.address();
  const origin = `http://127.0.0.1:${address.port}`;
  const browser = await chromium.launch({
    headless: true,
    ignoreDefaultArgs: ["--disable-popup-blocking"],
  });
  const context = await browser.newContext({ viewport: { width: 1440, height: 960 } });
  const diagnostics = { consoleErrors: [], pageErrors: [] };
  const attach = attachDiagnostics(context, diagnostics);
  const mock = createSupabaseMock();
  const seededSession = JSON.stringify(sessionPayload());
  await context.addInitScript(({ key, value }) => {
    try {
      if (window.location.protocol === "http:" || window.location.protocol === "https:") {
        window.localStorage.setItem(key, value);
      }
    } catch {}
  }, { key: sessionStorageKey, value: seededSession });
  await context.route(`${supabaseUrl}/**`, (route) => mock.handleRoute(route));
  return {
    origin,
    browser,
    context,
    server,
    mock,
    diagnostics,
    attach,
    async close() {
      const withTimeout = (promise, ms, label) => Promise.race([
        promise,
        new Promise((resolve) => setTimeout(() => {
          console.log(`STEP: ${label} did not settle within ${ms}ms, continuing teardown`);
          resolve();
        }, ms)),
      ]);
      // Pages left open by a failed assertion may still have live app timers
      // (renewal heartbeats, BroadcastChannel listeners). Closing them first,
      // then bounding context/browser teardown, keeps a single failing
      // assertion from stalling the whole suite for minutes.
      await Promise.all(context.pages().map((page) => page.close({ runBeforeUnload: false }).catch(() => {})));
      await withTimeout(context.close(), 10_000, "context.close");
      await withTimeout(browser.close(), 10_000, "browser.close");
      // A keep-alive connection from the browser can otherwise hold the
      // local dev server open indefinitely once the browser itself is gone.
      server.closeAllConnections?.();
      await new Promise((resolve) => server.close(resolve));
    },
  };
}

async function openDossier(page) {
  await page.goto(`${page.context()._options.baseURL || ""}`);
}

async function loadActiveWebsiteDossier(page, origin) {
  await page.goto(`${origin}/operator/dashboard/?module=dossiers`, { waitUntil: "domcontentloaded" });
  await page.locator("#operatorDashboard").waitFor({ state: "visible", timeout: 20_000 });
  const activeZone = page.locator('[data-dossiers-zone="ACTIVE"]');
  await activeZone.click();
  await page.locator('[data-dossiers-select="0"]').waitFor({ state: "visible", timeout: 20_000 });
  await page.locator('[data-dossiers-select="0"]').click();
  await page.locator('[data-dossiers-website-open]').waitFor({ state: "visible", timeout: 20_000 });
}

function diagnosticsSummary(diagnostics) {
  return JSON.stringify(diagnostics, null, 2);
}

test("real dashboard WEBSITE OPENEN opens the real popup and reuses it on second click", { timeout: 180_000 }, async () => {
  const env = await launchEnvironment();
  try {
    const page = await env.context.newPage();
    console.log("STEP: page created");
    env.attach(page);
    await loadActiveWebsiteDossier(page, env.origin);
    console.log("STEP: dossier loaded");

    const popupPromise = page.waitForEvent("popup");
    await page.getByRole("button", { name: "WEBSITE OPENEN" }).click();
    const popup = await popupPromise;
    console.log("STEP: popup opened", popup.url());
    await popup.waitForURL((value) => {
      const url = new URL(value);
      return url.pathname === "/operator/window/" && url.searchParams.get("module") === "dossiers";
    }, { timeout: 20_000 });
    await popup.getByRole("button", { name: "Requirements openen" }).waitFor({ state: "visible", timeout: 20_000 });
    console.log("STEP: child mounted");

    const popupUrl = new URL(popup.url());
    assert.equal(popupUrl.pathname, "/operator/window/");
    assert.equal(popupUrl.searchParams.get("module"), "dossiers");

    const pagesBeforeSecondClick = env.context.pages().length;
    const extraPopupPromise = page.waitForEvent("popup", { timeout: 2_000 }).catch(() => null);
    await page.getByRole("button", { name: "WEBSITE OPENEN" }).click();
    const extraPopup = await extraPopupPromise;
    console.log("STEP: second click awaited", extraPopup ? extraPopup.url() : "reused");
    if (extraPopup) {
      // openOperatorModuleWindow() synchronously reserves a popup slot to
      // consume the click's user-activation gesture before asynchronously
      // discovering the already-open managed child; it then closes this
      // reservation in favour of focusing the existing child. A transient
      // reservation popup is therefore expected here and must close itself
      // quickly rather than becoming a second managed child window.
      await extraPopup.waitForEvent("close", { timeout: 5_000 });
    }
    assert.equal(
      env.context.pages().length,
      pagesBeforeSecondClick,
      "no additional managed child window should remain open after the reservation is reconciled",
    );

    console.log("STEP: closing popup");
    await popup.close().catch(() => {});
    console.log("STEP: popup closed");
    await page.close().catch(() => {});
    assert.deepEqual(env.diagnostics.pageErrors, [], `page errors:\n${diagnosticsSummary(env.diagnostics)}`);
    assert.deepEqual(env.diagnostics.consoleErrors, [], `console errors:\n${diagnosticsSummary(env.diagnostics)}`);
  } finally {
    console.log("STEP: env closing");
    await env.close();
  }
});

test("second dashboard tab never fails silently when WEBSITE OPENEN is unavailable", { timeout: 180_000 }, async () => {
  const env = await launchEnvironment();
  try {
    const firstPage = await env.context.newPage();
    env.attach(firstPage);
    await loadActiveWebsiteDossier(firstPage, env.origin);

    const secondPage = await env.context.newPage();
    env.attach(secondPage);
    await loadActiveWebsiteDossier(secondPage, env.origin);

    const popupAttempt = secondPage.waitForEvent("popup", { timeout: 1_500 }).catch(() => null);
    await secondPage.getByRole("button", { name: "WEBSITE OPENEN" }).click();
    const popup = await popupAttempt;
    assert.equal(popup, null, "second tab should not open a second managed child window");

    const message = secondPage.locator("[data-operator-window-launch-message]");
    await message.waitFor({ state: "visible", timeout: 5_000 });
    await assert.doesNotReject(async () => {
      assert.match(await message.textContent(), /WORKSPACE_INACTIVE/);
    });

    assert.ok(env.mock.state.acquireCalls >= 1);
    assert.deepEqual(env.diagnostics.pageErrors, [], `page errors:\n${diagnosticsSummary(env.diagnostics)}`);
    assert.deepEqual(env.diagnostics.consoleErrors, [], `console errors:\n${diagnosticsSummary(env.diagnostics)}`);
  } finally {
    console.log("STEP: env closing");
    await env.close();
  }
});




