import assert from "node:assert/strict";
import test from "node:test";

import {
  C3_COMMIT_SHA,
  C3_REPOSITORY,
  C3_REPOSITORY_ID,
  assertC3SourceBinding,
  authorizeC3OperatorSession,
  createC3BrowserContextOptions,
  createC3BrowserLaunchOptions,
  createC3DetailProjection,
  createC3DossierSubstance,
  selectC3Build,
  translateC3HandoffUrl,
} from "./git001c-local-c3-demo.mjs";
import { websiteChildContext } from "../assets/js/operator-website-execution-child.mjs";

test("supplies the existing Website-child dossier substance contract", () => {
  const substance = createC3DossierSubstance();
  assert.equal(substance.quote_request_id, "a1e5c3e8-27a6-47c3-8ec1-75653bd2e8ac");
  assert.equal(substance.request_kind, "website");
  assert.equal(substance.intake.status, "submitted");
  assert.deepEqual(substance.documents, { customer_request_count: 0, uploaded_document_count: 0 });
  const context = websiteChildContext(
    createC3DetailProjection(),
    "a1e5c3e8-27a6-47c3-8ec1-75653bd2e8ac",
    substance,
  );
  assert.equal(context.dossierReference, "#00000006");
});

test("uses the maximized native viewport for every visible C3 page", () => {
  assert.deepEqual(createC3BrowserLaunchOptions(), {
    headless: false,
    ignoreDefaultArgs: ["--disable-popup-blocking"],
    args: ["--start-maximized"],
  });
  assert.deepEqual(createC3BrowserContextOptions(), { viewport: null });
});

test("accepts only the existing exact 0006 source binding", () => {
  assert.equal(C3_REPOSITORY_ID, "1378797607");
  assert.deepEqual(assertC3SourceBinding({
    repositoryOwner: "lorenzo-web-solutions",
    repositoryName: C3_REPOSITORY.split("/")[1],
    repositoryExternalId: C3_REPOSITORY_ID,
  }), {
    repositoryOwner: "lorenzo-web-solutions",
    repositoryName: C3_REPOSITORY.split("/")[1],
    repositoryExternalId: C3_REPOSITORY_ID,
  });
  assert.throws(() => assertC3SourceBinding({
    repositoryOwner: "lorenzo-web-solutions",
    repositoryName: `${C3_REPOSITORY.split("/")[1]}-copy`,
    repositoryExternalId: C3_REPOSITORY_ID,
  }), /C3_SOURCE_BINDING_INVALID/);
});

test("selects only a completed exact-commit build with persisted artifacts", () => {
  const selected = selectC3Build([
    { buildId: "old", commitSha: "a".repeat(40), status: "PASS", artifactCount: 4, builtAt: "2026-09-23T08:00:00Z" },
    { buildId: "failed", commitSha: C3_COMMIT_SHA, status: "FAILED", artifactCount: 4, builtAt: "2026-09-23T09:00:00Z" },
    { buildId: "current", commitSha: C3_COMMIT_SHA, status: "PASS_WITH_WARNINGS", artifactCount: 6, builtAt: "2026-09-23T10:00:00Z" },
  ]);
  assert.equal(selected.buildId, "current");
  assert.throws(() => selectC3Build([]), /C3_BUILD_NOT_AVAILABLE/);
});

test("authorizes only the fixed active owner at aal2", () => {
  const valid = {
    actorId: "c9bcd3ef-1e7e-4889-8a12-db827f1b97b0",
    role: "owner",
    status: "ACTIVE",
    aal: "aal2",
    expiresAt: 2_000,
  };
  assert.equal(authorizeC3OperatorSession(valid, 1_000), true);
  assert.throws(() => authorizeC3OperatorSession({ ...valid, aal: "aal1" }), /C3_AAL2_REQUIRED/);
  assert.throws(() => authorizeC3OperatorSession({ ...valid, actorId: crypto.randomUUID() }), /C3_OPERATOR_NOT_AUTHORIZED/);
  assert.throws(() => authorizeC3OperatorSession({ ...valid, expiresAt: 1_010 }, 1_000), /C3_OPERATOR_SESSION_EXPIRED/);
});

test("translates only the local gateway handoff to the isolated HTTPS preview origin", () => {
  const translated = translateC3HandoffUrl(
    "http://127.0.0.1:43111/__preview-session?build=build-1&token=abc",
    "http://127.0.0.1:43111",
    "https://localhost:43112",
  );
  assert.equal(translated, "https://localhost:43112/__preview-session?build=build-1&token=abc");
  assert.throws(() => translateC3HandoffUrl(
    "https://attacker.example/__preview-session?build=build-1&token=abc",
    "http://127.0.0.1:43111",
    "https://localhost:43112",
  ), /C3_HANDOFF_URL_INVALID/);
});