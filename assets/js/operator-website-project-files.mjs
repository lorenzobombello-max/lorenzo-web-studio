const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const COMMIT_SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const DIRECTORY_KEYS = [
  "contract_version", "quote_request_id", "website_work_context_id",
  "workspace_state", "repository", "snapshot", "directory", "entries",
  "next_cursor",
];
const FILE_KEYS = [
  "contract_version", "quote_request_id", "website_work_context_id",
  "workspace_state", "repository", "snapshot", "file",
];
const ENTRY_KEYS = [
  "entry_type", "name", "path", "kind", "size_bytes", "readability",
  "selectable",
];
const BLOCKED_ENTRY_KEYS = [
  "entry_type", "name", "kind", "readability", "selectable",
];
const READABILITIES = new Set([
  "DIRECTORY", "READABLE_CANDIDATE", "TOO_LARGE", "SENSITIVE_BLOCKED",
  "UNSUPPORTED",
]);

function exactKeys(value, keys) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === keys.length
    && keys.every((key) => Object.hasOwn(value, key));
}

function fail(code) {
  throw new Error(code);
}

function freeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const item of Object.values(value)) freeze(item);
  }
  return value;
}

function frozenClone(value) {
  return freeze(structuredClone(value));
}

function normalizedPath(value, allowRoot) {
  if (typeof value !== "string" || value !== value.normalize("NFC")
    || value.includes("\\") || value.includes("%") || value.startsWith("/")
    || value.endsWith("/") || /^[A-Za-z]:/.test(value)
    || /[\u0000-\u001f\u007f]/.test(value)
    || new TextEncoder().encode(value).byteLength > 1024) return null;
  if (value === "") return allowRoot ? "" : null;
  const segments = value.split("/");
  if (segments.length > 64 || segments.some((segment) => segment === ""
    || segment === "." || segment === ".."
    || new TextEncoder().encode(segment).byteLength > 255)) return null;
  return value;
}

function validRepository(value) {
  return exactKeys(value, ["display_name", "binding_revision"])
    && typeof value.display_name === "string" && value.display_name.length > 0
    && Number.isSafeInteger(value.binding_revision) && value.binding_revision >= 1;
}

function validSnapshot(value) {
  return exactKeys(value, ["commit_sha", "ref_label"])
    && COMMIT_SHA.test(String(value.commit_sha || ""))
    && typeof value.ref_label === "string" && value.ref_label.length > 0;
}

function validExpected(expected) {
  return exactKeys(expected, ["quoteRequestId", "websiteWorkContextId"])
    && UUID.test(String(expected.quoteRequestId || ""))
    && UUID.test(String(expected.websiteWorkContextId || ""));
}

function validEntry(value) {
  if (exactKeys(value, BLOCKED_ENTRY_KEYS)) {
    return value.entry_type === "BLOCKED_CREDENTIAL"
      && value.name === "Geblokkeerd bestand"
      && value.kind === "UNSUPPORTED"
      && value.readability === "SENSITIVE_BLOCKED"
      && value.selectable === false;
  }
  if (!exactKeys(value, ENTRY_KEYS) || value.entry_type !== "ENTRY"
    || typeof value.name !== "string" || value.name.length === 0
    || normalizedPath(value.path, false) === null
    || !["DIRECTORY", "FILE", "UNSUPPORTED"].includes(value.kind)
    || value.size_bytes !== null
      && (!Number.isSafeInteger(value.size_bytes) || value.size_bytes < 0)
    || !READABILITIES.has(value.readability)
    || typeof value.selectable !== "boolean") return false;
  if (value.readability === "DIRECTORY") {
    return value.kind === "DIRECTORY" && value.selectable;
  }
  if (value.readability === "READABLE_CANDIDATE") {
    return value.kind === "FILE" && value.selectable;
  }
  if (value.readability === "UNSUPPORTED") {
    return value.kind === "UNSUPPORTED" && !value.selectable;
  }
  return value.kind === "FILE" && !value.selectable;
}

