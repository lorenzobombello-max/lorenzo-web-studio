import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";
import test from "node:test";
import { chromium } from "@playwright/test";
import * as projectFilesModule from "../assets/js/operator-website-project-files.mjs";
import {
  createWebsiteProjectFilesController,
  validateWebsiteProjectDirectory,
  validateWebsiteProjectFile,
  websiteProjectDirectoryRequest,
  websiteProjectFileRequest,
} from "../assets/js/operator-website-project-files.mjs";
import { websiteProjectFilesGateway } from "../assets/js/operator-website-execution-child.mjs";

const quoteRequestId = "a2700000-0000-4000-8000-000000000001";
const websiteWorkContextId = "a2700000-0000-4000-8000-000000000002";
const websiteWorkspaceId = "a2700000-0000-4000-8000-000000000003";
const commitA = "a".repeat(40);
const commitB = "b".repeat(40);
const commitC = "c".repeat(40);

function entry(overrides = {}) {
  return {
    entry_type: "ENTRY",
    name: "index.html",
    path: "index.html",
    kind: "FILE",
    size_bytes: 42,
    readability: "READABLE_CANDIDATE",
    selectable: true,
    ...overrides,
  };
}

function blockedEntry(overrides = {}) {
  return {
    entry_type: "BLOCKED_CREDENTIAL",
    name: "Geblokkeerd bestand",
    kind: "UNSUPPORTED",
    readability: "SENSITIVE_BLOCKED",
    selectable: false,
    ...overrides,
  };
}

function directoryFixture(overrides = {}) {
  return {
    contract_version: 1,
    quote_request_id: quoteRequestId,
    website_work_context_id: websiteWorkContextId,
    workspace_state: "REPOSITORY_READY",
    repository: { display_name: "studio/example", binding_revision: 3 },
    snapshot: { commit_sha: commitA, ref_label: "main" },
    directory: "",
    entries: [entry()],
    next_cursor: null,
    ...overrides,
  };
}

function fileFixture(overrides = {}) {
  return {
    contract_version: 1,
    quote_request_id: quoteRequestId,
    website_work_context_id: websiteWorkContextId,
    workspace_state: "REPOSITORY_READY",
    repository: { display_name: "studio/example", binding_revision: 3 },
    snapshot: { commit_sha: commitA, ref_label: "main" },
    file: {
      path: "index.html",
      size_bytes: 42,
      media_type: "text/plain",
      encoding: "utf-8",
      content: "<!doctype html>",
    },
    ...overrides,
  };
}

function controllerHarness(responses, overrides = {}) {
  const requests = [];
  let aal2Calls = 0;
  const controller = createWebsiteProjectFilesController({
    quoteRequestId,
    websiteWorkContextId,
    ownerEligible: true,
    projectFilesRead: true,
    requireAal2: async () => { aal2Calls += 1; },
    gateway: async (request) => {
      requests.push(request);
      const response = responses.shift();
      if (response instanceof Error) throw response;
      return response;
    },
    ...overrides,
  });
  return { controller, requests, aal2Calls: () => aal2Calls };
}

function codedError(code) {
  return Object.assign(new Error(code), { code });
}

async function invokeProjectFilesGatewayError(code) {
  let invokeCalls = 0;
  const client = {
    functions: {
      async invoke() {
        invokeCalls += 1;
        return {
          data: null,
          error: {
            context: new Response(JSON.stringify({ ok: false, code }), {
              status: 503,
              headers: { "content-type": "application/json" },
            }),
          },
        };
      },
    },
  };
  let thrown;
  try {
    await websiteProjectFilesGateway(client, websiteProjectDirectoryRequest({
      quoteRequestId,
      path: "",
      cursor: null,
    }));
  } catch (error) {
    thrown = error;
  }
  assert.equal(invokeCalls, 1);
  assert.equal(thrown?.status, 503);
  return thrown;
}

