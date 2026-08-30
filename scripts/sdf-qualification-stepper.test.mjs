import assert from "node:assert/strict";
import test from "node:test";
import { canActivateSdfStep, deriveSdfStepState } from "../assets/js/sdf-qualification-stepper.mjs";

const completeStepOne = () => ({
  documentPurpose: { categories: ["invoice"] },
  workflowCapabilities: [],
  businessRequirements: {},
  sampleDocumentMetadata: { available: false, requestedByLws: false, uploadRequiredLater: false },
  commercialQualification: {
    packageDirection: "start",
    customComplexity: "",
    documentVolumes: [{ documentType: "invoice", documentCount: 100, period: "monthly", averagePagesPerDocument: 2 }],
  },
});

const completeStepTwo = () => ({ ...completeStepOne(), workflowCapabilities: ["receive"] });

const completeStepThree = () => ({
  ...completeStepTwo(),
  businessRequirements: {
    currentWorkflow: "Handmatig",
    desiredWorkflow: "Gecontroleerd digitaal",
    volumeBand: "50_to_249",
    frequency: "monthly",
    relevantDocumentTypes: ["Factuur"],
    rolesUsers: ["Boekhouding"],
  },
});

test("A-C fresh intake unlocks only step 1 and blocks step 2 and 3 activation", () => {
  const state = deriveSdfStepState();
  assert.deepEqual(state.unlocked, [true, false, false]);
  assert.equal(canActivateSdfStep(state, 1), false);
  assert.equal(canActivateSdfStep(state, 2), false);
});

test("D valid step 1 is completed and unlocks step 2 only", () => {
  const state = deriveSdfStepState(completeStepOne());
  assert.deepEqual(state.completed, [true, false, false]);
  assert.deepEqual(state.unlocked, [true, true, false]);
});

test("E valid step 2 is completed and unlocks step 3", () => {
  const state = deriveSdfStepState(completeStepTwo());
  assert.deepEqual(state.completed, [true, true, false]);
  assert.deepEqual(state.unlocked, [true, true, true]);
});

test("F completed earlier steps remain available for backward navigation", () => {
  const state = deriveSdfStepState(completeStepTwo());
  assert.equal(canActivateSdfStep(state, 0), true);
  assert.equal(canActivateSdfStep(state, 1), true);
});

test("G invalidating step 1 removes completion and relocks downstream steps", () => {
  const changed = completeStepTwo();
  changed.commercialQualification.documentVolumes[0].documentCount = null;
  const state = deriveSdfStepState(changed);
  assert.deepEqual(state.completed, [false, false, false]);
  assert.deepEqual(state.unlocked, [true, false, false]);
});

test("H draft restore with valid step 1 derives only step 1 completion", () => {
  assert.deepEqual(deriveSdfStepState(completeStepOne()).completed, [true, false, false]);
});

test("I draft restore with valid steps 1 and 2 deterministically unlocks step 3", () => {
  const state = deriveSdfStepState(completeStepTwo());
  assert.deepEqual(state.completed, [true, true, false]);
  assert.equal(state.unlocked[2], true);
});

test("J locked steps reject activation regardless of click or keyboard source", () => {
  const state = deriveSdfStepState();
  for (const target of [1, 2]) assert.equal(canActivateSdfStep(state, target), false);
});

test("step 3 completion includes canonical flow fields and confirmation", () => {
  assert.equal(deriveSdfStepState(completeStepThree(), false).completed[2], false);
  assert.equal(deriveSdfStepState(completeStepThree(), true).completed[2], true);
});

test("volume validity requires an exact selected-type bijection", () => {
  const data = completeStepOne();
  data.commercialQualification.documentVolumes.push({ documentType: "quotation", documentCount: 1, period: "weekly", averagePagesPerDocument: 1 });
  assert.equal(deriveSdfStepState(data).valid[0], false);
});
