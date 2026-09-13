import { projectRequirementsSummary } from "./operator-project-requirements.mjs?v=20260912-dossier-continuity-project-r1";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const WEBSITE_SLOT = /^website-([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/i;
const GITHUB_SEGMENT = /^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,98}[A-Za-z0-9])?$/;
const BRANCH = /^(?:main|develop|work\/[a-z0-9][a-z0-9-]{0,39})$/;
const COMMIT_SHA = /^[0-9a-f]{40}$/i;
const WEBSITE_WORK_KEYS = [
  "state", "quote_request_id", "concept_id", "project_id",
  "website_work_context_id", "mode", "briefing_status",
  "commercially_released", "revision", "permitted_actions",
];
const ROOT_KEYS = [
  "contract_version", "mode", "quote_request_id", "concept_id", "project_id",
  "website_work_context_id", "context_revision", "briefing_status",
  "commercially_released", "project", "start_gate", "workspace", "requirements",
];
const WORKSPACE_KEYS = [
  "website_workspace_id", "website_work_context_id", "project_id", "quote_request_id",
  "repository_provider", "repository_owner", "repository_name", "default_branch",
  "preview_branch", "preview_url", "last_commit_sha", "last_commit_at",
  "last_build_result", "last_build_at", "binding_revision", "created_at", "updated_at",
];

function exactKeys(value, keys) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === keys.length
    && keys.every((key)=>Object.hasOwn(value, key));
}

function validTimestamp(value) {
  return value === null || (typeof value === "string" && Number.isFinite(Date.parse(value)));
}

function optionalHttpsUrl(value) {
  if (value == null || value === "") return null;
  const url = new URL(String(value));
  if (url.protocol !== "https:" || url.username || url.password) {
    throw new Error("INVALID_WEBSITE_EXECUTION_URL");
  }
  url.hash = "";
  return url.href;
}

export function websiteExecutionSlot(quoteRequestId) {
  if (!UUID.test(String(quoteRequestId || ""))) {
    throw new Error("INVALID_WEBSITE_EXECUTION_SLOT");
  }
  return `website-${String(quoteRequestId).toLowerCase()}`;
}

export function quoteRequestIdFromWebsiteExecutionSlot(slotKey) {
  return WEBSITE_SLOT.exec(String(slotKey || ""))?.[1]?.toLowerCase() || null;
}

export function websiteExecutionRequest(detail) {
  if (detail?.request_kind !== "website") return null;
  const quoteRequestId = String(detail?.quote_request_id || "");
  const work = detail?.website_work;
  if (!UUID.test(quoteRequestId) || !exactKeys(work, WEBSITE_WORK_KEYS)
    || work.quote_request_id !== quoteRequestId
    || !["PRE_PROJECT", "OFFICIAL_PROJECT"].includes(work.state)
    || work.mode !== work.state
    || !UUID.test(String(work.website_work_context_id || ""))
    || !["LIMITED", "COMPLETE"].includes(work.briefing_status)
    || typeof work.commercially_released !== "boolean"
    || !Number.isSafeInteger(work.revision) || work.revision < 1
    || !Array.isArray(work.permitted_actions)
    || new Set(work.permitted_actions).size !== work.permitted_actions.length
    || work.permitted_actions.length !== 1 || work.permitted_actions[0] !== "OPEN_WEBSITE"
    || (work.state === "PRE_PROJECT"
      && (!UUID.test(String(work.concept_id || "")) || work.project_id !== null
        || work.commercially_released))
    || (work.state === "OFFICIAL_PROJECT"
      && (!UUID.test(String(work.project_id || ""))
        || (work.concept_id !== null && !UUID.test(String(work.concept_id || "")))))) {
    throw new Error("INVALID_WEBSITE_EXECUTION_CONTEXT");
  }
  return Object.freeze({
    action: "get_website_execution_workspace",
    quote_request_id: quoteRequestId,
  });
}

export function safeWebsiteExecutionLinks(repositoryOwner, repositoryName) {
  if (!GITHUB_SEGMENT.test(String(repositoryOwner || "")) ||
    !GITHUB_SEGMENT.test(String(repositoryName || ""))) {
    throw new Error("INVALID_WEBSITE_REPOSITORY_REFERENCE");
  }
  const path = `${encodeURIComponent(repositoryOwner)}/${encodeURIComponent(repositoryName)}`;
  return Object.freeze({
    github: `https://github.com/${path}`,
    vscode: `https://vscode.dev/github/${path}`,
  });
}