test("directory request is exact and root includes null cursor", () => {
  assert.deepEqual(websiteProjectDirectoryRequest({
    quoteRequestId,
    path: "",
    cursor: null,
  }), {
    action: "list_website_project_directory",
    quote_request_id: quoteRequestId,
    path: "",
    cursor: null,
  });
  assert.deepEqual(websiteProjectDirectoryRequest({
    quoteRequestId,
    path: "src/components",
    cursor: "opaque-cursor",
  }), {
    action: "list_website_project_directory",
    quote_request_id: quoteRequestId,
    path: "src/components",
    cursor: "opaque-cursor",
  });
  for (const forbidden of [
    "commit", "ref", "branch", "repositoryId", "workspaceId", "contextId",
    "bindingRevision", "token", "providerUrl", "localPath",
  ]) assert.throws(() => websiteProjectDirectoryRequest({
    quoteRequestId,
    path: "",
    cursor: null,
    [forbidden]: "browser-authority",
  }), /INVALID_WEBSITE_PROJECT_DIRECTORY_REQUEST/);
  assert.throws(() => websiteProjectDirectoryRequest({ quoteRequestId, path: "" }),
    /INVALID_WEBSITE_PROJECT_DIRECTORY_REQUEST/);
});

test("file request is exact and authority minimal", () => {
  assert.deepEqual(websiteProjectFileRequest({ quoteRequestId, path: "src/app.js" }), {
    action: "read_website_project_file",
    quote_request_id: quoteRequestId,
    path: "src/app.js",
  });
  for (const forbidden of [
    "commit", "ref", "branch", "repositoryId", "workspaceId", "contextId",
    "bindingRevision", "token", "providerUrl", "localPath",
  ]) assert.throws(() => websiteProjectFileRequest({
    quoteRequestId,
    path: "src/app.js",
    [forbidden]: "browser-authority",
  }), /INVALID_WEBSITE_PROJECT_FILE_REQUEST/);
});

test("directory DTO accepts only the closed metadata contract", () => {
  const result = validateWebsiteProjectDirectory(directoryFixture(), {
    quoteRequestId,
    websiteWorkContextId,
  });
  assert.equal(Object.isFrozen(result), true);
  assert.equal(Object.isFrozen(result.entries), true);
  assert.equal(Object.isFrozen(result.entries[0]), true);
  for (const readability of [
    "DIRECTORY", "READABLE_CANDIDATE", "TOO_LARGE", "SENSITIVE_BLOCKED", "UNSUPPORTED",
  ]) {
    const kind = readability === "DIRECTORY" ? "DIRECTORY"
      : readability === "UNSUPPORTED" ? "UNSUPPORTED" : "FILE";
    const selectable = ["DIRECTORY", "READABLE_CANDIDATE"].includes(readability);
    assert.doesNotThrow(() => validateWebsiteProjectDirectory(directoryFixture({
      entries: [entry({ kind, readability, selectable })],
    }), { quoteRequestId, websiteWorkContextId }));
  }
  for (const readability of ["TEXT", "BINARY_UNSUPPORTED", "UNSUPPORTED_ENCODING"]) {
    assert.throws(() => validateWebsiteProjectDirectory(directoryFixture({
      entries: [entry({ readability })],
    }), { quoteRequestId, websiteWorkContextId }), /INVALID_WEBSITE_PROJECT_DIRECTORY/);
  }
  for (const malformed of [
    { ...directoryFixture(), provider_url: "https://api.github.com/private" },
    { ...directoryFixture(), repository: { ...directoryFixture().repository, external_id: 42 } },
    { ...directoryFixture(), snapshot: { ...directoryFixture().snapshot, token: "secret" } },
    { ...directoryFixture(), entries: [entry({ object_sha: commitA })] },
    { ...directoryFixture(), entries: [entry({ selectable: false })] },
  ]) assert.throws(
    () => validateWebsiteProjectDirectory(malformed, { quoteRequestId, websiteWorkContextId }),
    /INVALID_WEBSITE_PROJECT_DIRECTORY/,
  );
});