export function websiteProjectDirectoryRequest(value) {
  if (!exactKeys(value, ["quoteRequestId", "path", "cursor"])
    || !UUID.test(String(value.quoteRequestId || ""))
    || normalizedPath(value.path, true) === null
    || value.cursor !== null
      && (typeof value.cursor !== "string" || value.cursor.length === 0)) {
    return fail("INVALID_WEBSITE_PROJECT_DIRECTORY_REQUEST");
  }
  return freeze({
    action: "list_website_project_directory",
    quote_request_id: value.quoteRequestId,
    path: value.path,
    cursor: value.cursor,
  });
}

export function websiteProjectFileRequest(value) {
  if (!exactKeys(value, ["quoteRequestId", "path"])
    || !UUID.test(String(value.quoteRequestId || ""))
    || normalizedPath(value.path, false) === null) {
    return fail("INVALID_WEBSITE_PROJECT_FILE_REQUEST");
  }
  return freeze({
    action: "read_website_project_file",
    quote_request_id: value.quoteRequestId,
    path: value.path,
  });
}

export function validateWebsiteProjectDirectory(value, expected) {
  if (!validExpected(expected) || !exactKeys(value, DIRECTORY_KEYS)
    || value.contract_version !== 1
    || value.quote_request_id !== expected.quoteRequestId
    || value.website_work_context_id !== expected.websiteWorkContextId
    || value.workspace_state !== "REPOSITORY_READY"
    || !validRepository(value.repository) || !validSnapshot(value.snapshot)
    || normalizedPath(value.directory, true) === null
    || !Array.isArray(value.entries) || !value.entries.every(validEntry)
    || value.next_cursor !== null
      && (typeof value.next_cursor !== "string" || value.next_cursor.length === 0)) {
    return fail("INVALID_WEBSITE_PROJECT_DIRECTORY");
  }
  return frozenClone(value);
}

export function validateWebsiteProjectFile(value, expected) {
  if (!validExpected(expected) || !exactKeys(value, FILE_KEYS)
    || value.contract_version !== 1
    || value.quote_request_id !== expected.quoteRequestId
    || value.website_work_context_id !== expected.websiteWorkContextId
    || value.workspace_state !== "REPOSITORY_READY"
    || !validRepository(value.repository) || !validSnapshot(value.snapshot)
    || !exactKeys(value.file, [
      "path", "size_bytes", "media_type", "encoding", "content",
    ])
    || normalizedPath(value.file.path, false) === null
    || !Number.isSafeInteger(value.file.size_bytes) || value.file.size_bytes < 0
    || value.file.media_type !== "text/plain" || value.file.encoding !== "utf-8"
    || typeof value.file.content !== "string") {
    return fail("INVALID_WEBSITE_PROJECT_FILE");
  }
  return frozenClone(value);
}

function errorCode(error) {
  if (error && typeof error === "object" && typeof error.code === "string") {
    return error.code;
  }
  return error instanceof Error ? error.message : "PROJECT_FILES_FAILURE";
}

function statusForError(code) {
  if ([
    "PROJECT_FILES_ACCESS_DENIED", "OPERATOR_NOT_AUTHORIZED",
    "WEBSITE_REPOSITORY_OWNER_REQUIRED",
  ].includes(code)) {
    return "access_denied";
  }
  if ([
    "PROJECT_FILES_PROVIDER_UNAVAILABLE", "PROJECT_FILES_PROVIDER_TIMEOUT",
    "PROJECT_FILES_PROVIDER_THROTTLED", "PROJECT_FILES_PROVIDER_RESPONSE_INVALID",
    "SENSITIVE_CLASSIFICATION_UNAVAILABLE",
  ].includes(code)) return "provider_unavailable";
  if ([
    "PROJECT_FILE_NOT_FOUND", "PROJECT_DIRECTORY_NOT_FOUND",
    "PROJECT_PATH_KIND_MISMATCH",
  ].includes(code)) return "not_found";
  if (code === "SENSITIVE_FILE_BLOCKED") return "sensitive";
  if (code === "BINARY_UNSUPPORTED") return "binary";
  if (code === "UNSUPPORTED_ENCODING") return "unsupported_encoding";
  if (code === "FILE_TOO_LARGE") return "oversized";
  if ([
    "REPOSITORY_BINDING_STALE", "PROJECT_FILES_CURSOR_INVALID",
    "PROJECT_FILES_SNAPSHOT_UNAVAILABLE", "REPOSITORY_REF_MISMATCH",
  ].includes(code)) return "stale_binding";
  return "failure";
}

