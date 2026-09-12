import assert from "node:assert/strict";
import test from "node:test";

import {
  REQUIRED_RELEASE_CHECKS,
  SENTINEL_REFERENCE,
  compareDossierCounts,
  evaluateDossierProjections,
  evaluateReleaseGate,
  inspectDossierContinuitySourceContracts,
  runProductionReadOnlySmoke,
  validateActiveEnvelope,
  validatePendingEnvelope,
  validateUiContinuity,
} from "./dossier-continuity-regression-gate.mjs";

const pending = Object.freeze({
  quote_request_id: "d1000000-0000-4000-8000-000000000001",
  reference: "#A1000001",
  dossier_state: "ACTIVE",
  retention_state: "ACTIVE",
  projection: "PENDING",
  assigned_operator_id: null,
});
const active = Object.freeze({
  quote_request_id: "d1000000-0000-4000-8000-000000000002",
  reference: SENTINEL_REFERENCE,
  dossier_state: "ACTIVE",
  retention_state: "ACTIVE",
  projection: "ACTIVE",
  assigned_operator_id: "d2000000-0000-4000-8000-000000000001",
});
const trashed = Object.freeze({
  quote_request_id: "d1000000-0000-4000-8000-000000000003",
  reference: "LWS-AAN-2099-0003",
  dossier_state: "TRASHED",
  retention_state: "ACTIVE",
  projection: "TRASHED",
  assigned_operator_id: "d2000000-0000-4000-8000-000000000001",
});

test("only the approved synthetic sentinel is fixed", () => {
  assert.equal(SENTINEL_REFERENCE, "LWS-AAN-2026-0006");
  assert.doesNotMatch(JSON.stringify([pending, active, trashed]), /Nathalie|Yuna/i);
});

test("pending active trash and personal queue projections remain separate", () => {
  const result = evaluateDossierProjections(
    [pending, active, trashed],
    active.assigned_operator_id,
  );
  assert.deepEqual(result.pending.map(({ reference }) => reference), [pending.reference]);
  assert.deepEqual(result.active.map(({ reference }) => reference), [active.reference]);
  assert.deepEqual(result.trash.map(({ reference }) => reference), [trashed.reference]);
  assert.deepEqual(result.personalQueue.map(({ reference }) => reference), [active.reference]);
  assert.equal(result.pending.some(({ reference }) => reference === active.reference), false);
  assert.equal(result.active.some(({ reference }) => reference === pending.reference), false);
});

test("list and detail remain assignment-independent while personal queue is assigned", () => {
  const otherOperator = "d2000000-0000-4000-8000-000000000099";
  const result = evaluateDossierProjections([active], otherOperator);
  assert.deepEqual(result.active, [active]);
  assert.equal(result.detail(active.quote_request_id)?.reference, SENTINEL_REFERENCE);
  assert.deepEqual(result.personalQueue, []);
});

test("invalid and inactive operators fail closed while active owner and admin can read", () => {
  for (const role of ["owner", "admin"]) {
    assert.doesNotThrow(() => evaluateDossierProjections([active], null, {
      role,
      status: "ACTIVE",
      authUidMatches: true,
    }));
  }
  for (const operator of [
    null,
    { role: "owner", status: "DISABLED", authUidMatches: true },
    { role: "admin", status: "INACTIVE", authUidMatches: true },
    { role: "owner", status: "ACTIVE", authUidMatches: false },
  ]) {
    assert.throws(
      () => evaluateDossierProjections([active], null, operator),
      /OPERATOR_READ_DENIED/,
    );
  }
});

test("pending DTO accepts seen-state fields and rejects contract drift", () => {
  const item = {
    quote_request_id: pending.quote_request_id,
    dossier_state: "ACTIVE",
    dossier_revision: 4,
    seen_at: null,
  };
  assert.deepEqual(validatePendingEnvelope({ items: [item] }).items, [item]);
  assert.throws(() => validatePendingEnvelope({ items: [{ ...item, dossier_revision: undefined }] }), /PENDING_DTO_CONTRACT/);
  assert.throws(() => validatePendingEnvelope({ items: [{ ...item, leak: true }] }), /PENDING_DTO_CONTRACT/);
});

test("active envelope requires items next_cursor and has_more", () => {
  const envelope = { items: [active], next_cursor: null, has_more: false };
  assert.deepEqual(validateActiveEnvelope(envelope), envelope);
  for (const missing of ["items", "next_cursor", "has_more"]) {
    const changed = { ...envelope };
    delete changed[missing];
    assert.throws(() => validateActiveEnvelope(changed), /ACTIVE_ENVELOPE_CONTRACT/);
  }
});

test("UI continuity distinguishes failure from successful empty and populated results", () => {
  assert.deepEqual(validateUiContinuity({ ok: false, items: [] }), {
    state: "failure",
    showEmpty: false,
    showLoadError: true,
  });
  assert.deepEqual(validateUiContinuity({ ok: true, items: [] }), {
    state: "empty",
    showEmpty: true,
    showLoadError: false,
  });
  assert.deepEqual(validateUiContinuity({ ok: true, items: [active] }), {
    state: "populated",
    showEmpty: false,
    showLoadError: false,
  });
});