test("blocked credential DTO is exact and irreversibly redacted", () => {
  assert.doesNotThrow(() => validateWebsiteProjectDirectory(directoryFixture({
    entries: [blockedEntry()],
  }), { quoteRequestId, websiteWorkContextId }));
  for (const extra of [
    { path: ".env" }, { original_filename: ".npmrc" }, { size_bytes: 12 },
    { object_sha: commitA }, { object_id: "provider-object" },
    { action_target: "read" }, { provider_url: "https://api.github.com/private" },
  ]) assert.throws(() => validateWebsiteProjectDirectory(directoryFixture({
    entries: [blockedEntry(extra)],
  }), { quoteRequestId, websiteWorkContextId }), /INVALID_WEBSITE_PROJECT_DIRECTORY/);
});

test("file DTO accepts only validated UTF-8 text content", () => {
  const result = validateWebsiteProjectFile(fileFixture(), {
    quoteRequestId,
    websiteWorkContextId,
  });
  assert.equal(Object.isFrozen(result), true);
  assert.equal(Object.isFrozen(result.file), true);
  for (const malformed of [
    { ...fileFixture(), provider_url: "https://api.github.com/private" },
    { ...fileFixture(), repository: { ...fileFixture().repository, repository_id: 42 } },
    { ...fileFixture(), snapshot: { ...fileFixture().snapshot, ref: "refs/heads/main" } },
    { ...fileFixture(), file: { ...fileFixture().file, media_type: "text/html" } },
    { ...fileFixture(), file: { ...fileFixture().file, encoding: "base64" } },
    { ...fileFixture(), file: { ...fileFixture().file, local_path: "C:/secret" } },
  ]) assert.throws(
    () => validateWebsiteProjectFile(malformed, { quoteRequestId, websiteWorkContextId }),
    /INVALID_WEBSITE_PROJECT_FILE/,
  );
});

test("project files require explicit owner eligibility and server capability", async () => {
  for (const overrides of [
    { ownerEligible: false, projectFilesRead: true },
    { ownerEligible: true, projectFilesRead: false },
  ]) {
    const harness = controllerHarness([directoryFixture()], overrides);
    await assert.rejects(() => harness.controller.loadDirectory({ path: "", cursor: null }),
      /PROJECT_FILES_ACCESS_DENIED/);
    assert.equal(harness.aal2Calls(), 0);
    assert.deepEqual(harness.requests, []);
    assert.equal(harness.controller.getState().status, "access_denied");
  }
});

test("AAL2 is required immediately before the first user gesture gateway call", async () => {
  const order = [];
  const controller = createWebsiteProjectFilesController({
    quoteRequestId,
    websiteWorkContextId,
    ownerEligible: true,
    projectFilesRead: true,
    requireAal2: async () => order.push("aal2"),
    gateway: async () => {
      order.push("gateway");
      return directoryFixture();
    },
  });
  await controller.loadDirectory({ path: "", cursor: null });
  assert.deepEqual(order, ["aal2", "gateway"]);
});

test("controller models loading, empty and cursor append in module memory", async () => {
  const first = directoryFixture({
    entries: [],
    next_cursor: "next-page",
  });
  const second = directoryFixture({
    entries: [entry({ name: "README.md", path: "README.md" })],
  });
  const harness = controllerHarness([first, second]);
  const pending = harness.controller.loadDirectory({ path: "", cursor: null });
  assert.equal(harness.controller.getState().status, "loading");
  await pending;
  assert.equal(harness.controller.getState().status, "empty");
  await harness.controller.loadDirectory({ path: "", cursor: "next-page" });
  const state = harness.controller.getState();
  assert.equal(state.status, "ready");
  assert.equal(state.directories[""].entries.length, 1);
  assert.equal(state.directories[""].entries[0].path, "README.md");
  assert.equal(state.directories[""].nextCursor, null);
});

