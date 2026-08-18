(function () {
  "use strict";

  const contract = window.LWS_DASHBOARD_CONTRACT;
  const storageKey = "lws-phase5d-synthetic-state-v1";
  const documentNames = ["Offerte", "Acceptatie", "M1 working invoice", "Payment evidence", "Project-release communication", "Preview communication", "M2 working invoice", "Final approval", "Final working invoice", "Transfer checklist", "Delivery document", "Reminder", "Change order"];
  const documentLinks = {
    "M1 working invoice": "../../LWS_Commercial_Document_Flow_Phase5A_2026-08-16/working-docx/LWS_INVOICE_MILESTONE_1_40_NONPRODUCTION.docx",
    "Payment evidence": "../../LWS_Commercial_Document_Flow_Phase5A_2026-08-16/working-docx/LWS_PAYMENT_PROJECT_RELEASE_EVIDENCE_NONPRODUCTION.docx",
    "Project-release communication": "../../LWS_Commercial_Document_Flow_Phase5A_2026-08-16/working-docx/LWS_CUSTOMER_COMMUNICATIONS_NONPRODUCTION.docx",
    "Preview communication": "../../LWS_Commercial_Document_Flow_Phase5A_2026-08-16/working-docx/LWS_CUSTOMER_COMMUNICATIONS_NONPRODUCTION.docx",
    "M2 working invoice": "../../LWS_Commercial_Document_Flow_Phase5A_2026-08-16/working-docx/LWS_INVOICE_MILESTONE_2_40_NONPRODUCTION.docx",
    "Final approval": "../../LWS_Commercial_Document_Flow_Phase5A_2026-08-16/working-docx/LWS_FINAL_APPROVAL_TRANSFER_DELIVERY_NONPRODUCTION.docx",
    "Final working invoice": "../../LWS_Commercial_Document_Flow_Phase5A_2026-08-16/working-docx/LWS_INVOICE_FINAL_REMAINDER_NONPRODUCTION.docx",
    "Transfer checklist": "../../LWS_Commercial_Document_Flow_Phase5A_2026-08-16/working-docx/LWS_FINAL_APPROVAL_TRANSFER_DELIVERY_NONPRODUCTION.docx",
    "Delivery document": "../../LWS_Commercial_Document_Flow_Phase5A_2026-08-16/working-docx/LWS_FINAL_APPROVAL_TRANSFER_DELIVERY_NONPRODUCTION.docx",
    "Reminder": "../../LWS_Commercial_Document_Flow_Phase5A_2026-08-16/working-docx/LWS_CUSTOMER_COMMUNICATIONS_NONPRODUCTION.docx",
    "Change order": "../../LWS_Commercial_Document_Flow_Phase5A_2026-08-16/working-docx/LWS_CHANGE_ORDER_NONPRODUCTION.docx",
  };
  const descriptions = {
    RECONCILE_M1: "Controleer de KBC-transactie handmatig. Alleen een exacte MATCHED-status maakt betalingsbevestiging beschikbaar.",
    CONFIRM_M1_PAYMENT: "De betaling is MATCHED. Bevestig nu afzonderlijk dat de transactie werkelijk is ontvangen en gecontroleerd.",
    RELEASE_PROJECT: "M1 is bevestigd. Projectvrijgave vereist nog een expliciete operatorbevestiging.",
    MARK_PREVIEW_READY: "Registreer eerst dat de kernfunctionaliteit gereed is en geen reviewblocker bestaat.",
    SEND_PREVIEW: "De preview is gereed. Registreer de beveiligde levering aan de klant.",
    RECONCILE_FINAL: "Controleer het exacte restbedrag handmatig op de KBC-rekening.",
    CONFIRM_FULL_PAYMENT: "Het restbedrag is MATCHED. Bevestig volledige betaling afzonderlijk.",
    AUTHORIZE_FINAL_TRANSFER: "Alle milestones zijn betaald. Autoriseer de finale overdracht expliciet.",
    DELIVER: "Overdracht is geautoriseerd. Bevestig de geconfigureerde veilige oplevering.",
    RECORD_DELIVERY_RECEIPT: "Registreer het synthetische ontvangstbewijs voordat archivering beschikbaar wordt.",
    ARCHIVE: "Controleer het dossier en bevestig append-only archivering.",
  };
  const dangerousText = {
    CONFIRM_M1_PAYMENT: "Bevestig dat € 1.400 daadwerkelijk op de KBC-rekening is ontvangen en handmatig is gecontroleerd.",
    CONFIRM_M2_PAYMENT: "Bevestig dat € 1.400 daadwerkelijk op de KBC-rekening is ontvangen en handmatig is gecontroleerd.",
    CONFIRM_FULL_PAYMENT: "Bevestig dat € 700 daadwerkelijk op de KBC-rekening is ontvangen en dat alle oorspronkelijke milestones volledig betaald zijn.",
    RELEASE_PROJECT: "Bevestig projectvrijgave uitsluitend op basis van de gecontroleerde M1-betaling.",
    AUTHORIZE_FINAL_TRANSFER: "Bevestig dat alle oorspronkelijke milestones volledig betaald zijn en de finale overdracht mag starten.",
    DELIVER: "Bevestig dat uitsluitend de geconfigureerde deliverables via de veilige overdracht zijn opgeleverd.",
    ARCHIVE: "Bevestig dat ontvangstbewijs, documentreferenties en artifact evidence compleet zijn.",
  };
  const elements = Object.fromEntries(["scenarioSelect", "stateBadge", "next-action-title", "nextActionDescription", "primaryAction", "actionMessage", "paymentPanel", "paymentForm", "expectedAmount", "receivedAmount", "transactionDate", "transactionReference", "evidenceReference", "paymentNotes", "matchBadge", "matchResult", "paymentStatus", "previewStatus", "approvalStatus", "transferStatus", "lastEvidence", "blockerType", "commercialBlocker", "documentList", "auditTimeline", "auditEmpty", "confirmationDialog", "confirmationTitle", "confirmationText", "confirmAction"].map((id) => [id, document.getElementById(id)]));
  let state = restoreState("m1");
  let pendingDangerousAction = null;

  function restoreState(scenarioId) {
    const raw = localStorage.getItem(storageKey);
    if (raw) {
      try { const parsed = JSON.parse(raw); if (parsed.scenarioId === scenarioId) return parsed; } catch (_) { localStorage.removeItem(storageKey); }
    }
    return contract.createScenario(scenarioId);
  }
    let actionLocked = false;

  function persist() { localStorage.setItem(storageKey, JSON.stringify(state)); }
  function euro(minor) { return new Intl.NumberFormat("nl-BE", { style: "currency", currency: "EUR", maximumFractionDigits: 2 }).format(minor / 100); }
  function paymentAction(action) { return ["RECONCILE_M1", "CONFIRM_M1_PAYMENT", "RECONCILE_M2", "CONFIRM_M2_PAYMENT", "RECONCILE_FINAL", "CONFIRM_FULL_PAYMENT"].includes(action); }
  function setPaymentDefaults() {
    const milestone = state.scenarioId === "final" ? 3 : state.scenarioId === "preview" ? 2 : 1;
    elements.receivedAmount.value = String(state.expectedAmountMinor / 100);
    elements.transactionReference.value = `TEST-KBC-TXN-M${milestone}`;
    elements.evidenceReference.value = `TEST-PAY-EVIDENCE-M${milestone}`;
    elements.paymentNotes.value = "";
  }

  function addAudit(action, previousState, newState, evidenceReference, note) {
    const idempotencyKey = `TEST-UI-${state.scenarioId}-${action}-${state.events.length + 1}`;
    const event = { event_id: `TEST-UI-EVT-${String(state.events.length + 1).padStart(3, "0")}`, timestamp: new Date().toISOString(), actor: "Lorenzo", action, previous_state: previousState, new_state: newState, document_reference: state.invoiceReference || "TEST-LWS-OFF-2026-0001", evidence_reference: evidenceReference || null, note: note || null };
    const appended = contract.appendIdempotent(state.events, state.processedKeys, idempotencyKey, event);
    state.events = appended.events;
    state.processedKeys = appended.processedKeys;
    if (evidenceReference) state.lastEvidence = evidenceReference;
    return appended.replay;
  }

  function setBadge(element, value) {
    element.textContent = value;
    element.className = "badge";
    if (["MATCHED", "AUTHORIZED", "RECORDED", "SENT"].includes(value)) element.classList.add("badge--green");
    if (["PARTIAL", "OVERPAYMENT", "UNVERIFIED", "NOT_READY"].includes(value)) element.classList.add("badge--amber");
    if (["REFERENCE_MISMATCH", "AMOUNT_MISMATCH", "DUPLICATE_EVIDENCE", "REJECTED", "BLOCKED"].includes(value)) element.classList.add("badge--red");
  }

  function renderDocuments() {
    elements.documentList.replaceChildren();
    documentNames.forEach((name, index) => {
      const item = document.createElement("li");
      const available = index < state.documentStage || Boolean(documentLinks[name] && index <= state.documentStage + 1);
      const label = documentLinks[name] ? document.createElement("a") : document.createElement("span");
      label.textContent = name;
      if (label instanceof HTMLAnchorElement) { label.href = documentLinks[name]; label.target = "_blank"; label.rel = "noopener"; label.setAttribute("aria-label", `${name} openen, non-production working document`); }
      const status = document.createElement("span"); status.textContent = available ? "Beschikbaar" : "Nog niet"; if (available) status.className = "available";
      item.append(label, status); elements.documentList.append(item);
    });
  }

  function renderTimeline() {
    elements.auditTimeline.replaceChildren();
    elements.auditEmpty.hidden = state.events.length > 0;
    [...state.events].reverse().forEach((event) => {
      const item = document.createElement("li");
      const time = document.createElement("time"); time.dateTime = event.timestamp; time.textContent = new Date(event.timestamp).toLocaleString("nl-BE", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
      const detail = document.createElement("div");
      const title = document.createElement("strong"); title.textContent = `${event.actor} · ${contract.ACTION_LABELS[event.action] || event.action}`;
      const transition = document.createElement("span"); transition.textContent = `${event.previous_state} → ${event.new_state}`;
      const refs = document.createElement("span"); refs.textContent = `Document: ${event.document_reference || "—"} · Evidence: ${event.evidence_reference || "—"}${event.note ? ` · ${event.note}` : ""}`;
      detail.append(title, transition, refs); item.append(time, detail); elements.auditTimeline.append(item);
    });
  }

  function render() {
    const visible = contract.visibleActions(state);
    elements.scenarioSelect.value = state.scenarioId;
    setBadge(elements.stateBadge, state.currentState);
    setBadge(elements.paymentStatus, state.paymentStatus);
    setBadge(elements.previewStatus, state.previewStatus);
    setBadge(elements.approvalStatus, state.finalApproval ? "RECORDED" : "NOT_RECORDED");
    setBadge(elements.transferStatus, state.transferStatus);
    setBadge(elements.matchBadge, state.paymentStatus);
    elements.matchResult.textContent = state.paymentStatus === "UNVERIFIED" ? "Nog niet gecontroleerd" : state.paymentStatus;
    elements.lastEvidence.textContent = state.lastEvidence || "—";
    elements.blockerType.textContent = state.blockerType;
    elements.blockerType.className = `badge ${state.blockerType.includes("COMMERCIAL") ? "badge--red" : "badge--amber"}`;
    elements.commercialBlocker.textContent = state.blocker || "Geen commerciële blocker.";
    const nextAction = visible[0] || null;
    elements["next-action-title"].textContent = nextAction ? contract.ACTION_LABELS[nextAction] : "Geen actie beschikbaar";
    elements.nextActionDescription.textContent = descriptions[nextAction] || "Deze synthetische workflow is voltooid of vereist review.";
    elements.primaryAction.hidden = !nextAction;
    elements.primaryAction.textContent = nextAction ? contract.ACTION_LABELS[nextAction] : "";
    elements.primaryAction.dataset.action = nextAction || "";
    elements.paymentPanel.hidden = !paymentAction(state.nextAction) && !state.currentState.includes("PAYMENT_PENDING");
    elements.expectedAmount.value = euro(state.expectedAmountMinor);
    renderDocuments(); renderTimeline(); persist();
  }

  function paymentInput() {
    return { bank: contract.APPROVED_BANK.bank, iban: contract.APPROVED_BANK.iban, bic: contract.APPROVED_BANK.bic, projectReference: "TEST-PRJ-0001", customerReference: "TEST-CUS-0001", invoiceReference: state.invoiceReference, expectedInvoiceReference: state.invoiceReference, expectedAmountMinor: state.expectedAmountMinor, authorityAmountMinor: state.expectedAmountMinor, receivedAmountMinor: Math.round(Number(elements.receivedAmount.value) * 100), transactionReference: elements.transactionReference.value.trim(), evidenceReference: elements.evidenceReference.value.trim() };
  }

  function reconcile(action) {
    if (!elements.paymentForm.reportValidity()) return;
    const input = paymentInput();
    const result = contract.classifyPayment(input, new Set(state.usedReferences));
    const previousState = state.currentState;
    state.paymentStatus = result;
    addAudit(action, previousState, previousState, input.evidenceReference, elements.paymentNotes.value.trim());
    if (result === "MATCHED") {
      state.usedReferences.push(input.transactionReference, input.evidenceReference);
      state.nextAction = contract.NEXT_AFTER_ACTION[action];
      state.blockerType = "OPERATOR ACTION REQUIRED";
      state.blocker = "Expliciete betalingsbevestiging vereist.";
      elements.actionMessage.textContent = "Transactie MATCHED. Betalingsbevestiging is nu beschikbaar.";
    } else {
      state.blockerType = "COMMERCIAL BLOCKER";
      state.blocker = `Payment mismatch: ${result}. Operatorreview vereist.`;
      elements.actionMessage.textContent = `${result}: betaling blijft geblokkeerd.`;
    }
    render();
  }

  function applyAction(action) {
    const previousState = state.currentState;
    const newState = contract.STATE_AFTER_ACTION[action] || previousState;
    const evidence = action.includes("PAYMENT") ? elements.evidenceReference.value.trim() : `TEST-EVIDENCE-${action}`;
    addAudit(action, previousState, newState, evidence, null);
    state.currentState = newState;
    state.nextAction = contract.NEXT_AFTER_ACTION[action];
    if (action.startsWith("CONFIRM_")) state.paymentStatus = "MATCHED";
    if (action === "MARK_PREVIEW_READY") { state.previewStatus = "READY"; state.blocker = "Preview moet nog veilig naar de klant worden verzonden."; }
    if (action === "SEND_PREVIEW") { state.previewStatus = "SENT"; state.documentStage = Math.max(state.documentStage, 7); }
    if (action === "RECORD_FINAL_APPROVAL") state.finalApproval = true;
    if (action === "AUTHORIZE_FINAL_TRANSFER") state.transferStatus = "AUTHORIZED";
    if (action === "ARCHIVE") { state.blockerType = "COMMERCIAL"; state.blocker = "Workflow voltooid en append-only gearchiveerd."; }
    else if (state.nextAction) { state.blockerType = "OPERATOR ACTION REQUIRED"; state.blocker = `${contract.ACTION_LABELS[state.nextAction]} vereist.`; }
    elements.actionMessage.textContent = `${contract.ACTION_LABELS[action]} geregistreerd.`;
    render();
  }

  function requestAction(action) {
    if (["RECONCILE_M1", "RECONCILE_M2", "RECONCILE_FINAL"].includes(action)) { reconcile(action); return; }
    if (contract.DANGEROUS_ACTIONS.includes(action)) {
      pendingDangerousAction = action;
      elements.confirmationTitle.textContent = contract.ACTION_LABELS[action];
      elements.confirmationText.textContent = dangerousText[action];
      elements.confirmAction.textContent = contract.ACTION_LABELS[action];
      elements.confirmationDialog.showModal();
      return;
    }
    applyAction(action);
  }

  elements.primaryAction.addEventListener("click", () => {
    if (actionLocked) return;
    actionLocked = true;
    const action = elements.primaryAction.dataset.action;
    elements.primaryAction.disabled = true;
    try { requestAction(action); } finally {
      window.setTimeout(() => {
        actionLocked = false;
        elements.primaryAction.disabled = false;
      }, 0);
    }
  });
  elements.confirmationDialog.addEventListener("close", () => { if (elements.confirmationDialog.returnValue === "confirm" && pendingDangerousAction) applyAction(pendingDangerousAction); pendingDangerousAction = null; });
  elements.scenarioSelect.addEventListener("change", () => { state = contract.createScenario(elements.scenarioSelect.value); localStorage.removeItem(storageKey); elements.actionMessage.textContent = ""; setPaymentDefaults(); render(); });

  window.LWSPrototype = Object.freeze({
    getState: () => JSON.parse(JSON.stringify(state)),
    reset: (scenarioId = "m1") => { state = contract.createScenario(scenarioId); localStorage.removeItem(storageKey); setPaymentDefaults(); render(); },
    runAction: requestAction,
    storageKey,
  });
  setPaymentDefaults();
  render();
})();