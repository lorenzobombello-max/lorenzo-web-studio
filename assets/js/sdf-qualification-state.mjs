const EDITABLE_STATUSES = new Set(["invited", "in_progress", "changes_requested"]);
const SUCCESS_STATUSES = new Set(["submitted", "under_review", "qualification_complete", "closed"]);
const VIEWS = new Set(["loading", "unavailable", "workspace", "success"]);

export function sdfQualificationInitialView(status) {
  if (EDITABLE_STATUSES.has(status)) return "workspace";
  if (SUCCESS_STATUSES.has(status)) return "success";
  return "unavailable";
}

export function applySdfQualificationView(view, nodes) {
  if (!VIEWS.has(view)) throw new TypeError("INVALID_SDF_QUALIFICATION_VIEW");
  for (const [name, node] of Object.entries(nodes)) node.hidden = name !== view;
}