test("directory entry behavior is authority inert until an allowed action", () => {
  const harness = controllerHarness([]);
  const cases = [
    [entry({ kind: "DIRECTORY", readability: "DIRECTORY", selectable: true }), true, false],
    [entry(), false, true],
    [entry({ readability: "TOO_LARGE", selectable: false }), false, false],
    [entry({ kind: "UNSUPPORTED", readability: "UNSUPPORTED", selectable: false }), false, false],
    [entry({ readability: "SENSITIVE_BLOCKED", selectable: false }), false, false],
    [blockedEntry(), false, false],
  ];
  for (const [value, expandable, selectableFile] of cases) {
    assert.deepEqual(harness.controller.entryBehavior(value), { expandable, selectableFile });
  }
  harness.controller.setDirectoryExpanded("src", true);
  assert.deepEqual(harness.controller.getState().expandedDirectories, ["src"]);
  harness.controller.setDirectoryExpanded("src", false);
  assert.deepEqual(harness.controller.getState().expandedDirectories, []);
});

test("stable gateway errors map to deterministic in-memory states", async () => {
  const cases = [
    ["OPERATOR_NOT_AUTHORIZED", "access_denied"],
    ["GITHUB_PROVIDER_DISABLED", "provider_unavailable"],
    ["PROJECT_FILES_PROVIDER_UNAVAILABLE", "provider_unavailable"],
    ["PROJECT_FILE_NOT_FOUND", "not_found"],
    ["SENSITIVE_FILE_BLOCKED", "sensitive"],
    ["BINARY_UNSUPPORTED", "binary"],
    ["UNSUPPORTED_ENCODING", "unsupported_encoding"],
    ["FILE_TOO_LARGE", "oversized"],
    ["REPOSITORY_BINDING_STALE", "stale_binding"],
    ["PROJECT_FILES_SNAPSHOT_UNAVAILABLE", "stale_binding"],
    ["SENSITIVE_CLASSIFICATION_UNAVAILABLE", "provider_unavailable"],
    ["UNRECOGNIZED", "failure"],
  ];
  for (const [code, status] of cases) {
    const harness = controllerHarness([codedError(code)]);
    await assert.rejects(() => harness.controller.readFile("index.html"));
    assert.equal(harness.controller.getState().status, status, code);
    assert.equal(harness.controller.getState().currentFile, null);
  }
});

test("Functions HTTP provider-disabled codes retain their public classification", async () => {
  for (const code of [
    "GITHUB_PROVIDER_DISABLED",
    "PROJECT_FILES_PROVIDER_UNAVAILABLE",
  ]) {
    const error = await invokeProjectFilesGatewayError(code);
    assert.equal(error?.code, code);
    const harness = controllerHarness([error]);
    await assert.rejects(() => harness.controller.loadDirectory({ path: "", cursor: null }));
    assert.equal(harness.controller.getState().status, "provider_unavailable");
  }
});

test("unrelated Functions HTTP 503 remains generic and fail closed", async () => {
  const error = await invokeProjectFilesGatewayError("UNRELATED_SERVICE_FAILURE");
  assert.equal(error?.code, "NETWORK_ERROR");
  const harness = controllerHarness([error]);
  await assert.rejects(() => harness.controller.loadDirectory({ path: "", cursor: null }));
  assert.equal(harness.controller.getState().status, "failure");
});

test("tree and file same commit may display", async () => {
  const harness = controllerHarness([directoryFixture(), fileFixture()]);
  await harness.controller.loadDirectory({ path: "", cursor: null });
  await harness.controller.readFile("index.html");
  const state = harness.controller.getState();
  assert.equal(state.currentTreeSnapshot.commit_sha, commitA);
  assert.equal(state.currentFileSnapshot.commit_sha, commitA);
  assert.equal(state.currentFile.file.content, "<!doctype html>");
  assert.equal(state.refreshRootRequired, false);
});

