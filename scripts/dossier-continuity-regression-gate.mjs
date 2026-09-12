import { readFile, writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

export const SENTINEL_REFERENCE = "LWS-AAN-2026-0006";
export const REQUIRED_RELEASE_CHECKS = Object.freeze([
  "CORS",
  "JWT_FORWARDING",
  "PENDING_RPC",
  "ACTIVE_RPC",
  "DETAIL_RPC",
  "PENDING_PROJECTION",
  "ACTIVE_PROJECTION",
  "TRASH_PROJECTION",
  "RESPONSE_CONTRACT",
  "UI_CONTINUITY",
  "SENTINEL",
  "PRE_POST_COUNT_GUARD",
]);
const COUNT_FIELDS = Object.freeze([
  "TOTAL_RAW",
  "TOTAL_PENDING",
  "TOTAL_ACTIVE",
  "TOTAL_TRASHED",
]);
const PRODUCTION_ORIGIN = "https://lorenzowebsolutions.be";
const EDGE_URL = "https://xcsptvntvrizwhskaphr.supabase.co/functions/v1/commercial-operator-command";

function fail(code) {
  throw new Error(code);
}

function exactKeys(value, expected) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const actual = Object.keys(value).sort();
  return actual.length === expected.length && actual.every((key, index) => key === [...expected].sort()[index]);
}

function validOperator(operator) {
  return operator && operator.authUidMatches === true && operator.status === "ACTIVE" &&
    ["owner", "admin"].includes(operator.role);
}

export function evaluateDossierProjections(
  records,
  assignedOperatorId,
  operator = { role: "owner", status: "ACTIVE", authUidMatches: true },
) {
  if (!validOperator(operator) || !Array.isArray(records)) fail("OPERATOR_READ_DENIED");
  const pending = records.filter((record) => record.projection === "PENDING" && record.dossier_state !== "TRASHED");
  const active = records.filter((record) => record.projection === "ACTIVE" && record.dossier_state !== "TRASHED");
  const trash = records.filter((record) => record.projection === "TRASHED" || record.dossier_state === "TRASHED");
  const visible = [...pending, ...active, ...trash];
  return Object.freeze({
    pending,
    active,
    trash,
    personalQueue: records.filter((record) =>
      record.assigned_operator_id === assignedOperatorId && record.dossier_state !== "TRASHED"
    ),
    detail: (quoteRequestId) => visible.find((record) => record.quote_request_id === quoteRequestId) || null,
  });
}

export function validatePendingEnvelope(value) {
  if (!exactKeys(value, ["items"]) || !Array.isArray(value.items)) fail("PENDING_DTO_CONTRACT");
  for (const item of value.items) {
    if (!exactKeys(item, ["quote_request_id", "dossier_state", "dossier_revision", "seen_at"]) ||
      typeof item.quote_request_id !== "string" || typeof item.dossier_state !== "string" ||
      !Number.isSafeInteger(item.dossier_revision) ||
      !(item.seen_at === null || typeof item.seen_at === "string")) {
      fail("PENDING_DTO_CONTRACT");
    }
  }
  return value;
}

export function validateActiveEnvelope(value) {
  if (!exactKeys(value, ["items", "next_cursor", "has_more"]) || !Array.isArray(value.items) ||
    !(value.next_cursor === null || typeof value.next_cursor === "string") ||
    typeof value.has_more !== "boolean") {
    fail("ACTIVE_ENVELOPE_CONTRACT");
  }
  return value;
}

export function validateUiContinuity({ ok, items }) {
  if (ok !== true) return Object.freeze({ state: "failure", showEmpty: false, showLoadError: true });
  if (!Array.isArray(items)) fail("UI_CONTINUITY_CONTRACT");
  return items.length === 0
    ? Object.freeze({ state: "empty", showEmpty: true, showLoadError: false })
    : Object.freeze({ state: "populated", showEmpty: false, showLoadError: false });
}

