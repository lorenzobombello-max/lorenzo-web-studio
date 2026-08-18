(function (root, factory) {
  const contract = factory();
  if (typeof module === "object" && module.exports) module.exports = contract;
  else root.LWS_DASHBOARD_CONTRACT = contract;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const APPROVED_BANK = Object.freeze({ bank: "KBC", iban: "BE42 7380 5510 8954", bic: "KREDBEBB" });
  const PAYMENT_MATCH = Object.freeze(["UNVERIFIED", "MATCHED", "PARTIAL", "OVERPAYMENT", "REFERENCE_MISMATCH", "AMOUNT_MISMATCH", "DUPLICATE_EVIDENCE", "REJECTED"]);
  const NEXT_AFTER_ACTION = Object.freeze({
    CREATE_QUOTE: "SEND_QUOTE", SEND_QUOTE: "RECORD_ACCEPTANCE", RECORD_ACCEPTANCE: "PREPARE_M1",
    PREPARE_M1: "REGISTER_M1_SENT", REGISTER_M1_SENT: "WAIT_M1_PAYMENT", WAIT_M1_PAYMENT: "RECONCILE_M1",
    RECONCILE_M1: "CONFIRM_M1_PAYMENT", CONFIRM_M1_PAYMENT: "RELEASE_PROJECT", RELEASE_PROJECT: "START_PROJECT",
    START_PROJECT: "MARK_PREVIEW_READY", MARK_PREVIEW_READY: "SEND_PREVIEW", SEND_PREVIEW: "PREPARE_M2",
    PREPARE_M2: "REGISTER_M2_SENT", REGISTER_M2_SENT: "RECONCILE_M2", RECONCILE_M2: "CONFIRM_M2_PAYMENT",
    CONFIRM_M2_PAYMENT: "MARK_FINAL_READY", MARK_FINAL_READY: "RECORD_FINAL_APPROVAL",
    RECORD_FINAL_APPROVAL: "PREPARE_AND_SEND_FINAL_INVOICE", PREPARE_AND_SEND_FINAL_INVOICE: "RECONCILE_FINAL",
    RECONCILE_FINAL: "CONFIRM_FULL_PAYMENT", CONFIRM_FULL_PAYMENT: "AUTHORIZE_FINAL_TRANSFER",
    AUTHORIZE_FINAL_TRANSFER: "DELIVER", DELIVER: "RECORD_DELIVERY_RECEIPT", RECORD_DELIVERY_RECEIPT: "ARCHIVE", ARCHIVE: null,
  });
  const ACTION_LABELS = Object.freeze({
    CREATE_QUOTE: "Offerte opmaken", SEND_QUOTE: "Offerte verzonden registreren", RECORD_ACCEPTANCE: "Acceptatie registreren",
    PREPARE_M1: "M1 voorbereiden", REGISTER_M1_SENT: "M1 verzonden registreren", WAIT_M1_PAYMENT: "Wachten op betaling",
    RECONCILE_M1: "Betaling controleren", CONFIRM_M1_PAYMENT: "Betaling bevestigen", RELEASE_PROJECT: "Project vrijgeven",
    START_PROJECT: "Project starten", MARK_PREVIEW_READY: "Preview gereed registreren", SEND_PREVIEW: "Preview verzonden registreren",
    PREPARE_M2: "M2 voorbereiden", REGISTER_M2_SENT: "M2 verzonden registreren", RECONCILE_M2: "Betaling controleren",
    CONFIRM_M2_PAYMENT: "M2-betaling bevestigen", MARK_FINAL_READY: "Finale versie gereed registreren",
    RECORD_FINAL_APPROVAL: "Finale goedkeuring registreren", PREPARE_AND_SEND_FINAL_INVOICE: "Restfactuur voorbereiden",
    RECONCILE_FINAL: "Finale betaling controleren", CONFIRM_FULL_PAYMENT: "Volledige betaling bevestigen",
    AUTHORIZE_FINAL_TRANSFER: "Overdracht autoriseren", DELIVER: "Oplevering registreren",
    RECORD_DELIVERY_RECEIPT: "Ontvangst registreren", ARCHIVE: "Archiveren",
  });
  const DANGEROUS_ACTIONS = Object.freeze(["CONFIRM_M1_PAYMENT", "CONFIRM_M2_PAYMENT", "CONFIRM_FULL_PAYMENT", "RELEASE_PROJECT", "AUTHORIZE_FINAL_TRANSFER", "DELIVER", "ARCHIVE"]);
  const STATE_AFTER_ACTION = Object.freeze({
    CREATE_QUOTE: "QUOTE_DRAFT", SEND_QUOTE: "QUOTE_SENT", RECORD_ACCEPTANCE: "QUOTE_ACCEPTED", PREPARE_M1: "M1_READY",
    REGISTER_M1_SENT: "M1_PAYMENT_PENDING", WAIT_M1_PAYMENT: "M1_PAYMENT_PENDING", RECONCILE_M1: "M1_PAYMENT_PENDING",
    CONFIRM_M1_PAYMENT: "M1_PAYMENT_RECEIVED", RELEASE_PROJECT: "PROJECT_RELEASED", START_PROJECT: "PROJECT_IN_PROGRESS",
    MARK_PREVIEW_READY: "PROJECT_IN_PROGRESS", SEND_PREVIEW: "PREVIEW_READY", PREPARE_M2: "M2_READY",
    REGISTER_M2_SENT: "M2_PAYMENT_PENDING", RECONCILE_M2: "M2_PAYMENT_PENDING", CONFIRM_M2_PAYMENT: "M2_PAYMENT_RECEIVED",
    MARK_FINAL_READY: "FINAL_DELIVERY_READY", RECORD_FINAL_APPROVAL: "FINAL_APPROVAL_RECORDED",
    PREPARE_AND_SEND_FINAL_INVOICE: "FINAL_PAYMENT_PENDING", RECONCILE_FINAL: "FINAL_PAYMENT_PENDING",
    CONFIRM_FULL_PAYMENT: "FULL_PAYMENT_RECEIVED", AUTHORIZE_FINAL_TRANSFER: "FINAL_TRANSFER_AUTHORIZED",
    DELIVER: "DELIVERED", RECORD_DELIVERY_RECEIPT: "DELIVERED", ARCHIVE: "ARCHIVED",
  });
  const SCENARIOS = Object.freeze({
    m1: Object.freeze({ id: "m1", label: "M1-betaling open", currentState: "M1_PAYMENT_PENDING", nextAction: "RECONCILE_M1", expectedAmountMinor: 140000, invoiceReference: "TEST-INV-NONPROD-PRJ-0001-M1", paymentStatus: "UNVERIFIED", previewStatus: "NOT_AVAILABLE", finalApproval: false, transferStatus: "BLOCKED", blockerType: "OPERATOR ACTION REQUIRED", blocker: "Handmatige betalingscontrole vereist.", documentStage: 3 }),
    preview: Object.freeze({ id: "preview", label: "Preview nog niet gereed", currentState: "PROJECT_IN_PROGRESS", nextAction: "MARK_PREVIEW_READY", expectedAmountMinor: 140000, invoiceReference: "TEST-INV-NONPROD-PRJ-0001-M2", paymentStatus: "MATCHED", previewStatus: "NOT_READY", finalApproval: false, transferStatus: "BLOCKED", blockerType: "COMMERCIAL BLOCKER", blocker: "Preview is nog niet gereed; M2 blijft geblokkeerd.", documentStage: 5 }),
    final: Object.freeze({ id: "final", label: "Finale betaling open", currentState: "FINAL_PAYMENT_PENDING", nextAction: "RECONCILE_FINAL", expectedAmountMinor: 70000, invoiceReference: "TEST-INV-NONPROD-PRJ-0001-M3", paymentStatus: "UNVERIFIED", previewStatus: "SENT", finalApproval: true, transferStatus: "BLOCKED", blockerType: "COMMERCIAL BLOCKER", blocker: "Finale betaling moet handmatig worden gecontroleerd.", documentStage: 9 }),
  });

  function classifyPayment(input, usedReferences) {
    if (usedReferences.has(input.transactionReference) || usedReferences.has(input.evidenceReference)) return "DUPLICATE_EVIDENCE";
    if (input.bank !== APPROVED_BANK.bank || input.iban !== APPROVED_BANK.iban || input.bic !== APPROVED_BANK.bic) return "REJECTED";
    if (input.projectReference !== "TEST-PRJ-0001" || input.customerReference !== "TEST-CUS-0001" || input.invoiceReference !== input.expectedInvoiceReference) return "REFERENCE_MISMATCH";
    if (input.receivedAmountMinor < input.expectedAmountMinor) return "PARTIAL";
    if (input.receivedAmountMinor > input.expectedAmountMinor) return "OVERPAYMENT";
    if (input.expectedAmountMinor !== input.authorityAmountMinor || input.receivedAmountMinor !== input.authorityAmountMinor) return "AMOUNT_MISMATCH";
    return "MATCHED";
  }

  function visibleActions(state) {
    if (!state.nextAction) return [];
    if (state.nextAction.startsWith("CONFIRM_") && state.paymentStatus !== "MATCHED") return [];
    return [state.nextAction];
  }

  function appendAudit(events, event) {
    return Object.freeze([...events, Object.freeze({ ...event })]);
  }

  function appendIdempotent(events, processedKeys, key, event) {
    if (processedKeys[key]) return { events, processedKeys, replay: true };
    return { events: appendAudit(events, event), processedKeys: Object.freeze({ ...processedKeys, [key]: event.event_id }), replay: false };
  }

  function createScenario(id) {
    const scenario = SCENARIOS[id] || SCENARIOS.m1;
    return {
      scenarioId: scenario.id, currentState: scenario.currentState, nextAction: scenario.nextAction,
      paymentStatus: scenario.paymentStatus, previewStatus: scenario.previewStatus, finalApproval: scenario.finalApproval,
      transferStatus: scenario.transferStatus, blockerType: scenario.blockerType, blocker: scenario.blocker,
      expectedAmountMinor: scenario.expectedAmountMinor, invoiceReference: scenario.invoiceReference, documentStage: scenario.documentStage,
      lastEvidence: "TEST-ACCEPTANCE-EVIDENCE-0001", events: [], processedKeys: {}, usedReferences: [],
      totalMinor: 350000, m1Minor: 140000, m2Minor: 140000, remainderMinor: 70000,
    };
  }

  return Object.freeze({ APPROVED_BANK, PAYMENT_MATCH, NEXT_AFTER_ACTION, ACTION_LABELS, DANGEROUS_ACTIONS, STATE_AFTER_ACTION, SCENARIOS, classifyPayment, visibleActions, appendAudit, appendIdempotent, createScenario });
});