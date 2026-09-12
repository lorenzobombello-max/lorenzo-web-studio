import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  validateWebsiteConceptStartResponse,
  validateWebsiteWork,
  websiteConceptStartRequest,
  websiteWorkPresentation,
} from "../assets/js/operator-dossiers.mjs";
import { websiteExecutionSlot } from "../assets/js/operator-website-execution.mjs";

const root = new URL("../", import.meta.url);
const requestId = "c1110001-0000-4000-8000-000000000001";
const conceptId = "c2110001-0000-4000-8000-000000000001";
const projectId = "c3110001-0000-4000-8000-000000000001";
const contextId = "c4110001-0000-4000-8000-000000000001";
const idempotencyKey = "c1a00000-0000-4000-8000-000000000001";

function websiteWork(overrides = {}) {
  return {
    state: "NONE",
    quote_request_id: requestId,
    concept_id: null,
    project_id: null,
    website_work_context_id: null,
    mode: null,
    briefing_status: null,
    commercially_released: false,
    revision: 1,
    permitted_actions: ["CAN_START_WEBSITE_CONCEPT"],
    ...overrides,
  };
}

test("Website work validation is exact and state-bound", () => {
  assert.deepEqual(validateWebsiteWork(websiteWork(), requestId), websiteWork());
  assert.deepEqual(validateWebsiteWork(websiteWork({
    state: "PRE_PROJECT",
    concept_id: conceptId,
    website_work_context_id: contextId,
    mode: "PRE_PROJECT",
    briefing_status: "LIMITED",
    permitted_actions: ["OPEN_WEBSITE"],
  }), requestId).state, "PRE_PROJECT");
  assert.deepEqual(validateWebsiteWork(websiteWork({
    state: "OFFICIAL_PROJECT",
    project_id: projectId,
    website_work_context_id: contextId,
    mode: "OFFICIAL_PROJECT",
    briefing_status: "COMPLETE",
    commercially_released: true,
    permitted_actions: ["OPEN_WEBSITE"],
  }), requestId).state, "OFFICIAL_PROJECT");

  for (const invalid of [
    websiteWork({ state: "UNKNOWN" }),
    websiteWork({ permitted_actions: ["UNKNOWN"] }),
    websiteWork({ permitted_actions: ["CAN_START_WEBSITE_CONCEPT", "CAN_START_WEBSITE_CONCEPT"] }),
    websiteWork({ quote_request_id: projectId }),
    websiteWork({ state: "PRE_PROJECT", concept_id: null, website_work_context_id: contextId, mode: "PRE_PROJECT", briefing_status: "LIMITED", permitted_actions: ["OPEN_WEBSITE"] }),
    websiteWork({ state: "OFFICIAL_PROJECT", project_id: null, website_work_context_id: contextId, mode: "OFFICIAL_PROJECT", briefing_status: "COMPLETE", permitted_actions: ["OPEN_WEBSITE"] }),
    websiteWork({ state: "PRE_PROJECT", concept_id: conceptId, website_work_context_id: contextId, mode: "PRE_PROJECT", briefing_status: "LIMITED", commercially_released: true, permitted_actions: ["OPEN_WEBSITE"] }),
    { ...websiteWork(), role: "owner" },
  ]) assert.throws(() => validateWebsiteWork(invalid, requestId), /INVALID_WEBSITE_WORK/);
});

test("Website work presentation trusts permitted actions instead of browser role", () => {
  const eligible = websiteWorkPresentation(websiteWork(), { role: "operator" });
  assert.deepEqual(eligible, {
    statusLabel: "Nog geen websiteconcept",
    briefingLabel: "Niet beschikbaar",
    releaseLabel: "Niet commercieel vrijgegeven",
    canStart: true,
    canOpen: false,
  });
  assert.equal(websiteWorkPresentation(websiteWork({ permitted_actions: [] }), { role: "owner" }).canStart, false);
  assert.deepEqual(websiteWorkPresentation(websiteWork({
    state: "PRE_PROJECT",
    concept_id: conceptId,
    website_work_context_id: contextId,
    mode: "PRE_PROJECT",
    briefing_status: "COMPLETE",
    permitted_actions: ["OPEN_WEBSITE"],
  }), { role: "read_only" }), {
    statusLabel: "PRE_PROJECT / CONCEPT",
    briefingLabel: "COMPLETE",
    releaseLabel: "Niet commercieel vrijgegeven",
    canStart: false,
    canOpen: true,
  });
});

test("Website concept start request and response remain complete and bounded", () => {
  assert.deepEqual(websiteConceptStartRequest(websiteWork(), idempotencyKey), {
    action: "start_website_concept",
    quote_request_id: requestId,
    expected_website_work_revision: 1,
    idempotency_key: idempotencyKey,
  });
  const response = websiteWork({
    state: "PRE_PROJECT",
    concept_id: conceptId,
    website_work_context_id: contextId,
    mode: "PRE_PROJECT",
    briefing_status: "LIMITED",
    revision: 2,
    permitted_actions: ["OPEN_WEBSITE"],
    replayed: false,
  });
  assert.equal(validateWebsiteConceptStartResponse(response, requestId).state, "PRE_PROJECT");
  assert.throws(() => validateWebsiteConceptStartResponse({ ...response, replayed: "false" }, requestId), /INVALID_WEBSITE_CONCEPT_START_RESPONSE/);
});

test("Dossiers wires exact confirmation, single-flight start, and the existing Website slot", async () => {
  assert.equal(websiteExecutionSlot(requestId), `website-${requestId}`);
  const source = await readFile(new URL("../assets/js/operator-dossiers.mjs", import.meta.url), "utf8");
  assert.match(source, /Voorlopig concept starten — dit is nog geen commerciële bestelling/);
  assert.match(source, /WEBSITE-CONCEPT STARTEN/);
  assert.match(source, /WEBSITE OPENEN/);
  assert.match(source, /data-dossiers-website-concept-cancel/);
  assert.match(source, /state\.websiteConceptBusy/);
  assert.match(source, /websiteConceptStartRequest\([\s\S]*crypto\.randomUUID\(\)/);
  assert.match(source, /validateWebsiteConceptStartResponse/);
  assert.match(source, /websiteExecutionSlot\(websiteWork\.quote_request_id\)/);
  assert.doesNotMatch(source, /projectWorkspaceSlot\(websiteWork\.quote_request_id\)/);
});