function initialState(available) {
  return freeze({
    status: available ? "idle" : "access_denied",
    directories: {},
    expandedDirectories: [],
    selectedPath: null,
    currentTreeSnapshot: null,
    currentFileSnapshot: null,
    currentFile: null,
    pendingFileSnapshot: null,
    refreshRootRequired: false,
  });
}

export function createWebsiteProjectFilesController(options) {
  if (!exactKeys(options, [
    "quoteRequestId", "websiteWorkContextId", "ownerEligible",
    "projectFilesRead", "requireAal2", "gateway",
  ]) || !UUID.test(String(options.quoteRequestId || ""))
    || !UUID.test(String(options.websiteWorkContextId || ""))
    || typeof options.ownerEligible !== "boolean"
    || typeof options.projectFilesRead !== "boolean"
    || typeof options.requireAal2 !== "function"
    || typeof options.gateway !== "function") {
    return fail("INVALID_WEBSITE_PROJECT_FILES_CONTROLLER");
  }

  const available = options.ownerEligible && options.projectFilesRead;
  const expected = {
    quoteRequestId: options.quoteRequestId,
    websiteWorkContextId: options.websiteWorkContextId,
  };
  let state = initialState(available);

  function update(changes) {
    state = freeze({ ...state, ...changes });
  }

  function clearPagination() {
    const directories = Object.fromEntries(Object.entries(state.directories)
      .map(([path, directory]) => [path, { ...directory, nextCursor: null }]));
    update({ directories: freeze(directories) });
  }

  function deny() {
    state = initialState(false);
    return fail("PROJECT_FILES_ACCESS_DENIED");
  }

  function handleError(error) {
    update({
      status: statusForError(errorCode(error)),
      currentFile: null,
      currentFileSnapshot: null,
    });
    throw error;
  }

  async function authorizeGesture() {
    if (!available) return deny();
    await options.requireAal2();
  }

  async function loadDirectory(input, userGesture = true) {
    let request;
    try {
      request = websiteProjectDirectoryRequest({
        quoteRequestId: options.quoteRequestId,
        path: input?.path,
        cursor: input?.cursor,
      });
      if (!available) return deny();
      update({ status: "loading" });
      if (userGesture) await authorizeGesture();
      const result = validateWebsiteProjectDirectory(
        await options.gateway(request), expected,
      );
      const priorTreeCommit = state.currentTreeSnapshot?.commit_sha || null;
      const previous = state.directories[result.directory];
      const append = input.cursor !== null && previous
        && previous.snapshot.commit_sha === result.snapshot.commit_sha;
      let directories = append ? {
        ...state.directories,
        [result.directory]: freeze({
          entries: freeze([...previous.entries, ...result.entries]),
          nextCursor: result.next_cursor,
          snapshot: result.snapshot,
        }),
      } : {
        ...state.directories,
        [result.directory]: freeze({
          entries: result.entries,
          nextCursor: result.next_cursor,
          snapshot: result.snapshot,
        }),
      };
      if (result.directory === "" && priorTreeCommit
        && priorTreeCommit !== result.snapshot.commit_sha) {
        directories = { "": directories[""] };
      }

      let currentFile = state.currentFile;
      let currentFileSnapshot = state.currentFileSnapshot;
      let pendingFileSnapshot = state.pendingFileSnapshot;
      let refreshRootRequired = state.refreshRootRequired;
      if (result.directory === "" && pendingFileSnapshot) {
        if (result.snapshot.commit_sha === pendingFileSnapshot.commit_sha) {
          currentFile = pendingFileSnapshot.result;
          currentFileSnapshot = pendingFileSnapshot;
          pendingFileSnapshot = null;
          refreshRootRequired = false;
        } else if (priorTreeCommit !== result.snapshot.commit_sha) {
          currentFile = null;
          currentFileSnapshot = null;
          pendingFileSnapshot = null;
          refreshRootRequired = false;
        }
      }
      const entries = directories[result.directory].entries;
      update({
        status: entries.length === 0 ? "empty" : "ready",
        directories: freeze(directories),
        currentTreeSnapshot: result.snapshot,
        currentFile,
        currentFileSnapshot,
        pendingFileSnapshot,
        refreshRootRequired,
      });
      return result;
    } catch (error) {
      return handleError(error);
    }
  }

  async function readFile(path) {
    try {
      const request = websiteProjectFileRequest({
        quoteRequestId: options.quoteRequestId,
        path,
      });
      if (!available) return deny();
      update({ status: "loading", selectedPath: path });
      await authorizeGesture();
      const result = validateWebsiteProjectFile(await options.gateway(request), expected);
      if (state.currentTreeSnapshot?.commit_sha === result.snapshot.commit_sha) {
        update({
          status: "ready",
          currentFile: result,
          currentFileSnapshot: result.snapshot,
          pendingFileSnapshot: null,
          refreshRootRequired: false,
        });
        return result;
      }
      clearPagination();
      update({
        currentFile: null,
        currentFileSnapshot: null,
        pendingFileSnapshot: freeze({ ...result.snapshot, result }),
        refreshRootRequired: true,
      });
      await loadDirectory({ path: "", cursor: null }, false);
      return result;
    } catch (error) {
      return handleError(error);
    }
  }

  return freeze({
    getState: () => state,
    loadDirectory,
    readFile,
    reset() {
      state = initialState(available);
    },
    setDirectoryExpanded(path, expanded) {
      if (normalizedPath(path, false) === null || typeof expanded !== "boolean") {
        return fail("INVALID_WEBSITE_PROJECT_DIRECTORY_STATE");
      }
      const paths = new Set(state.expandedDirectories);
      if (expanded) paths.add(path); else paths.delete(path);
      update({ expandedDirectories: freeze([...paths].sort()) });
    },
    entryBehavior(value) {
      if (!validEntry(value)) return fail("INVALID_WEBSITE_PROJECT_DIRECTORY");
      return freeze({
        expandable: value.entry_type === "ENTRY"
          && value.readability === "DIRECTORY" && value.selectable,
        selectableFile: value.entry_type === "ENTRY"
          && value.readability === "READABLE_CANDIDATE" && value.selectable,
      });
    },
  });
}

