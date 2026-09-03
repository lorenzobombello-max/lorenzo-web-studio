import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  bindDossierPurgeEligibility,
  presentDossierPurgeEligibility,
  retainDossierPurgeEligibility,
} from "../assets/js/operator-dossiers.mjs";

const root = new URL("../", import.meta.url);
const referenceA = "LWS-AAN-2099-0001";
const referenceB = "LWS-AAN-2099-0002";

function createPurgeWorkspace() {
  const purge = {
    hidden: true,
    disabled: false,
    attributes: new Map(),
    setAttribute(name, value) { this.attributes.set(name, value); },
    removeAttribute(name) { this.attributes.delete(name); },
  };
  const message = { textContent: "" };
  return {
    purge,
    message,
    querySelector(selector) {
      if (selector === "[data-dossiers-purge]") return purge;
      if (selector === "[data-dossiers-purge-message]") return message;
      throw new Error(`Unexpected selector: ${selector}`);
    },
  };
}

const allowed = (reference = referenceA)=>bindDossierPurgeEligibility(reference, { can_purge: true, reason: null });
const denied = (reference = referenceA)=>bindDossierPurgeEligibility(reference, { can_purge: false, reason: "PROJECT_EXISTS" });

test("confirmed allowed Trash eligibility remains visible while refresh is pending", ()=>{
  const workspace = createPurgeWorkspace();
  presentDossierPurgeEligibility(workspace, retainDossierPurgeEligibility(allowed(), referenceA), { refreshing: true });
  assert.equal(workspace.purge.hidden, false);
  assert.equal(workspace.purge.disabled, true);
  assert.equal(workspace.purge.attributes.get("aria-busy"), "true");
  assert.equal(workspace.message.textContent, "Permanent verwijderen is server-side toegestaan.");
});

test("same-dossier allowed refresh keeps permanent deletion available", ()=>{
  const workspace = createPurgeWorkspace();
  presentDossierPurgeEligibility(workspace, allowed());
  assert.equal(workspace.purge.hidden, false);
  assert.equal(workspace.purge.disabled, false);
  assert.equal(workspace.purge.attributes.has("aria-busy"), false);
});

test("same-dossier explicit denied refresh replaces confirmed allowed state", ()=>{
  const workspace = createPurgeWorkspace();
  presentDossierPurgeEligibility(workspace, denied());
  assert.equal(workspace.purge.hidden, true);
  assert.equal(workspace.purge.disabled, false);
  assert.match(workspace.message.textContent, /project aan dit dossier gekoppeld/);
});

test("eligibility request failure restores the last confirmed presentation", ()=>{
  const workspace = createPurgeWorkspace();
  const previous = allowed();
  presentDossierPurgeEligibility(workspace, previous, { refreshing: true });
  presentDossierPurgeEligibility(workspace, previous);
  assert.equal(workspace.purge.hidden, false);
  assert.equal(workspace.purge.disabled, false);
  assert.equal(workspace.message.textContent, "Permanent verwijderen is server-side toegestaan.");
});

test("eligibility is never retained across dossier selection", ()=>{
  const workspace = createPurgeWorkspace();
  const retained = retainDossierPurgeEligibility(allowed(referenceA), referenceB);
  presentDossierPurgeEligibility(workspace, retained);
  assert.equal(retained, null);
  assert.equal(workspace.purge.hidden, true);
  assert.equal(workspace.message.textContent, "");
});

test("first Trash load without confirmed eligibility has no false positive", ()=>{
  const workspace = createPurgeWorkspace();
  presentDossierPurgeEligibility(workspace, null, { refreshing: true });
  assert.equal(workspace.purge.hidden, true);
  assert.equal(workspace.purge.disabled, false);
  assert.equal(workspace.message.textContent, "");
});

test("restore control remains independent from purge eligibility presentation", async ()=>{
  const source = await readFile(new URL("assets/js/operator-dossiers.mjs", root), "utf8");
  assert.match(source, /TRASHED: \["restore_dossier"\]/);
  assert.doesNotMatch(presentDossierPurgeEligibility.toString(), /restore_dossier|data-dossiers-lifecycle/);
});

test("non-Trash selection clears permanent deletion presentation", ()=>{
  const workspace = createPurgeWorkspace();
  presentDossierPurgeEligibility(workspace, allowed());
  presentDossierPurgeEligibility(workspace, null);
  assert.equal(workspace.purge.hidden, true);
  assert.equal(workspace.message.textContent, "");
});

test("repeated periodic refresh cycles never toggle confirmed allowed visibility", ()=>{
  const workspace = createPurgeWorkspace();
  let current = allowed();
  for (let cycle = 0; cycle < 3; cycle += 1) {
    current = retainDossierPurgeEligibility(current, referenceA);
    presentDossierPurgeEligibility(workspace, current, { refreshing: true });
    assert.equal(workspace.purge.hidden, false);
    current = allowed();
    presentDossierPurgeEligibility(workspace, current);
    assert.equal(workspace.purge.hidden, false);
  }
});

test("refresh integration preserves by reference without adding network or timer paths", async ()=>{
  const source = await readFile(new URL("assets/js/operator-dossiers.mjs", root), "utf8");
  assert.match(source, /retainDossierPurgeEligibility\(state\.purgeEligibility, summary\.reference\)/);
  assert.match(source, /presentDossierPurgeEligibility\(workspace, state\.purgeEligibility, \{ refreshing: Boolean\(state\.purgeEligibility\) \}\)/);
  assert.match(source, /state\.purgeEligibility = bindDossierPurgeEligibility\(summary\.reference, eligibility\)/);
  assert.doesNotMatch(source, /purgeEligibility[\s\S]{0,120}(?:setTimeout|setInterval|createOperatorAutoRefresh)/);
});