test("new file snapshot blocks stale tree presentation", async () => {
  const harness = controllerHarness([
    directoryFixture(),
    fileFixture({ snapshot: { commit_sha: commitB, ref_label: "main" } }),
    directoryFixture(),
  ]);
  await harness.controller.loadDirectory({ path: "", cursor: null });
  await harness.controller.readFile("index.html");
  const state = harness.controller.getState();
  assert.equal(state.currentTreeSnapshot.commit_sha, commitA);
  assert.equal(state.currentFile, null);
  assert.equal(state.pendingFileSnapshot.commit_sha, commitB);
  assert.equal(state.refreshRootRequired, true);
  assert.equal(state.directories[""].nextCursor, null);
  assert.deepEqual(harness.requests.at(-1), {
    action: "list_website_project_directory",
    quote_request_id: quoteRequestId,
    path: "",
    cursor: null,
  });
});

test("changed snapshot refreshes root before content display", async () => {
  const converged = controllerHarness([
    directoryFixture(),
    fileFixture({ snapshot: { commit_sha: commitB, ref_label: "main" } }),
    directoryFixture({ snapshot: { commit_sha: commitB, ref_label: "main" } }),
  ]);
  await converged.controller.loadDirectory({ path: "", cursor: null });
  await converged.controller.readFile("index.html");
  assert.equal(converged.controller.getState().currentFileSnapshot.commit_sha, commitB);
  assert.equal(converged.controller.getState().currentFile.file.content, "<!doctype html>");
  assert.equal(converged.controller.getState().refreshRootRequired, false);

  const movedAgain = controllerHarness([
    directoryFixture(),
    fileFixture({ snapshot: { commit_sha: commitB, ref_label: "main" } }),
    directoryFixture({ snapshot: { commit_sha: commitC, ref_label: "main" } }),
  ]);
  await movedAgain.controller.loadDirectory({ path: "", cursor: null });
  await movedAgain.controller.readFile("index.html");
  assert.equal(movedAgain.controller.getState().currentTreeSnapshot.commit_sha, commitC);
  assert.equal(movedAgain.controller.getState().currentFile, null);
  assert.equal(movedAgain.controller.getState().pendingFileSnapshot, null);
  assert.equal(movedAgain.controller.getState().refreshRootRequired, false);
  assert.equal(movedAgain.requests.some((request) => "commit" in request), false);
});

test("failed canonical root refresh discards pending and current authority", async () => {
  const harness = controllerHarness([
    directoryFixture({ next_cursor: "opaque-next" }),
    fileFixture({ snapshot: { commit_sha: commitB, ref_label: "main" } }),
    codedError("PROJECT_FILES_PROVIDER_UNAVAILABLE"),
  ]);
  await harness.controller.loadDirectory({ path: "", cursor: null });
  await assert.rejects(() => harness.controller.readFile("index.html"));
  assert.deepEqual(harness.controller.getState(), {
    status: "provider_unavailable",
    directories: {},
    expandedDirectories: [],
    selectedPath: null,
    currentTreeSnapshot: null,
    currentFileSnapshot: null,
    currentFile: null,
    pendingFileSnapshot: null,
    refreshRootRequired: false,
  });
  assert.deepEqual(harness.requests.at(-1), {
    action: "list_website_project_directory",
    quote_request_id: quoteRequestId,
    path: "",
    cursor: null,
  });
  assert.equal(harness.requests.some((request) =>
    ["commit", "commit_sha", "ref", "branch"].some((key) => key in request)), false);
});