const TREE_CONTEXT_KEYS = [
  "quoteRequestId", "websiteWorkContextId", "projectFilesRead",
  "workspaceState", "repositoryOperationState", "failureCategory",
  "recoveryGuidance",
];

function treeContextValid(value) {
  return exactKeys(value, TREE_CONTEXT_KEYS)
    && UUID.test(String(value.quoteRequestId || ""))
    && UUID.test(String(value.websiteWorkContextId || ""))
    && typeof value.projectFilesRead === "boolean"
    && [
      null, "PENDING_REPOSITORY", "REPOSITORY_PROVISIONING",
      "REPOSITORY_READY", "REPOSITORY_FAILED", "READY",
    ].includes(value.workspaceState)
    && [
      null, "CLAIMED", "CREATING", "EXTERNAL_CREATED", "VERIFYING",
      "RETRYABLE_FAILED", "RETRY_SCHEDULED", "BLOCKED", "QUARANTINED",
      "TERMINAL_FAILED", "COMPLETE",
    ].includes(value.repositoryOperationState)
    && [null, "RETRYABLE", "BLOCKED", "QUARANTINED", "TERMINAL"]
      .includes(value.failureCategory)
    && [
      null, "WAIT", "REFRESH_LATER", "CONTACT_OWNER",
      "RECONCILIATION_REQUIRED",
    ].includes(value.recoveryGuidance);
}

