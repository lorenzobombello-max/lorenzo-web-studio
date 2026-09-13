import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { retainWebsiteWorkSnapshot } from "../assets/js/operator-dossiers.mjs";

const quoteRequestA = "a1800000-0000-4000-8000-000000000001";
const quoteRequestB = "a1800000-0000-4000-8000-000000000002";
const websiteWork = Object.freeze({
  state: "NONE",
  quote_request_id: quoteRequestA,
  concept_id: null,
  project_id: null,
  website_work_context_id: null,
  mode: null,
  briefing_status: null,
  commercially_released: false,
  revision: 1,
  permitted_actions: Object.freeze(["CAN_START_WEBSITE_CONCEPT"]),
});
const detail = Object.freeze({
  quote_request_id: quoteRequestA,
  request_kind: "website",
  name: "Snapshot customer",
  website_work: websiteWork,
});
const substance = Object.freeze({
  quote_request_id: quoteRequestA,
  request_kind: "website",
  request: Object.freeze({ reference: "LWS-AAN-2099-0001" }),
  customer: Object.freeze({ name: "Snapshot customer" }),
  intake: Object.freeze({
    intake_id: "a1800000-0000-4000-8000-000000000003",
    structured_answers: Object.freeze({ website_goals: "Launch" }),
  }),
  documents: Object.freeze({ customer_request_count: 0, uploaded_document_count: 0 }),
});
const source = await readFile(
  new URL("../assets/js/operator-dossiers.mjs", import.meta.url),
  "utf8",
);
const childSource = await readFile(
  new URL("../assets/js/operator-website-execution-child.mjs", import.meta.url),
  "utf8",
);

test("same-record refresh retains one complete Website work snapshot", () => {
  const retained = retainWebsiteWorkSnapshot(detail, substance, quoteRequestA);
  assert.deepEqual(retained, { detail, substance });
  assert.equal(retainWebsiteWorkSnapshot(detail, substance, quoteRequestB), null);
  assert.equal(retainWebsiteWorkSnapshot({
    ...detail,
    website_work: { ...websiteWork, unknown: true },
  }, substance, quoteRequestA), null);
  assert.equal(retainWebsiteWorkSnapshot(detail, { ...substance, request_kind: "slimme_documentenflow" }, quoteRequestA), null);
});

test("Website concept start preserves NONE until validated PRE_PROJECT atomically replaces it", () => {
  const body = source.match(/async function startWebsiteConcept\(\) \{([\s\S]*?)\n  \}/)?.[1] || "";
  assert.doesNotMatch(body, /state\.detail\s*=\s*null|website_work\s*=\s*null/);
  assert.match(body, /validateWebsiteConceptStartResponse\([\s\S]*?state\.detail = \{ \.\.\.state\.detail, website_work: websiteWork \};/);
  assert.match(body, /catch \(error\)[\s\S]*message\.textContent/);
});

test("Dossiers retains Website work only for the selected dossier and authorization still locks immediately", () => {
  const selection = source.match(/async function selectDossier\(summary[^]*?\n  \}/)?.[0] || "";
  assert.match(selection, /retainWebsiteWorkSnapshot\(\s*state\.detail,\s*state\.substance,\s*summary\.raw\?\.quote_request_id,?\s*\)/);
  assert.match(selection, /state\.detail = retainedWebsiteWorkSnapshot\?\.detail \|\| null/);
  assert.match(selection, /state\.substance = retainedWebsiteWorkSnapshot\?\.substance \|\| null/);
  assert.doesNotMatch(selection, /state\.detail = null/);
  assert.match(source, /onAuthorizationFailure\(code\) \{[^]*state\.items = \[\];[^]*revalidateSelection\(\);[^]*options\.onAuthorizationFailure\?\.\(code\)/);
  assert.match(source, /function revalidateSelection\(\)[^]*state\.detail = null;[^]*clearDetailSelection\(workspace\)/);
});

test("validated detail and substance replace the retained snapshot in one state commit", () => {
  const selection = source.match(/async function selectDossier\(summary[^]*?\n  \}/)?.[0] || "";
  assert.match(selection, /const detail = detailIdentity\(detailResponse\);\s*const substance = validateDossierSubstance\(substanceResponse, detail\.quote_request_id\);[^]*Object\.assign\(state, \{\s*detail,\s*substance,\s*copySource:/);
});

test("first load may wait while same-record refresh never blanks Website work", () => {
  const selection = source.match(/async function selectDossier\(summary[^]*?\n  \}/)?.[0] || "";
  const beforeRead = selection.split("try {")[0];
  assert.match(beforeRead, /state\.detail = retainedWebsiteWorkSnapshot\?\.detail \|\| null/);
  assert.match(beforeRead, /status\.textContent = "Dossier laden\."/);
  assert.doesNotMatch(beforeRead, /renderWebsiteWork|data-dossiers-website-work-(?:status|badge|briefing|release)|clearDetailSelection/);
});

test("malformed or failed same-record reads retain the mounted snapshot with a separate error", () => {
  const selection = source.match(/async function selectDossier\(summary[^]*?\n  \}/)?.[0] || "";
  const failure = selection.match(/catch \(error\) \{\s*if \(selection === selectDossier\.generation\) \{([^]*?)\n      \}\s*return false;/)?.[1] || "";
  assert.match(failure, /status\.textContent = [^;]*"Dossier kon niet veilig worden geladen\."/);
  assert.doesNotMatch(failure, /state\.(?:detail|substance)\s*=|renderDetail|renderWebsiteWork|clearDetailSelection|\.hidden\s*=/);
});

test("Website child commits one complete context-bound snapshot after every authority validates", () => {
  assert.match(childSource, /let currentSnapshot = null/);
  assert.match(childSource, /projection\.context_revision !== context\.websiteWorkRevision/);
  assert.match(childSource, /const nextSnapshot = Object\.freeze\(\{\s*state: "ready",\s*context,\s*assignment,\s*summary,\s*view:/);
  assert.match(childSource, /currentSnapshot = nextSnapshot;\s*renderChild\(workspace, currentSnapshot\)/);
});

test("Website child retains mounted content on background failure but clears denial and dispose", () => {
  const refresh = childSource.match(/async function refresh\([^]*?\n  \}/)?.[0] || "";
  assert.match(refresh, /if \(denied\) \{[^]*currentSnapshot = null;[^]*renderChild\(workspace, \{\s*state: "denied"/);
  assert.match(refresh, /if \(currentSnapshot\) \{[^]*data-website-message[^]*background[^]*return false/);
  assert.match(childSource, /dispose\(\) \{[^]*currentSnapshot = null;[^]*workspace\.replaceChildren\(\)/);
});