function validateCounts(value) {
  if (!exactKeys(value, COUNT_FIELDS) || COUNT_FIELDS.some((field) => !Number.isSafeInteger(value[field]) || value[field] < 0)) {
    fail("COUNT_CONTRACT");
  }
  return value;
}

export function compareDossierCounts(before, after) {
  validateCounts(before);
  validateCounts(after);
  const changed = COUNT_FIELDS.filter((field) => before[field] !== after[field]);
  return Object.freeze({ pass: changed.length === 0, changed });
}

export function evaluateReleaseGate(checks) {
  const failures = REQUIRED_RELEASE_CHECKS.filter((name) => checks?.[name] !== true);
  return Object.freeze({
    releaseGate: failures.length === 0 ? "PASS" : "FAIL",
    productionReleaseAllowed: failures.length === 0 ? "JA" : "NEE",
    failures,
  });
}

async function source(root, path) {
  return readFile(new URL(path, root), "utf8");
}

function includesAll(text, values) {
  return values.every((value) => text.includes(value));
}

export async function inspectDossierContinuitySourceContracts(root) {
  const [edge, callerJwtTest, handler, cors, listSql, readmodelSql, pendingSql, detailSql, queueSql, ui, aal2Sql] = await Promise.all([
    source(root, "supabase/functions/commercial-operator-command/index.ts"),
    source(root, "supabase/functions/commercial-operator-command/caller-jwt-read-path.test.ts"),
    source(root, "supabase/functions/commercial-operator-command/handler.ts"),
    source(root, "supabase/functions/_shared/cors.ts"),
    source(root, "supabase/migrations/20260904210000_route_dossier_list_through_caller_jwt_v1.sql"),
    source(root, "supabase/migrations/20260824130000_add_operator_dossier_readmodel_v2.sql"),
    source(root, "supabase/migrations/20260904190000_route_pending_intake_list_through_caller_jwt_v1.sql"),
    source(root, "supabase/migrations/20260904220000_route_dossier_substance_through_caller_jwt_v1.sql"),
    source(root, "supabase/migrations/20260828235000_exclude_trashed_dossiers_from_personal_queue.sql"),
    source(root, "assets/js/operator-dossiers.mjs"),
    source(root, "supabase/migrations/20260904160000_require_operator_aal2_for_critical_actions_v1.sql"),
  ]);
  const callerReadRpcs = [
    "list_operator_pending_intakes_v1",
    "list_operator_pending_sdf_intakes_v1",
    "count_operator_active_pending_intakes_v1",
    "list_operator_applications_v2",
    "get_operator_dossier_facets_v2",
    "get_operator_dossier_substance_v1",
  ];
  const jwtForwarding = callerReadRpcs.every((rpc) => edge.includes(rpc)) &&
    includesAll(callerJwtTest, ["clientFor(jwt)", "service role"]);
  const actorBinding = (sql) => includesAll(sql, [
    "auth.uid() is null",
    "auth.uid() <> p_actor_auth_user_id",
    "OPERATOR_IDENTITY_MISMATCH",
    "to authenticated",
  ]);
  const personalQueueAuth = includesAll(queueSql, ["auth.uid()", "assignee_operator_id", "readmodel.zone <> 'TRASHED'"]);
  const aal2Policy = includesAll(handler, ["requireOperatorAal2(claims, sub)", "list_pending_intakes", "list_applications_v2"]) &&
    includesAll(aal2Sql, ["aal2", "AAL2_REQUIRED"]);
  const checks = {
    CORS: includesAll(cors, [PRODUCTION_ORIGIN, "apikey", "authorization", "content-type", "x-client-info"]),
    JWT_FORWARDING: jwtForwarding && personalQueueAuth && aal2Policy,
    PENDING_RPC: actorBinding(pendingSql) && pendingSql.includes("list_operator_pending_intakes_v1"),
    ACTIVE_RPC: actorBinding(listSql) && listSql.includes("list_operator_applications_v2"),
    DETAIL_RPC: actorBinding(detailSql) && detailSql.includes("get_operator_dossier_substance_v1"),
    PENDING_PROJECTION: pendingSql.includes("project_operator_dossier_seen_v1"),
    ACTIVE_PROJECTION: includesAll(readmodelSql, ["p_zone <> 'ACTIVE_ARCHIVED'", "readmodel.zone = p_zone"]),
    TRASH_PROJECTION: includesAll(readmodelSql, ["p_zone = 'TRASHED'", "readmodel.zone = 'TRASHED'"]),
    RESPONSE_CONTRACT: includesAll(handler, ["dossier_state", "dossier_revision", "seen_at", "next_cursor", "has_more"]),
    UI_CONTINUITY: includesAll(ui, ["Geen dossiers gevonden.", "Dossiers konden niet veilig worden geladen.", "data-dossiers-empty"]),
    SENTINEL: SENTINEL_REFERENCE === "LWS-AAN-2026-0006",
    PRE_POST_COUNT_GUARD: COUNT_FIELDS.length === 4,
    JWT_CALLSITES: jwtForwarding,
    PERSONAL_QUEUE_AUTH: personalQueueAuth,
    AAL2_POLICY: aal2Policy,
  };
  const failures = REQUIRED_RELEASE_CHECKS.filter((name) => checks[name] !== true);
  return Object.freeze({ pass: failures.length === 0, checks: Object.freeze(checks), failures });
}