function lifecycleMessage(context, ownerEligible) {
  if (!ownerEligible) return "Geen toegang tot Projectbestanden.";
  if (!context) return "Technische werkruimte nog niet beschikbaar.";
  if (context.repositoryOperationState === "QUARANTINED") {
    return "Repository-identiteit vereist reconciliatie.";
  }
  if (context.repositoryOperationState === "BLOCKED") {
    return "Repositorytoegang is geblokkeerd.";
  }
  if (context.workspaceState === "PENDING_REPOSITORY") {
    return "Repository wordt voorbereid.";
  }
  if (context.workspaceState === "REPOSITORY_PROVISIONING") {
    return "Repository wordt gekoppeld.";
  }
  if (context.workspaceState === "REPOSITORY_FAILED") {
    return "Repository is niet beschikbaar. Neem contact op met de eigenaar.";
  }
  if (context.workspaceState === "READY") {
    return "Repositorybinding moet worden geverifieerd.";
  }
  if (!context.projectFilesRead) return "Projectbestanden zijn niet beschikbaar.";
  return "Selecteer een map of bestand.";
}

function element(documentTarget, tagName, className, text = null) {
  const node = documentTarget.createElement(tagName);
  if (className) node.className = className;
  if (text !== null) node.textContent = text;
  return node;
}

