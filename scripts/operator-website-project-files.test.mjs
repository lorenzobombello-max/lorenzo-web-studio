import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  createWebsiteProjectFilesController,
  validateWebsiteProjectDirectory,
  validateWebsiteProjectFile,
  websiteProjectDirectoryRequest,
  websiteProjectFileRequest,
} from "../assets/js/operator-website-project-files.mjs";

const quoteRequestId = "a2700000-0000-4000-8000-000000000001";
const websiteWorkContextId = "a2700000-0000-4000-8000-000000000002";
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
    ["PROJECT_FILES_PROVIDER_UNAVAILABLE", "provider_unavailable"],
    ["PROJECT_FILE_NOT_FOUND", "not_found"],
    ["SENSITIVE_FILE_BLOCKED", "sensitive"],
    ["BINARY_UNSUPPORTED", "binary"],
    ["UNSUPPORTED_ENCODING", "unsupported_encoding"],
    ["FILE_TOO_LARGE", "oversized"],
    ["REPOSITORY_BINDING_STALE", "stale_binding"],
    ["UNRECOGNIZED", "failure"],
  ];
  for (const [code, status] of cases) {
    const harness = controllerHarness([codedError(code)]);
    await assert.rejects(() => harness.controller.readFile("index.html"));
    assert.equal(harness.controller.getState().status, status, code);
    assert.equal(harness.controller.getState().currentFile, null);
  }
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

test("repository content has no persistence surface", async () => {
  const source = await readFile(new URL(
    "../assets/js/operator-website-project-files.mjs",
    import.meta.url,
  ), "utf8");
  assert.doesNotMatch(source, /localStorage|sessionStorage|indexedDB|caches\.|serviceWorker/i);
  assert.doesNotMatch(source, /location\.|URLSearchParams|history\.|pushState|replaceState/i);
  assert.doesNotMatch(source, /vscode\.dev|github\.dev|vscode:\/\//i);
  assert.doesNotMatch(source, /document\.|querySelector|createElement|innerHTML/i);
});