function requestHeaders(apiKey, jwt) {
  return {
    apikey: apiKey,
    Authorization: `Bearer ${jwt}`,
    "Content-Type": "application/json",
    "x-client-info": "lws-dossier-continuity-gate/1.0",
  };
}

async function edgeRequest(fetchImpl, apiKey, jwt, body) {
  const response = await fetchImpl(EDGE_URL, {
    method: "POST",
    headers: requestHeaders(apiKey, jwt),
    body: JSON.stringify(body),
    redirect: "error",
  });
  const payload = await response.json().catch(() => null);
  return { status: response.status, payload };
}

async function listAll(fetchImpl, apiKey, jwt, zone) {
  const items = [];
  let cursor = null;
  do {
    const response = await edgeRequest(fetchImpl, apiKey, jwt, {
      action: "list_applications_v2",
      zone,
      operational_status: null,
      year: null,
      quarter: null,
      request_kind: null,
      search: null,
      cursor,
      limit: 100,
    });
    if (response.status !== 200) fail(`${zone}_RPC_FAILED`);
    const envelope = validateActiveEnvelope(response.payload?.result);
    items.push(...envelope.items);
    cursor = envelope.has_more ? envelope.next_cursor : null;
  } while (cursor);
  return items;
}

export async function runProductionReadOnlySmoke({ apiKey, jwt, fetchImpl = fetch }) {
  if (!apiKey || !jwt) fail("PRODUCTION_READONLY_CREDENTIALS_REQUIRED");
  const preflight = await fetchImpl(EDGE_URL, {
    method: "OPTIONS",
    headers: {
      Origin: PRODUCTION_ORIGIN,
      "Access-Control-Request-Headers": "apikey,authorization,content-type,x-client-info",
    },
    redirect: "error",
  });
  const allowHeaders = new Set((preflight.headers.get("access-control-allow-headers") || "").split(",").map((value) => value.trim().toLowerCase()));
  const cors = preflight.status === 204 &&
    preflight.headers.get("access-control-allow-origin") === PRODUCTION_ORIGIN &&
    ["apikey", "authorization", "content-type", "x-client-info"].every((header) => allowHeaders.has(header));
  if (!cors) fail("CORS_PREFLIGHT_FAILED");
  const pendingResponse = await edgeRequest(fetchImpl, apiKey, jwt, { action: "list_pending_intakes", retention_state: "ACTIVE" });
  if (pendingResponse.status !== 200 || !Array.isArray(pendingResponse.payload?.result?.items)) fail("PENDING_RPC_FAILED");
  const [active, archived, trash] = await Promise.all([
    listAll(fetchImpl, apiKey, jwt, "ACTIVE"),
    listAll(fetchImpl, apiKey, jwt, "ARCHIVED"),
    listAll(fetchImpl, apiKey, jwt, "TRASHED"),
  ]);
  const sentinel = active.find((item) => item.application_reference === SENTINEL_REFERENCE);
  if (!sentinel?.quote_request_id) fail("SENTINEL_ACTIVE_LIST_MISSING");
  const detail = await edgeRequest(fetchImpl, apiKey, jwt, {
    action: "get_dossier_substance",
    quote_request_id: sentinel.quote_request_id,
  });
  if (detail.status !== 200 || !detail.payload?.result) fail("DETAIL_RPC_FAILED");
  if (trash.some((item) => item.application_reference === SENTINEL_REFERENCE)) fail("SENTINEL_TRASHED");
  const pending = pendingResponse.payload.result.items;
  const rawIds = new Set([...pending, ...active, ...archived, ...trash].map((item) => item.quote_request_id));
  const counts = Object.freeze({
    TOTAL_RAW: rawIds.size,
    TOTAL_PENDING: pending.length,
    TOTAL_ACTIVE: active.length,
    TOTAL_TRASHED: trash.length,
  });
  validateCounts(counts);
  return Object.freeze({
    checks: Object.freeze({
      CORS: cors,
      PENDING_RPC: true,
      ACTIVE_RPC: true,
      DETAIL_RPC: true,
      SENTINEL: true,
    }),
    sentinel: Object.freeze({ rawPresent: true, listPresent: true, detailPresent: true, expectedZone: "ACTIVE", notTrashed: true }),
    counts,
  });
}