test("repository content has no persistence surface", async () => {
  const source = await readFile(new URL(
    "../assets/js/operator-website-project-files.mjs",
    import.meta.url,
  ), "utf8");
  assert.doesNotMatch(source, /localStorage|sessionStorage|indexedDB|caches\.|serviceWorker/i);
  assert.doesNotMatch(source, /location\.|URLSearchParams|history\.|pushState|replaceState/i);
  assert.doesNotMatch(source, /vscode\.dev|github\.dev|vscode:\/\//i);
  assert.match(source, /createElement/);
  assert.match(source, /textContent/);
  assert.doesNotMatch(source, /innerHTML|outerHTML|insertAdjacentHTML|\beval\(|new Function/);
});

test("Task 9 exports one safe internal tree and inert content mount", async () => {
  assert.equal(typeof projectFilesModule.mountWebsiteProjectFilesTree, "function");
  const source = await readFile(new URL(
    "../assets/js/operator-website-project-files.mjs",
    import.meta.url,
  ), "utf8");
  assert.match(source, /website-project-files__tree/);
  assert.match(source, /website-project-files__row/);
  assert.match(source, /website-project-files__status/);
  assert.match(source, /website-project-files__refresh/);
  assert.match(source, /website-project-files__text/);
  assert.match(source, /website-project-files__metadata/);
  assert.match(source, /clearAuthorityState/);
  assert.doesNotMatch(source, /srcdoc|createObjectURL|data:|blob:|download_url|provider_url/i);
  assert.doesNotMatch(source, /window\.open|requestOpen|reserve|register/i);
});

test("controller reset clears stale tree selection and pagination", async () => {
  const harness = controllerHarness([
    directoryFixture({ next_cursor: "opaque-next" }),
  ]);
  await harness.controller.loadDirectory({ path: "", cursor: null });
  harness.controller.setDirectoryExpanded("src", true);
  harness.controller.reset();
  assert.deepEqual(harness.controller.getState(), {
    status: "idle",
    directories: {},
    expandedDirectories: [],
    selectedPath: null,
    currentTreeSnapshot: null,
    currentFileSnapshot: null,
    currentFile: null,
    pendingFileSnapshot: null,
    refreshRootRequired: false,
  });
});

const root = new URL("../", import.meta.url);
const rootPath = decodeURIComponent(root.pathname).replace(/^\/(?:([A-Za-z]:))/, "$1");

const task9Harness = `<!doctype html><html><body>
<section data-website-project-files tabindex="-1"></section>
<script type="module">
window.task9Counters = { script: 0, event: 0, local: 0, session: 0, indexedDb: 0, cache: 0, serviceWorker: 0, history: 0, objectUrl: 0 };
const localSet = localStorage.setItem.bind(localStorage);
localStorage.setItem = (...args) => { window.task9Counters.local += 1; return localSet(...args); };
const sessionSet = sessionStorage.setItem.bind(sessionStorage);
sessionStorage.setItem = (...args) => { window.task9Counters.session += 1; return sessionSet(...args); };
const indexedOpen = indexedDB.open.bind(indexedDB);
indexedDB.open = (...args) => { window.task9Counters.indexedDb += 1; return indexedOpen(...args); };
if (window.caches) { const cacheOpen = caches.open.bind(caches); caches.open = (...args) => { window.task9Counters.cache += 1; return cacheOpen(...args); }; }
const pushState = history.pushState.bind(history);
history.pushState = (...args) => { window.task9Counters.history += 1; return pushState(...args); };
const replaceState = history.replaceState.bind(history);
history.replaceState = (...args) => { window.task9Counters.history += 1; return replaceState(...args); };
URL.createObjectURL = () => { window.task9Counters.objectUrl += 1; throw new Error("OBJECT_URL_FORBIDDEN"); };
window.task9Responses = [];
window.task9Requests = [];
window.task9Aal2 = true;
const { mountWebsiteProjectFilesTree } = await import("/assets/js/operator-website-project-files.mjs");
window.projectFiles = mountWebsiteProjectFilesTree(document.querySelector("[data-website-project-files]"), {
  gateway: async (request) => { window.task9Requests.push(structuredClone(request)); const response = window.task9Responses.shift(); if (response?.error) throw Object.assign(new Error(response.error), { code: response.error }); return response; },
  requireAal2: async () => { if (!window.task9Aal2) throw Object.assign(new Error("OPERATOR_AAL2_REQUIRED"), { code: "OPERATOR_AAL2_REQUIRED" }); },
  ownerEligible: true,
});
window.task9Ready = true;
</script></body></html>`;

function serveTask9Harness() {
  const server = createServer(async (request, response) => {
    if (request.url === "/task9") {
      response.setHeader("content-type", "text/html; charset=utf-8");
      response.end(task9Harness);
      return;
    }
    const relative = normalize(decodeURIComponent(request.url.split("?")[0]))
      .replace(/^[/\\]+/, "");
    if (relative.includes("..")) { response.writeHead(403).end(); return; }
    try {
      const body = await readFile(join(rootPath, relative));
      response.setHeader("content-type", extname(relative) === ".mjs"
        ? "text/javascript" : "text/css");
      response.end(body);
    } catch { response.writeHead(404).end(); }
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

function task9Context(overrides = {}) {
  return {
    quoteRequestId,
    websiteWorkContextId,
    websiteWorkspaceId,
    bindingRevision: 3,
    projectFilesRead: true,
    workspaceState: "REPOSITORY_READY",
    repositoryOperationState: "COMPLETE",
    failureCategory: null,
    recoveryGuidance: null,
    ...overrides,
  };
}

async function queueAndOpenFile(page, fixture = fileFixture(), context = task9Context()) {
  await page.evaluate(({ directory, file, nextContext }) => {
    window.task9Responses.push(directory, file);
    window.projectFiles.updateContext(nextContext);
  }, { directory: directoryFixture(), file: fixture, nextContext: context });
  await page.evaluate(() => window.projectFiles.activate());
  await page.getByRole("treeitem", { name: /Bestand/ }).click();
  await page.waitForSelector(".website-project-files__text:not([hidden])");
}

test("hostile repository text and filenames remain inert with safe metadata and zero persistence", async () => {
  const server = await serveTask9Harness();
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    const address = server.address();
    await page.goto(`http://127.0.0.1:${address.port}/task9`);
    await page.waitForFunction(() => window.task9Ready === true);
    const hostileName = '<img src=x onerror="window.task9Counters.event += 1">.html';
    const hostileContent = [
      '<script>window.task9Counters.script += 1<\/script>',
      '<svg onload="window.task9Counters.event += 1"></svg>',
      '<img src=x onerror="window.task9Counters.event += 1">',
      '# Markdown', '{{ template.expression }}', '</pre></div></section>',
    ].join("\n");
    await page.evaluate(({ directory, file, context }) => {
      window.task9Responses.push(directory, file);
      window.projectFiles.updateContext(context);
    }, {
      directory: directoryFixture({ entries: [entry({ name: hostileName, path: hostileName })] }),
      file: fileFixture({ file: { ...fileFixture().file, path: hostileName, size_bytes: hostileContent.length, content: hostileContent } }),
      context: task9Context(),
    });
    await page.evaluate(() => window.projectFiles.activate());
    await page.getByRole("treeitem", { name: /Bestand/ }).click();
    await page.waitForSelector(".website-project-files__text:not([hidden])");
    assert.equal(await page.locator(".website-project-files__text").textContent(), hostileContent);
    assert.equal(await page.locator(".website-project-files__path").textContent(), hostileName);
    assert.match(await page.locator(".website-project-files__metadata").textContent(), /utf-8/);
    assert.match(await page.locator(".website-project-files__metadata").textContent(), /text\/plain/);
    assert.match(await page.locator(".website-project-files__metadata").textContent(), /a{40}/);
    assert.deepEqual(await page.evaluate(() => window.task9Counters), {
      script: 0, event: 0, local: 0, session: 0, indexedDb: 0, cache: 0,
      serviceWorker: 0, history: 0, objectUrl: 0,
    });
    assert.equal(await page.locator(
      "[data-website-project-files] script, [data-website-project-files] svg, [data-website-project-files] img, [data-website-project-files] iframe",
    ).count(), 0);
    assert.equal(await page.evaluate(() => window.task9Requests.some((request) =>
      ["commit", "commit_sha", "ref", "branch"].some((key) => key in request))), false);
    await page.close();
  } finally {
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});

test("every authority-loss path clears content and disables reads until revalidation", async () => {
  const server = await serveTask9Harness();
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    const address = server.address();
    await page.goto(`http://127.0.0.1:${address.port}/task9`);
    await page.waitForFunction(() => window.task9Ready === true);
    for (const status of ["logout", "authorization_failure", "revoke", "owner_aal2_loss"]) {
      await queueAndOpenFile(page);
      await page.evaluate((reason) => window.projectFiles.clearAuthorityState(reason), status);
      assert.equal(await page.locator(".website-project-files__text:not([hidden])").count(), 0, status);
      const before = await page.evaluate(() => window.task9Requests.length);
      await page.evaluate(() => window.projectFiles.activate());
      assert.equal(await page.evaluate(() => window.task9Requests.length), before, status);
    }
    for (const context of [
      task9Context({ websiteWorkContextId: "a2700000-0000-4000-8000-000000000012" }),
      task9Context({ websiteWorkspaceId: "a2700000-0000-4000-8000-000000000013" }),
      task9Context({ bindingRevision: 4 }),
      task9Context({ projectFilesRead: false, workspaceState: "REPOSITORY_FAILED", repositoryOperationState: "TERMINAL_FAILED", failureCategory: "TERMINAL", recoveryGuidance: "CONTACT_OWNER" }),
    ]) {
      await queueAndOpenFile(page);
      await page.evaluate((nextContext) => window.projectFiles.updateContext(nextContext), context);
      assert.equal(await page.locator(".website-project-files__text:not([hidden])").count(), 0);
    }
    await queueAndOpenFile(page);
    await page.evaluate(() => window.projectFiles.markUnavailable());
    assert.equal(await page.locator(".website-project-files__text:not([hidden])").count(), 0);
    assert.equal(await page.locator(".website-project-files__refresh").isDisabled(), true);
    await queueAndOpenFile(page);
    const beforeAal2Loss = await page.evaluate(() => window.task9Requests.length);
    await page.evaluate(() => { window.task9Aal2 = false; });
    await page.getByRole("treeitem", { name: /Bestand/ }).click();
    await page.waitForFunction(() => document.querySelector(".website-project-files__refresh").disabled);
    assert.equal(await page.locator(".website-project-files__text:not([hidden])").count(), 0);
    assert.equal(await page.evaluate(() => window.task9Requests.length), beforeAal2Loss);
    await page.evaluate(() => window.projectFiles.dispose());
    assert.equal(await page.locator("[data-website-project-files]").textContent(), "");
    await page.close();
  } finally {
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});

test("Website child forwards exact authority identity and clears on auth or refresh loss", async () => {
  const child = await readFile(new URL(
    "../assets/js/operator-website-execution-child.mjs",
    import.meta.url,
  ), "utf8");
  assert.match(child, /websiteWorkspaceId:\s*projection\.workspace\?\.website_workspace_id/);
  assert.match(child, /bindingRevision:\s*projection\.workspace\?\.binding_revision/);
  assert.match(child, /onAuthorizationFailure[^]*projectFiles\.clearAuthorityState/);
  assert.match(child, /background[^]*projectFiles\.markUnavailable/);
  assert.match(child, /projectFiles\.dispose\(\)/);
});

test("Task 8 styles provide bounded focusable responsive tree dimensions", async () => {
  const css = await readFile(new URL("../assets/css/operator-dashboard.css", import.meta.url), "utf8");
  assert.match(css, /\.website-project-files\s*\{[^}]*min-width:0/);
  assert.match(css, /\.website-project-files__tree\s*\{[^}]*overflow:auto/);
  assert.match(css, /\.website-project-files__row[^}]*overflow-wrap:anywhere/);
  assert.match(css, /\.website-project-files[^}]*:focus-visible/);
  assert.match(css, /@media \(max-width:540px\)[^]*\.website-project-files/);
});

test("Task 9 content pane is bounded readable and responsive", async () => {
  const css = await readFile(new URL("../assets/css/operator-dashboard.css", import.meta.url), "utf8");
  assert.match(css, /\.website-project-files__text\s*\{[^}]*white-space:pre-wrap/);
  assert.match(css, /\.website-project-files__text\s*\{[^}]*overflow:auto/);
  assert.match(css, /\.website-project-files__content-pane\s*\{[^}]*min-width:0/);
  assert.match(css, /\.website-project-files__text:focus-visible/);
  assert.match(css, /@media \(max-width:540px\)[^]*\.website-project-files__text/);
});