export function validateWebsiteExecutionWorkspace(value, expected) {
  if (!UUID.test(String(expected?.quoteRequestId || ""))
    || !UUID.test(String(expected?.websiteWorkContextId || ""))
    || !["PRE_PROJECT", "OFFICIAL_PROJECT"].includes(expected?.mode)
    || (expected.mode === "PRE_PROJECT"
      && (!UUID.test(String(expected?.conceptId || "")) || expected?.projectId !== null))
    || (expected.mode === "OFFICIAL_PROJECT"
      && (!UUID.test(String(expected?.projectId || ""))
        || (expected?.conceptId !== null && !UUID.test(String(expected?.conceptId || "")))))) {
    throw new Error("INVALID_WEBSITE_EXECUTION_CONTEXT");
  }
  if (!exactKeys(value, ROOT_KEYS) || value.contract_version !== 2
    || value.mode !== expected.mode
    || value.quote_request_id !== expected.quoteRequestId
    || value.website_work_context_id !== expected.websiteWorkContextId
    || !Number.isSafeInteger(value.context_revision) || value.context_revision < 1
    || !["LIMITED", "COMPLETE"].includes(value.briefing_status)
    || typeof value.commercially_released !== "boolean"
    || !exactKeys(value.requirements, ["state", "message"])) {
    throw new Error("INVALID_WEBSITE_EXECUTION_RESPONSE");
  }
  if (value.concept_id !== expected.conceptId || value.project_id !== expected.projectId) {
    throw new Error("WEBSITE_WORKSPACE_BINDING_MISMATCH");
  }
  if (value.mode === "PRE_PROJECT") {
    if (value.project !== null || value.start_gate !== null || value.commercially_released
      || value.requirements.state !== "NOT_AVAILABLE"
      || value.requirements.message !== "Requirements volgen na intake-sync.") {
      throw new Error("INVALID_WEBSITE_EXECUTION_RESPONSE");
    }
  } else if (!value.project || value.project.project_id !== expected.projectId
    || !value.start_gate || value.start_gate.project_id !== expected.projectId
    || value.start_gate.quote_request_id !== expected.quoteRequestId
    || value.requirements.state !== "PROJECT_BOUND"
    || value.requirements.message !== null) {
    throw new Error("WEBSITE_WORKSPACE_BINDING_MISMATCH");
  }

  let workspace = null;
  if (value.workspace !== null) {
    workspace = value.workspace;
    if (!exactKeys(workspace, WORKSPACE_KEYS)
      || !UUID.test(String(workspace.website_workspace_id || ""))
      || workspace.website_work_context_id !== expected.websiteWorkContextId
      || workspace.project_id !== expected.projectId
      || workspace.quote_request_id !== expected.quoteRequestId
      || workspace.repository_provider !== "GITHUB"
      || !GITHUB_SEGMENT.test(String(workspace.repository_owner || ""))
      || !GITHUB_SEGMENT.test(String(workspace.repository_name || ""))
      || !BRANCH.test(String(workspace.default_branch || ""))
      || (workspace.preview_branch !== null && !BRANCH.test(String(workspace.preview_branch)))
      || (workspace.last_commit_sha !== null && !COMMIT_SHA.test(String(workspace.last_commit_sha)))
      || !validTimestamp(workspace.last_commit_at)
      || ![null, "PASS", "FAIL", "UNKNOWN"].includes(workspace.last_build_result)
      || !validTimestamp(workspace.last_build_at)
      || !Number.isSafeInteger(workspace.binding_revision) || workspace.binding_revision < 1
      || !validTimestamp(workspace.created_at) || workspace.created_at === null
      || !validTimestamp(workspace.updated_at) || workspace.updated_at === null) {
      throw new Error("INVALID_WEBSITE_EXECUTION_RESPONSE");
    }
    workspace = {
      ...workspace,
      preview_url: optionalHttpsUrl(workspace.preview_url),
    };
  }
  return Object.freeze({
    ...structuredClone(value),
    startGate: value.start_gate,
    workspace: workspace === null ? null : Object.freeze(workspace),
  });
}

export function websiteExecutionView(value) {
  const productionUrl = optionalHttpsUrl(value.project?.site?.canonical_url);
  if (!value.workspace) {
    return Object.freeze({
      state: "empty",
      message: "Website workspace niet gekoppeld.",
      modeLabel: value.mode === "PRE_PROJECT" ? "Voorlopig concept" : "Officieel project",
      briefingLabel: value.briefing_status,
      releaseLabel: value.commercially_released
        ? "Commercieel vrijgegeven" : "Niet commercieel vrijgegeven",
      repository: "Repository niet gekoppeld",
      branch: "Niet beschikbaar",
      preview: "Preview nog niet beschikbaar",
      production: productionUrl || "Production URL nog niet beschikbaar",
      commit: "Nog geen commit geregistreerd",
      links: Object.freeze({ github: null, vscode: null, preview: null, production: productionUrl }),
    });
  }
  const workspace = value.workspace;
  const links = safeWebsiteExecutionLinks(
    workspace.repository_owner,
    workspace.repository_name,
  );
  return Object.freeze({
    state: "ready",
    message: "",
    modeLabel: value.mode === "PRE_PROJECT" ? "Voorlopig concept" : "Officieel project",
    briefingLabel: value.briefing_status,
    releaseLabel: value.commercially_released
      ? "Commercieel vrijgegeven" : "Niet commercieel vrijgegeven",
    repository: `${workspace.repository_owner}/${workspace.repository_name}`,
    branch: workspace.preview_branch || workspace.default_branch,
    preview: workspace.preview_url || "Preview nog niet beschikbaar",
    production: productionUrl || "Production URL nog niet beschikbaar",
    commit: workspace.last_commit_sha || "Nog geen commit geregistreerd",
    buildResult: workspace.last_build_result || "UNKNOWN",
    links: Object.freeze({
      ...links,
      preview: workspace.preview_url,
      production: productionUrl,
    }),
  });
}

export function websiteRequirementsSummary(value, expected) {
  if (expected?.mode === "PRE_PROJECT") {
    if (!exactKeys(value, ["state", "message"])
      || value.state !== "NOT_AVAILABLE"
      || value.message !== "Requirements volgen na intake-sync.") {
      throw new Error("INVALID_WEBSITE_EXECUTION_RESPONSE");
    }
    return Object.freeze({ state: "empty", heading: "PROJECTVEREISTEN", message: value.message });
  }
  return projectRequirementsSummary(value, expected);
}