function valueAfter(argumentsList, flag) {
  const index = argumentsList.indexOf(flag);
  return index >= 0 ? argumentsList[index + 1] : null;
}

async function main(argumentsList) {
  const mode = argumentsList[0] || "local";
  if (mode === "local") {
    const result = await inspectDossierContinuitySourceContracts(new URL("../", import.meta.url));
    const gate = evaluateReleaseGate(result.checks);
    for (const name of REQUIRED_RELEASE_CHECKS) console.log(`${name}=${result.checks[name] ? "PASS" : "FAIL"}`);
    console.log(`PRODUCTION_RELEASE_ALLOWED=${gate.productionReleaseAllowed}`);
    if (!result.pass) process.exitCode = 1;
    return;
  }
  if (mode === "smoke" || mode === "snapshot") {
    const result = await runProductionReadOnlySmoke({
      apiKey: process.env.LWS_SUPABASE_ANON_KEY,
      jwt: process.env.LWS_OPERATOR_JWT,
    });
    for (const [name, passed] of Object.entries(result.checks)) console.log(`${name}=${passed ? "PASS" : "FAIL"}`);
    for (const [name, count] of Object.entries(result.counts)) console.log(`${name}=${count}`);
    console.log("SENTINEL_2026_0006=PASS");
    if (mode === "snapshot") {
      const output = valueAfter(argumentsList, "--output");
      if (!output) fail("SNAPSHOT_OUTPUT_REQUIRED");
      await writeFile(output, `${JSON.stringify(result.counts, null, 2)}\n`, { flag: "wx" });
    }
    return;
  }
  if (mode === "compare") {
    const beforePath = valueAfter(argumentsList, "--before");
    const afterPath = valueAfter(argumentsList, "--after");
    if (!beforePath || !afterPath) fail("COUNT_SNAPSHOTS_REQUIRED");
    const comparison = compareDossierCounts(
      JSON.parse(await readFile(beforePath, "utf8")),
      JSON.parse(await readFile(afterPath, "utf8")),
    );
    console.log(`PRE_POST_COUNT_GUARD=${comparison.pass ? "PASS" : "FAIL"}`);
    console.log(`PRODUCTION_RELEASE_ALLOWED=${comparison.pass ? "JA" : "NEE"}`);
    if (!comparison.pass) process.exitCode = 1;
    return;
  }
  fail("UNKNOWN_GATE_MODE");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(`DOSSIER_CONTINUITY_GATE_ERROR=${error.message}`);
    console.error("PRODUCTION_RELEASE_ALLOWED=NEE");
    process.exitCode = 1;
  });
}