test("frontend or Edge releases preserve anonymized dossier counts", () => {
  const before = { TOTAL_RAW: 3, TOTAL_PENDING: 1, TOTAL_ACTIVE: 1, TOTAL_TRASHED: 1 };
  assert.deepEqual(compareDossierCounts(before, { ...before }), { pass: true, changed: [] });
  assert.deepEqual(compareDossierCounts(before, { ...before, TOTAL_ACTIVE: 0 }), {
    pass: false,
    changed: ["TOTAL_ACTIVE"],
  });
  assert.throws(() => compareDossierCounts(before, { ...before, customer: "forbidden" }), /COUNT_CONTRACT/);
});

test("hard gate denies production when any mandatory check fails", () => {
  const passing = Object.fromEntries(REQUIRED_RELEASE_CHECKS.map((name) => [name, true]));
  assert.deepEqual(evaluateReleaseGate(passing), {
    releaseGate: "PASS",
    productionReleaseAllowed: "JA",
    failures: [],
  });
  assert.deepEqual(evaluateReleaseGate({ ...passing, DETAIL_RPC: false }), {
    releaseGate: "FAIL",
    productionReleaseAllowed: "NEE",
    failures: ["DETAIL_RPC"],
  });
});

test("repository sources preserve JWT CORS authority response and UI contracts", async () => {
  const result = await inspectDossierContinuitySourceContracts(new URL("../", import.meta.url));
  assert.equal(result.pass, true, JSON.stringify(result.failures));
  assert.deepEqual(result.failures, []);
  assert.ok(REQUIRED_RELEASE_CHECKS.every((name) => result.checks[name] === true));
});

test("production smoke is read-only and proves CORS sentinel list detail and counts", async () => {
  const requests = [];
  const jsonResponse = (result) => new Response(JSON.stringify({ ok: true, result }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
  const fetchImpl = async (_url, options) => {
    requests.push(options);
    if (options.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "access-control-allow-origin": "https://lorenzowebsolutions.be",
          "access-control-allow-headers": "apikey,authorization,content-type,x-client-info",
        },
      });
    }
    const body = JSON.parse(options.body);
    if (body.action === "list_pending_intakes") {
      return jsonResponse({ items: [{ quote_request_id: pending.quote_request_id }] });
    }
    if (body.action === "get_dossier_substance") {
      return jsonResponse({ quote_request_id: active.quote_request_id });
    }
    if (body.action === "list_applications_v2") {
      const items = body.zone === "ACTIVE"
        ? [{ quote_request_id: active.quote_request_id, application_reference: SENTINEL_REFERENCE }]
        : body.zone === "TRASHED"
        ? [{ quote_request_id: trashed.quote_request_id, application_reference: trashed.reference }]
        : [];
      return jsonResponse({ items, next_cursor: null, has_more: false });
    }
    throw new Error("UNEXPECTED_SMOKE_REQUEST");
  };
  const result = await runProductionReadOnlySmoke({
    apiKey: "synthetic-public-key",
    jwt: "synthetic-caller-jwt",
    fetchImpl,
  });
  assert.deepEqual(result.counts, {
    TOTAL_RAW: 3,
    TOTAL_PENDING: 1,
    TOTAL_ACTIVE: 1,
    TOTAL_TRASHED: 1,
  });
  assert.deepEqual(result.sentinel, {
    rawPresent: true,
    listPresent: true,
    detailPresent: true,
    expectedZone: "ACTIVE",
    notTrashed: true,
  });
  assert.ok(requests.every(({ method }) => ["OPTIONS", "POST"].includes(method)));
  assert.ok(requests.filter(({ method }) => method === "POST").every(({ headers }) =>
    headers.Authorization === "Bearer synthetic-caller-jwt" &&
    headers.apikey === "synthetic-public-key" &&
    headers["x-client-info"] === "lws-dossier-continuity-gate/1.0"
  ));
  const allowedActions = new Set([
    "list_pending_intakes",
    "list_applications_v2",
    "get_dossier_substance",
  ]);
  assert.ok(requests.filter(({ body }) => body).every(({ body }) =>
    allowedActions.has(JSON.parse(body).action)
  ));
});

test("production smoke fails closed on CORS or detail regressions", async () => {
  const jsonResponse = (result, status = 200) => new Response(JSON.stringify({ ok: status === 200, result }), {
    status,
    headers: { "content-type": "application/json" },
  });
  const smokeFetch = ({ corsStatus = 204, detailStatus = 200 }) => async (_url, options) => {
    if (options.method === "OPTIONS") {
      return new Response(null, {
        status: corsStatus,
        headers: {
          "access-control-allow-origin": "https://lorenzowebsolutions.be",
          "access-control-allow-headers": "apikey,authorization,content-type,x-client-info",
        },
      });
    }
    const body = JSON.parse(options.body);
    if (body.action === "list_pending_intakes") return jsonResponse({ items: [] });
    if (body.action === "list_applications_v2") {
      const items = body.zone === "ACTIVE"
        ? [{ quote_request_id: active.quote_request_id, application_reference: SENTINEL_REFERENCE }]
        : [];
      return jsonResponse({ items, next_cursor: null, has_more: false });
    }
    if (body.action === "get_dossier_substance") return jsonResponse(null, detailStatus);
    throw new Error("UNEXPECTED_SMOKE_REQUEST");
  };

  await assert.rejects(
    runProductionReadOnlySmoke({ apiKey: "public", jwt: "caller", fetchImpl: smokeFetch({ corsStatus: 403 }) }),
    /CORS_PREFLIGHT_FAILED/,
  );
  await assert.rejects(
    runProductionReadOnlySmoke({ apiKey: "public", jwt: "caller", fetchImpl: smokeFetch({ detailStatus: 400 }) }),
    /DETAIL_RPC_FAILED/,
  );
});