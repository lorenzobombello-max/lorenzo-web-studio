import { projectRequirementsSummary } from "./operator-project-requirements.mjs?v=20260912-dossier-continuity-project-r1";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const WEBSITE_SLOT = /^website-([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/i;
const GITHUB_SEGMENT = /^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,98}[A-Za-z0-9])?$/;
const BRANCH = /^(?:main|develop|work\/[a-z0-9][a-z0-9-]{0,39})$/;
const COMMIT_SHA = /^[0-9a-f]{40}$/i;

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
  const projectId = String(detail?.project?.project_id || "");
  if (!UUID.test(quoteRequestId) || !UUID.test(projectId)) {
    throw new Error("INVALID_WEBSITE_EXECUTION_CONTEXT");
  }
  return Object.freeze({
    action: "get_website_execution_workspace",
    quote_request_id: quoteRequestId,
    project_id: projectId,
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
  if (!UUID.test(String(expected?.quoteRequestId || "")) ||
    !UUID.test(String(expected?.projectId || ""))) {
    throw new Error("INVALID_WEBSITE_EXECUTION_CONTEXT");
  }
  if (value?.project?.project_id !== expected.projectId ||
    value?.start_gate?.project_id !== expected.projectId ||
    value?.start_gate?.quote_request_id !== expected.quoteRequestId) {
    throw new Error("WEBSITE_WORKSPACE_BINDING_MISMATCH");
  }
  if (value.workspace == null) {
    return Object.freeze({
      project: value.project,
      startGate: value.start_gate,
      workspace: null,
    });
  }
  const workspace = value.workspace;
  if (workspace.project_id !== expected.projectId ||
    workspace.quote_request_id !== expected.quoteRequestId ||
    workspace.repository_provider !== "GITHUB" ||
    !GITHUB_SEGMENT.test(String(workspace.repository_owner || "")) ||
    !GITHUB_SEGMENT.test(String(workspace.repository_name || "")) ||
    !BRANCH.test(String(workspace.default_branch || "")) ||
    (workspace.preview_branch != null &&
      !BRANCH.test(String(workspace.preview_branch))) ||
    (workspace.last_commit_sha != null &&
      !COMMIT_SHA.test(String(workspace.last_commit_sha)))) {
    throw new Error("INVALID_WEBSITE_EXECUTION_RESPONSE");
  }
  return Object.freeze({
    project: value.project,
    startGate: value.start_gate,
    workspace: Object.freeze({
      ...workspace,
      preview_url: optionalHttpsUrl(workspace.preview_url),
    }),
  });
}

export function websiteExecutionView(value) {
  const productionUrl = optionalHttpsUrl(value.project?.site?.canonical_url);
  if (!value.workspace) {
    return Object.freeze({
      state: "empty",
      message: "Website workspace niet gekoppeld.",
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
  return projectRequirementsSummary(value, expected);
}