export function mountWebsiteProjectFilesTree(host, options) {
  if (!host?.ownerDocument || !exactKeys(options, [
    "gateway", "requireAal2", "ownerEligible",
  ]) || typeof options.gateway !== "function"
    || typeof options.requireAal2 !== "function"
    || typeof options.ownerEligible !== "boolean") {
    return fail("INVALID_WEBSITE_PROJECT_FILES_TREE");
  }

  const documentTarget = host.ownerDocument;
  const heading = element(documentTarget, "div", "website-project-files__heading");
  const headingText = element(documentTarget, "div", null);
  headingText.append(
    element(documentTarget, "p", "eyebrow", "Repository"),
    element(documentTarget, "h2", null, "Projectbestanden"),
  );
  const refreshButton = element(
    documentTarget, "button", "secondary-action website-project-files__refresh",
    "Vernieuwen",
  );
  refreshButton.type = "button";
  heading.append(headingText, refreshButton);
  const status = element(documentTarget, "p", "website-project-files__status");
  status.setAttribute("role", "status");
  status.setAttribute("aria-live", "polite");
  const empty = element(
    documentTarget, "p", "website-project-files__empty", "Geen bestanden in deze map.",
  );
  empty.hidden = true;
  const tree = element(documentTarget, "div", "website-project-files__tree");
  tree.setAttribute("role", "tree");
  tree.setAttribute("aria-label", "Projectbestanden");
  host.replaceChildren(heading, status, empty, tree);

  let context = null;
  let controller = null;
  let busy = false;
  let disposed = false;

  function available() {
    return options.ownerEligible && context?.projectFilesRead === true;
  }

  function createController() {
    if (!context) return null;
    return createWebsiteProjectFilesController({
      quoteRequestId: context.quoteRequestId,
      websiteWorkContextId: context.websiteWorkContextId,
      ownerEligible: options.ownerEligible,
      projectFilesRead: context.projectFilesRead,
      requireAal2: options.requireAal2,
      gateway: options.gateway,
    });
  }

  function appendDirectory(parent, path, depth) {
    const directory = controller?.getState().directories[path];
    if (!directory) return;
    const expanded = new Set(controller.getState().expandedDirectories);
    for (const entry of directory.entries) {
      const behavior = controller.entryBehavior(entry);
      if (behavior.expandable) {
        const button = element(
          documentTarget, "button",
          "website-project-files__row website-project-files__row--directory",
          entry.name,
        );
        button.type = "button";
        button.disabled = busy;
        button.setAttribute("role", "treeitem");
        button.setAttribute("aria-level", String(depth + 1));
        button.setAttribute("aria-expanded", String(expanded.has(entry.path)));
        button.setAttribute("aria-label", `Map ${entry.name} ${
          expanded.has(entry.path) ? "inklappen" : "uitklappen"
        }`);
        button.addEventListener("click", () => {
          if (busy || disposed) return;
          if (expanded.has(entry.path)) {
            controller.setDirectoryExpanded(entry.path, false);
            render();
            return;
          }
          controller.setDirectoryExpanded(entry.path, true);
          if (controller.getState().directories[entry.path]) render();
          else void perform(() => controller.loadDirectory({
            path: entry.path,
            cursor: null,
          }));
        });
        parent.append(button);
        if (expanded.has(entry.path)) {
          const group = element(documentTarget, "div", "website-project-files__group");
          group.setAttribute("role", "group");
          appendDirectory(group, entry.path, depth + 1);
          parent.append(group);
        }
      } else if (behavior.selectableFile) {
        const button = element(
          documentTarget, "button",
          "website-project-files__row website-project-files__row--file",
          entry.name,
        );
        button.type = "button";
        button.disabled = busy;
        button.setAttribute("role", "treeitem");
        button.setAttribute("aria-level", String(depth + 1));
        button.setAttribute("aria-label", `Bestand ${entry.name} selecteren`);
        button.addEventListener("click", () => {
          if (!busy && !disposed) void perform(() => controller.readFile(entry.path));
        });
        parent.append(button);
      } else {
        const row = element(
          documentTarget, "div",
          "website-project-files__row website-project-files__row--inert",
          entry.name,
        );
        row.setAttribute("role", "treeitem");
        row.setAttribute("aria-level", String(depth + 1));
        row.setAttribute("aria-disabled", "true");
        parent.append(row);
      }
    }
    if (directory.nextCursor) {
      const more = element(
        documentTarget, "button", "website-project-files__more", "Meer laden",
      );
      more.type = "button";
      more.disabled = busy;
      more.addEventListener("click", () => {
        if (!busy && !disposed) void perform(() => controller.loadDirectory({
          path,
          cursor: directory.nextCursor,
        }));
      });
      parent.append(more);
    }
  }

  function render() {
    if (disposed) return;
    const state = controller?.getState();
    refreshButton.disabled = busy || !available();
    status.textContent = busy ? "Projectbestanden laden..."
      : state?.status === "provider_unavailable" ? "Provider tijdelijk niet beschikbaar."
      : state?.status === "not_found" ? "Map of bestand niet gevonden."
      : state?.status === "stale_binding" ? "Repositorybinding is gewijzigd. Vernieuw de lijst."
      : state?.status === "failure" ? "Projectbestanden konden niet veilig worden geladen."
      : lifecycleMessage(context, options.ownerEligible);
    tree.replaceChildren();
    appendDirectory(tree, "", 0);
    empty.hidden = state?.status !== "empty";
  }

  async function perform(operation) {
    if (busy || disposed || !available() || !controller) return false;
    busy = true;
    const pending = operation();
    render();
    try {
      await pending;
      return true;
    } catch {
      return false;
    } finally {
      busy = false;
      render();
    }
  }

  async function refresh() {
    if (!controller || !available()) return false;
    controller.reset();
    render();
    return perform(() => controller.loadDirectory({ path: "", cursor: null }));
  }

  refreshButton.addEventListener("click", () => void refresh());
  render();

  return freeze({
    activate() {
      if (disposed) return Promise.resolve(false);
      host.focus({ preventScroll: true });
      if (!available() || busy) {
        render();
        return Promise.resolve(false);
      }
      if (controller.getState().directories[""]) {
        render();
        return Promise.resolve(true);
      }
      return perform(() => controller.loadDirectory({ path: "", cursor: null }));
    },
    updateContext(value) {
      if (value !== null && !treeContextValid(value)) {
        return fail("INVALID_WEBSITE_PROJECT_FILES_TREE_CONTEXT");
      }
      context = value === null ? null : frozenClone(value);
      controller = createController();
      busy = false;
      render();
    },
    refresh,
    dispose() {
      if (disposed) return;
      disposed = true;
      controller = null;
      host.replaceChildren();
    },
  });
}
