const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const FINANCE_TABS = new Set(["overview", "websites", "sdf", "workforce", "expenses", "inbox", "owner"]);
const AUTHORIZATION_FAILURE = /AUTHENTICATION_REQUIRED|HUMAN_JWT_REQUIRED|OPERATOR_NOT_ACTIVE|OWNER_REQUIRED|WORKSPACE_MODULE_NOT_AUTHORIZED/;
const CURRENCY = /^[A-Z]{3}$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const DOCUMENT_INBOX_STATUSES = new Set(["RECEIVED", "REVIEW_REQUIRED", "APPROVED", "PROCESSED", "REJECTED"]);
const DOCUMENT_INBOX_EXTRACTION_STATUSES = new Set(["NOT_RECORDED", "SUCCEEDED", "PARTIAL", "ERROR"]);
const WEBSITE_UNAVAILABLE_FLAGS = ["invoice_projection_available", "outstanding_projection_available", "overdue_projection_available", "upcoming_projection_available", "recurring_amount_projection_available", "bank_actuals_projection_available"];
const SDF_UNAVAILABLE_FLAGS = ["expected_payment_available", "payment_evidence_available", "confirmed_received_available", "outstanding_projection_available", "overdue_projection_available", "upcoming_projection_available", "recurring_amount_projection_available"];
const EXPENSE_UNAVAILABLE_FLAGS = ["payment_state_available", "paid_amount_available", "paid_date_available", "confirmed_cash_out_available", "outstanding_available", "overdue_available", "upcoming_available", "vat_available", "deductible_vat_available", "bank_actuals_available", "recurring_available"];
const FINANCE_DIALOG_IDS = ["businessExpenseDialog", "supplierDocumentDialog", "documentInboxUploadDialog", "documentInboxDialog"];

function financeTab(url) {
  const value = new URL(url, "https://operator.invalid").searchParams.get("financeTab") || "overview";
  return FINANCE_TABS.has(value) ? value : "overview";
}

function authorizationFailure(error) {
  return error?.code === "42501" || AUTHORIZATION_FAILURE.test(String(error?.message || ""));
}

function money(minor, currency) {
  if (!Number.isSafeInteger(minor) || minor < 0 || !/^[A-Z]{3}$/.test(currency || "")) throw new Error("INVALID_FINANCE_MONEY");
  return new Intl.NumberFormat("nl-BE", { style: "currency", currency }).format(minor / 100);
}

function exactObject(value) {
  return value && typeof value === "object" && !Array.isArray(value);
}

function validMoney(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

function websitePortfolio(value) {
  if (!exactObject(value) || value.scope !== "website" || !Array.isArray(value.currency_totals) || !Array.isArray(value.projects)
      || value.bank_actuals !== null || WEBSITE_UNAVAILABLE_FLAGS.some((flag)=>value[flag] !== false)) {
    throw new Error("INVALID_WEBSITE_FINANCE_PORTFOLIO");
  }
  for (const total of value.currency_totals) if (!CURRENCY.test(total?.currency || "") || !validMoney(total?.total_commitment_minor)
      || !validMoney(total?.total_expected_minor) || !validMoney(total?.total_confirmed_received_minor)) throw new Error("INVALID_WEBSITE_FINANCE_PORTFOLIO");
  for (const item of value.projects) if (!UUID.test(String(item?.project_id || "")) || item.request_kind !== "website"
      || !CURRENCY.test(item?.currency || "") || !validMoney(item?.accepted_total_minor) || !validMoney(item?.expected_minor)
      || !validMoney(item?.confirmed_received_minor) || !Array.isArray(item?.milestones)) throw new Error("INVALID_WEBSITE_FINANCE_PORTFOLIO");
  return value;
}

function sdfPortfolio(value) {
  if (!exactObject(value) || value.scope !== "sdf" || !Array.isArray(value.currency_totals) || !Array.isArray(value.projects)
      || !Number.isSafeInteger(value.project_count) || value.project_count < 0 || value.project_count !== value.projects.length
      || value.invoice_projection_available !== true || SDF_UNAVAILABLE_FLAGS.some((flag)=>value[flag] !== false)) {
    throw new Error("INVALID_SDF_FINANCE_PORTFOLIO");
  }
  for (const total of value.currency_totals) if (!CURRENCY.test(total?.currency || "") || !validMoney(total?.commitment_minor)
      || !validMoney(total?.m1_obligation_minor) || !validMoney(total?.issued_invoice_minor)) throw new Error("INVALID_SDF_FINANCE_PORTFOLIO");
  for (const item of value.projects) if (!UUID.test(String(item?.quote_request_id || "")) || !CURRENCY.test(item?.currency || "")
      || !validMoney(item?.commitment_minor) || !validMoney(item?.m1_obligation_minor)) throw new Error("INVALID_SDF_FINANCE_PORTFOLIO");
  return value;
}

function expensePortfolio(value) {
  if (!exactObject(value) || value.scope !== "business_expenses" || !Array.isArray(value.currency_totals)
      || !Array.isArray(value.expenses) || !Number.isSafeInteger(value.expense_count) || value.expense_count < 0
      || value.expense_count !== value.expenses.length || !exactObject(value.availability)
      || EXPENSE_UNAVAILABLE_FLAGS.some((flag)=>value.availability[flag] !== false) || value.bank_actuals !== null) {
    throw new Error("INVALID_BUSINESS_EXPENSE_FINANCE_PORTFOLIO");
  }
  for (const total of value.currency_totals) if (!CURRENCY.test(total?.currency || "") || !validMoney(total?.active_expense_minor)) throw new Error("INVALID_BUSINESS_EXPENSE_FINANCE_PORTFOLIO");
  for (const item of value.expenses) if (!UUID.test(String(item?.id || "")) || typeof item?.supplier_name !== "string"
      || typeof item?.description !== "string" || !validMoney(item?.amount_minor) || !CURRENCY.test(item?.currency || "")
      || !DATE.test(item?.expense_date || "") || !["RECORDED", "CANCELLED"].includes(item?.status)
      || !Number.isSafeInteger(item?.document_count) || item.document_count < 0 || !Array.isArray(item?.relation_types)) throw new Error("INVALID_BUSINESS_EXPENSE_FINANCE_PORTFOLIO");
  return value;
}

function inboxPortfolio(value) {
  if (!exactObject(value) || value.scope !== "document_inbox" || !Array.isArray(value.items)) throw new Error("INVALID_DOCUMENT_INBOX_RESPONSE");
  for (const item of value.items) if (!UUID.test(String(item?.id || "")) || !DOCUMENT_INBOX_STATUSES.has(item?.lifecycle_status)
      || !Number.isSafeInteger(item?.revision) || item.revision < 0 || !Array.isArray(item?.warnings)
      || !DOCUMENT_INBOX_EXTRACTION_STATUSES.has(item?.extraction_status) || !exactObject(item?.extraction_candidates)
      || !["production", "internal_e2e"].includes(item?.record_classification)) throw new Error("INVALID_DOCUMENT_INBOX_RESPONSE");
  return value;
}

function mutationResponse(value, message = "INVALID_FINANCE_MUTATION_RESPONSE") {
  if (!exactObject(value) || !UUID.test(String(value.id || "")) || !DOCUMENT_INBOX_STATUSES.has(value.status)
      || !Number.isSafeInteger(value.revision) || value.revision < 1) throw new Error(message);
  return value;
}

const FINANCE_COMMANDS = new Set([
  "update_document_inbox_proposal_v1",
  "confirm_document_inbox_values_v1",
  "approve_document_inbox_item_v1",
  "reject_document_inbox_item_v1",
  "process_document_inbox_item_v1",
]);
const DOCUMENT_TYPES = new Set(["INVOICE", "CREDIT_NOTE", "RECEIPT", "CONTRACT", "OTHER"]);
const EXPENSE_CATEGORIES = new Set(["software", "hosting", "telecom", "accounting", "hardware", "marketing", "insurance", "education", "office", "transport", "other"]);

function boundedText(value, maximum, required = false) {
  const result = String(value ?? "").trim();
  if ((required && !result) || result.length > maximum) throw new Error("INVALID_FINANCE_VALUES");
  return result;
}

function amountMinor(value) {
  const normalized = String(value ?? "").trim().replace(",", ".");
  if (!/^\d+(?:\.\d{1,2})?$/.test(normalized)) throw new Error("INVALID_FINANCE_AMOUNT");
  const [units, decimals = ""] = normalized.split(".");
  const result = (BigInt(units) * 100n) + BigInt(decimals.padEnd(2, "0"));
  if (result < 1n || result > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("INVALID_FINANCE_AMOUNT");
  return Number(result);
}

function inboxValues(values) {
  const request = {
    p_supplier_name: boundedText(values?.supplier_name, 200, true),
    p_document_type: boundedText(values?.document_type, 40, true),
    p_document_reference: boundedText(values?.document_reference, 200) || null,
    p_document_date: String(values?.document_date || "") || null,
    p_amount_minor: amountMinor(values?.amount),
    p_currency: String(values?.currency || ""),
    p_description: boundedText(values?.description, 1000, true),
    p_category: boundedText(values?.category, 80, true),
    p_expense_date: String(values?.expense_date || ""),
    p_relation_type: boundedText(values?.relation_type, 40, true),
  };
  if (!DOCUMENT_TYPES.has(request.p_document_type) || !DOCUMENT_TYPES.has(request.p_relation_type)
      || !EXPENSE_CATEGORIES.has(request.p_category) || request.p_currency !== "EUR"
      || (request.p_document_date && !/^\d{4}-\d{2}-\d{2}$/.test(request.p_document_date))
      || !/^\d{4}-\d{2}-\d{2}$/.test(request.p_expense_date)) throw new Error("INVALID_FINANCE_VALUES");
  return request;
}

function initialInboxValues(item) {
  const value = (field)=>item[`confirmed_${field}`] ?? item[`proposed_${field}`] ?? "";
  const minor = value("amount_minor");
  return {
    supplier_name: value("supplier_name"),
    document_type: value("document_type"),
    document_reference: value("document_reference"),
    document_date: value("document_date"),
    expense_date: value("expense_date"),
    amount: Number.isSafeInteger(minor) ? (minor / 100).toFixed(2).replace(".", ",") : "",
    currency: value("currency") || "EUR",
    description: value("description"),
    category: value("category"),
    relation_type: value("relation_type"),
  };
}

function validFile(file) {
  return file && ["application/pdf", "image/png", "image/jpeg"].includes(file.type)
    && Number.isSafeInteger(file.size) && file.size > 0 && file.size <= 10 * 1024 * 1024
    && boundedText(file.name, 200, true) && !/[\\/]/.test(file.name);
}

export function createOperatorFinanceWriteAuthority(client, { onAuthorizationFailure = ()=>{} } = {}) {
  if (!client?.rpc || !client?.functions?.invoke) throw new TypeError("FINANCE_WRITE_CLIENT_REQUIRED");
  let disposed = false;
  async function checked(result) {
    if (disposed) throw new Error("FINANCE_DISPOSED");
    if (result.error) {
      if (authorizationFailure(result.error)) onAuthorizationFailure(result.error);
      throw result.error;
    }
    return result.data;
  }
  async function rpc(name, request) {
    return checked(await client.rpc(name, request));
  }
  async function upload(file) {
    if (!validFile(file)) throw new Error("INVALID_FINANCE_FILE");
    const data = await checked(await client.functions.invoke("supplier-document-upload", {
      method: "POST",
      headers: { "Content-Type": file.type },
      body: file,
    }));
    if (!exactObject(data) || data.bucket !== "supplier-documents"
      || typeof data.object_path !== "string" || !/^documents\/[0-9a-f]{64}\.(?:pdf|png|jpg)$/.test(data.object_path)
      || typeof data.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(data.sha256)
        || data.mime_type !== file.type || data.byte_count !== file.size) throw new Error("INVALID_FINANCE_UPLOAD_RESPONSE");
    return data;
  }
  return {
    async createExpense(values) {
      const request = {
        p_supplier_name: boundedText(values?.supplier_name, 200, true),
        p_description: boundedText(values?.description, 1000, true),
        p_category: boundedText(values?.category, 80, true),
        p_amount_minor: amountMinor(values?.amount),
        p_currency: "EUR",
        p_expense_date: String(values?.expense_date || ""),
      };
      if (!/^\d{4}-\d{2}-\d{2}$/.test(request.p_expense_date)) throw new Error("INVALID_FINANCE_VALUES");
      const id = await rpc("create_business_expense_v1", request);
      if (!UUID.test(String(id || ""))) throw new Error("INVALID_BUSINESS_EXPENSE_ID");
      return id;
    },
    async attachExpenseDocument(expenseId, values, file) {
      if (!UUID.test(String(expenseId || ""))) throw new Error("INVALID_FINANCE_EXPENSE");
      const authority = await upload(file);
      const documentId = await rpc("create_supplier_document_v1", {
        p_document_type: boundedText(values?.document_type, 40, true),
        p_supplier_name: boundedText(values?.supplier_name, 200, true),
        p_document_reference: boundedText(values?.document_reference, 200) || null,
        p_document_date: String(values?.document_date || "") || null,
        p_original_file_name: file.name,
        p_mime_type: authority.mime_type,
        p_byte_count: authority.byte_count,
        p_sha256: authority.sha256,
      });
      if (!UUID.test(String(documentId || ""))) throw new Error("INVALID_SUPPLIER_DOCUMENT_ID");
      const linkId = await rpc("link_business_expense_document_v1", {
        p_business_expense_id: expenseId,
        p_supplier_document_id: documentId,
        p_relation_type: boundedText(values?.relation_type, 40, true),
      });
      if (!UUID.test(String(linkId || ""))) throw new Error("INVALID_BUSINESS_EXPENSE_DOCUMENT_LINK_ID");
      return linkId;
    },
    async receiveInboxDocument(file) {
      const authority = await upload(file);
      const result = await rpc("receive_document_inbox_item_v1", {
        p_sha256: authority.sha256,
        p_original_file_name: file.name,
        p_mime_type: authority.mime_type,
        p_byte_count: authority.byte_count,
        p_source_type: "MANUAL_UPLOAD",
        p_source_instance: null,
        p_external_id: null,
        p_record_classification: "production",
      });
      mutationResponse(result, "INVALID_DOCUMENT_INBOX_RECEIVE_RESPONSE");
      if (typeof result.replayed !== "boolean") throw new Error("INVALID_DOCUMENT_INBOX_RECEIVE_RESPONSE");
      return result;
    },
    async extractInboxDocument(item) {
      if (!UUID.test(String(item?.id || "")) || !Number.isSafeInteger(item?.revision)) throw new Error("INVALID_DOCUMENT_INBOX_ITEM");
      const result = await checked(await client.functions.invoke("document-inbox-extract", {
        body: { document_inbox_item_id: item.id, expected_revision: item.revision },
      }));
      mutationResponse(result, "INVALID_DOCUMENT_INBOX_EXTRACTION_RESPONSE");
      if (result.ok !== true || result.code !== "DOCUMENT_INBOX_EXTRACTION_RECORDED"
          || !DOCUMENT_INBOX_EXTRACTION_STATUSES.has(result.extraction_status) || !exactObject(result.extraction_candidates)) {
        throw new Error("INVALID_DOCUMENT_INBOX_EXTRACTION_RESPONSE");
      }
      return result;
    },
    command(name, item, values = {}) {
      if (!FINANCE_COMMANDS.has(name) || !UUID.test(String(item?.id || "")) || !Number.isSafeInteger(item?.revision)) {
        throw new Error("FINANCE_COMMAND_NOT_ALLOWED");
      }
      const request = { p_inbox_item_id: item.id, p_expected_revision: item.revision };
      if (name === "approve_document_inbox_item_v1") request.p_acknowledge_warnings = Boolean(values.acknowledge_warnings);
      else if (name === "reject_document_inbox_item_v1") request.p_reason = boundedText(values.reason, 500) || null;
      else if (["update_document_inbox_proposal_v1", "confirm_document_inbox_values_v1"].includes(name)) {
        Object.assign(request, inboxValues(values));
        if (name === "update_document_inbox_proposal_v1") request.p_warnings = Array.isArray(item.warnings) ? item.warnings : [];
      }
      return rpc(name, request).then((result)=>mutationResponse(result));
    },
    dispose() { disposed = true; },
  };
}

function appendMetric(root, target, label, value) {
  const group = root.createElement("div");
  const term = root.createElement("dt");
  const detail = root.createElement("dd");
  term.textContent = label;
  detail.textContent = value;
  group.append(term, detail);
  target.append(group);
}

function setText(root, id, value) {
  const node = root.getElementById(id);
  if (node) node.textContent = value;
}

export function createOperatorFinanceController({ loadTab, onChange = ()=>{} }) {
  let activeTab = "overview";
  let generation = 0;
  let disposed = false;
  let loading = false;
  let error = null;
  const loaded = new Set(["overview", "workforce", "owner"]);
  const state = ()=>({ activeTab, loading, error, loaded: new Set(loaded) });
  const notify = ()=>{ if (!disposed) onChange(state()); };

  async function activate(tab, { force = false } = {}) {
    if (disposed || !FINANCE_TABS.has(tab)) return false;
    activeTab = tab;
    error = null;
    const requestGeneration = ++generation;
    notify();
    if (loaded.has(tab) && !force) return true;
    loading = true;
    notify();
    try {
      await loadTab(tab, ()=>!disposed && requestGeneration === generation && activeTab === tab);
      if (disposed || requestGeneration !== generation) return false;
      loaded.add(tab);
      loading = false;
      notify();
      return true;
    } catch (caught) {
      if (disposed || requestGeneration !== generation) return false;
      loading = false;
      error = caught;
      notify();
      return false;
    }
  }

  return {
    get state() { return state(); },
    activate,
    refresh: ()=>activate(activeTab, { force: true }),
    dispose() {
      if (disposed) return;
      disposed = true;
      generation += 1;
      loaded.clear();
      error = null;
      loading = false;
    },
  };
}

export function initializeOperatorFinance(root, client, identity, { onAuthorizationFailure = ()=>{}, navigate = null } = {}) {
  if (!root?.getElementById || !client?.rpc || !client?.functions?.invoke || identity?.role !== "owner") throw new Error("FINANCE_MANAGEMENT_OWNER_REQUIRED");
  const shell = root.querySelector('[data-module-panel="finance"]') || root.querySelector(".module-shell--finance");
  if (!shell) throw new Error("OPERATOR_FINANCE_TEMPLATE_MISSING");
  if (shell.operatorFinanceController) return shell.operatorFinanceController;
  const listeners = new AbortController();
  let disposed = false;
  let controller;
  let selectedExpense = null;
  let selectedInboxItem = null;
  const writes = createOperatorFinanceWriteAuthority(client, { onAuthorizationFailure });

  function present(state) {
    if (disposed) return;
    for (const link of shell.querySelectorAll("[data-finance-tab]")) link.setAttribute("aria-current", String(link.dataset.financeTab === state.activeTab ? "page" : "false"));
    for (const panel of shell.querySelectorAll("[data-finance-tab-panel]")) panel.hidden = panel.dataset.financeTabPanel !== state.activeTab;
  }

  async function rpc(name, args = {}) {
    const response = await client.rpc(name, args);
    if (response.error) {
      if (authorizationFailure(response.error)) onAuthorizationFailure(response.error);
      throw response.error;
    }
    return response.data;
  }

  async function loadWebsites(isCurrent) {
    const value = websitePortfolio(await rpc("get_website_finance_portfolio_v1"));
    if (!isCurrent()) return;
    const totals = root.getElementById("financeCurrencyTotals");
    const projects = root.getElementById("financeProjectList");
    totals?.replaceChildren();
    projects?.replaceChildren();
    for (const total of value.currency_totals) {
      const section = root.createElement("section");
      const heading = root.createElement("h3");
      const metrics = root.createElement("dl");
      heading.textContent = total.currency;
      appendMetric(root, metrics, "Commerciële waarde", money(total.total_commitment_minor, total.currency));
      appendMetric(root, metrics, "Verwacht", money(total.total_expected_minor, total.currency));
      appendMetric(root, metrics, "Bevestigd ontvangen", money(total.total_confirmed_received_minor, total.currency));
      section.append(heading, metrics);
      totals?.append(section);
    }
    for (const project of value.projects) {
      const item = root.createElement("li");
      const heading = root.createElement("strong");
      const metrics = root.createElement("dl");
      heading.textContent = project.application_reference || project.project_id;
      appendMetric(root, metrics, "Commerciële waarde", money(project.accepted_total_minor, project.currency));
      appendMetric(root, metrics, "Verwacht", money(project.expected_minor, project.currency));
      appendMetric(root, metrics, "Bevestigd ontvangen", money(project.confirmed_received_minor, project.currency));
      item.append(heading, metrics);
      projects?.append(item);
    }
    setText(root, "financeWebsiteCount", `${value.projects.length} ${value.projects.length === 1 ? "project" : "projecten"}`);
    setText(root, "financeWebsiteStatus", value.projects.length ? "Websiteportfolio beschikbaar." : "");
    const content = root.getElementById("financeWebsiteContent");
    if (content) content.hidden = false;
    const empty = root.getElementById("financeProjectEmpty");
    if (empty) empty.hidden = value.projects.length !== 0;
  }

  async function loadSdf(isCurrent) {
    const value = sdfPortfolio(await rpc("get_sdf_finance_portfolio_v1"));
    if (!isCurrent()) return;
    const totals = root.getElementById("financeSdfCurrencyTotals");
    const projects = root.getElementById("financeSdfProjectList");
    totals?.replaceChildren();
    projects?.replaceChildren();
    for (const total of value.currency_totals) {
      const section = root.createElement("section");
      const heading = root.createElement("h3");
      const metrics = root.createElement("dl");
      heading.textContent = total.currency;
      appendMetric(root, metrics, "Commerciële waarde", money(total.commitment_minor, total.currency));
      appendMetric(root, metrics, "M1-verplichting", money(total.m1_obligation_minor, total.currency));
      appendMetric(root, metrics, "Uitgegeven facturen", money(total.issued_invoice_minor, total.currency));
      section.append(heading, metrics);
      totals?.append(section);
    }
    for (const project of value.projects) {
      const item = root.createElement("li");
      const heading = root.createElement("strong");
      const metrics = root.createElement("dl");
      heading.textContent = project.application_reference || project.quote_request_id;
      appendMetric(root, metrics, "Commerciële waarde", money(project.commitment_minor, project.currency));
      appendMetric(root, metrics, "M1-verplichting", money(project.m1_obligation_minor, project.currency));
      appendMetric(root, metrics, "Factuurstatus", project.invoice_issuance_state || project.invoice_candidate_state || "Niet voorbereid");
      item.append(heading, metrics);
      projects?.append(item);
    }
    setText(root, "financeSdfCount", `${value.project_count} ${value.project_count === 1 ? "dossier" : "dossiers"}`);
    setText(root, "financeSdfStatus", value.project_count ? "SDF-portfolio beschikbaar." : "");
    const content = root.getElementById("financeSdfContent");
    if (content) content.hidden = false;
    const empty = root.getElementById("financeSdfProjectEmpty");
    if (empty) empty.hidden = value.project_count !== 0;
  }

  async function loadExpenses(isCurrent) {
    const value = expensePortfolio(await rpc("get_business_expense_portfolio_v1"));
    if (!isCurrent()) return;
    const totals = root.getElementById("financeExpenseCurrencyTotals");
    const expenses = root.getElementById("financeExpenseList");
    totals?.replaceChildren();
    expenses?.replaceChildren();
    for (const total of value.currency_totals) {
      const metrics = root.createElement("dl");
      appendMetric(root, metrics, `${total.currency} geregistreerd`, money(total.active_expense_minor, total.currency));
      totals?.append(metrics);
    }
    for (const expense of value.expenses) {
      const item = root.createElement("li");
      const heading = root.createElement("strong");
      const metrics = root.createElement("dl");
      heading.textContent = expense.supplier_name;
      appendMetric(root, metrics, "Omschrijving", expense.description || "Geen omschrijving");
      appendMetric(root, metrics, "Bedrag", money(expense.amount_minor, expense.currency));
      appendMetric(root, metrics, "Datum", expense.expense_date);
      const attach = root.createElement("button");
      attach.type = "button";
      attach.className = "secondary-action";
      attach.textContent = "Document toevoegen";
      attach.dataset.supplierDocumentExpenseId = expense.id;
      attach.addEventListener("click", ()=>{
        selectedExpense = expense;
        const form = root.getElementById("supplierDocumentForm");
        form?.reset();
        setText(root, "supplierDocumentExpense", `${expense.supplier_name} · ${expense.description || "Geen omschrijving"}`);
        const supplier = root.getElementById("supplierDocumentSupplier");
        if (supplier) supplier.value = expense.supplier_name;
        root.getElementById("supplierDocumentDialog")?.showModal();
      }, { signal: listeners.signal });
      item.append(heading, metrics, attach);
      expenses?.append(item);
    }
    setText(root, "financeExpenseCount", `${value.expense_count} ${value.expense_count === 1 ? "kost" : "kosten"}`);
    setText(root, "financeExpenseStatus", value.expense_count ? "Bedrijfskosten beschikbaar." : "");
    const content = root.getElementById("financeExpenseContent");
    if (content) content.hidden = false;
    const empty = root.getElementById("financeExpenseEmpty");
    if (empty) empty.hidden = value.expense_count !== 0;
  }

  async function loadInbox(isCurrent) {
    const value = inboxPortfolio(await rpc("get_document_inbox_v1", { p_lifecycle_status: null, p_record_classification: "production" }));
    if (!isCurrent()) return;
    const list = root.getElementById("documentInboxList");
    list?.replaceChildren();
    for (const documentItem of value.items) {
      const item = root.createElement("li");
      const open = root.createElement("button");
      const heading = root.createElement("strong");
      const detail = root.createElement("p");
      open.type = "button";
      heading.textContent = documentItem.confirmed_supplier_name || documentItem.proposed_supplier_name || documentItem.original_filename || "Document";
      detail.textContent = `${documentItem.lifecycle_status.replaceAll("_", " ")} · ${documentItem.document_reference || documentItem.id}`;
      open.append(heading, detail);
      open.addEventListener("click", ()=>{
        selectedInboxItem = documentItem;
        const form = root.getElementById("documentInboxConfirmedForm");
        form?.reset();
        for (const [name, fieldValue] of Object.entries(initialInboxValues(documentItem))) {
          const field = form?.elements.namedItem(name);
          if (field) field.value = fieldValue;
        }
        setText(root, "documentInboxDialogFile", documentItem.original_filename || documentItem.document_reference || documentItem.id);
        setText(root, "documentInboxDialogStatus", documentItem.lifecycle_status.replaceAll("_", " "));
        for (const [id, visible] of [
          ["documentInboxExtract", ["RECEIVED", "REVIEW_REQUIRED"].includes(documentItem.lifecycle_status)],
          ["documentInboxSaveProposal", ["RECEIVED", "REVIEW_REQUIRED"].includes(documentItem.lifecycle_status)],
          ["documentInboxSaveConfirmed", documentItem.lifecycle_status === "REVIEW_REQUIRED"],
          ["documentInboxApprove", documentItem.lifecycle_status === "REVIEW_REQUIRED"],
          ["documentInboxReject", ["RECEIVED", "REVIEW_REQUIRED"].includes(documentItem.lifecycle_status)],
          ["documentInboxProcess", documentItem.lifecycle_status === "APPROVED"],
        ]) {
          const action = root.getElementById(id);
          if (action) action.hidden = !visible;
        }
        root.getElementById("documentInboxDialog")?.showModal();
      }, { signal: listeners.signal });
      item.append(open);
      list?.append(item);
    }
    setText(root, "documentInboxCount", `${value.items.length} ${value.items.length === 1 ? "document" : "documenten"}`);
    setText(root, "documentInboxStatus", value.items.length ? "Documenten beschikbaar." : "");
    const empty = root.getElementById("documentInboxEmpty");
    if (empty) empty.hidden = value.items.length !== 0;
  }

  controller = createOperatorFinanceController({
    loadTab: async (tab, isCurrent)=>{
      if (tab === "websites") return loadWebsites(isCurrent);
      if (tab === "sdf") return loadSdf(isCurrent);
      if (tab === "expenses") return loadExpenses(isCurrent);
      if (tab === "inbox") return loadInbox(isCurrent);
    },
    onChange: present,
  });

  const expenseForm = root.getElementById("businessExpenseForm");
  if (expenseForm) {
    let trigger = root.getElementById("businessExpenseCreate");
    if (!trigger) {
      trigger = root.createElement("button");
      trigger.id = "businessExpenseCreate";
      trigger.type = "button";
      trigger.className = "primary-action primary-action--compact";
      trigger.textContent = "Nieuwe bedrijfskost";
      root.getElementById("financeExpensesTitle")?.closest(".finance-section-heading")?.append(trigger);
    }
    trigger.addEventListener("click", ()=>root.getElementById("businessExpenseDialog")?.showModal(), { signal: listeners.signal });
    root.getElementById("businessExpenseCancel")?.addEventListener("click", ()=>root.getElementById("businessExpenseDialog")?.close(), { signal: listeners.signal });
    expenseForm.addEventListener("submit", async (event)=>{
      event.preventDefault();
      const submit = root.getElementById("businessExpenseSubmit");
      if (submit) submit.disabled = true;
      try {
        await writes.createExpense(Object.fromEntries(new FormData(expenseForm)));
        expenseForm.reset();
        root.getElementById("businessExpenseDialog")?.close();
        await controller.activate("expenses", { force: true });
      } catch {
        setText(root, "businessExpenseFormStatus", "Bedrijfskost kon niet worden opgeslagen.");
      } finally {
        if (submit) submit.disabled = false;
      }
    }, { signal: listeners.signal });
  }

  const supplierForm = root.getElementById("supplierDocumentForm");
  supplierForm?.addEventListener("submit", async (event)=>{
    event.preventDefault();
    const file = root.getElementById("supplierDocumentFile")?.files?.[0];
    if (!selectedExpense || !file) return;
    const submit = root.getElementById("supplierDocumentSubmit");
    if (submit) submit.disabled = true;
    try {
      await writes.attachExpenseDocument(selectedExpense.id, Object.fromEntries(new FormData(supplierForm)), file);
      supplierForm.reset();
      selectedExpense = null;
      root.getElementById("supplierDocumentDialog")?.close();
      await controller.activate("expenses", { force: true });
    } catch {
      setText(root, "supplierDocumentFormStatus", "Document kon niet veilig worden opgeslagen en gekoppeld.");
    } finally {
      if (submit) submit.disabled = false;
    }
  }, { signal: listeners.signal });
  root.getElementById("supplierDocumentCancel")?.addEventListener("click", ()=>{
    selectedExpense = null;
    root.getElementById("supplierDocumentDialog")?.close();
  }, { signal: listeners.signal });

  const inboxUploadForm = root.getElementById("documentInboxUploadForm");
  root.getElementById("documentInboxUploadOpen")?.addEventListener("click", ()=>root.getElementById("documentInboxUploadDialog")?.showModal(), { signal: listeners.signal });
  root.getElementById("documentInboxUploadCancel")?.addEventListener("click", ()=>root.getElementById("documentInboxUploadDialog")?.close(), { signal: listeners.signal });
  inboxUploadForm?.addEventListener("submit", async (event)=>{
    event.preventDefault();
    const file = root.getElementById("documentInboxUploadFile")?.files?.[0];
    if (!file) return;
    try {
      await writes.receiveInboxDocument(file);
      inboxUploadForm.reset();
      root.getElementById("documentInboxUploadDialog")?.close();
      await controller.activate("inbox", { force: true });
    } catch {
      setText(root, "documentInboxUploadStatus", "Document kon niet veilig worden ontvangen.");
    }
  }, { signal: listeners.signal });

  const inboxCommands = new Map([
    ["documentInboxSaveProposal", "update_document_inbox_proposal_v1"],
    ["documentInboxSaveConfirmed", "confirm_document_inbox_values_v1"],
    ["documentInboxApprove", "approve_document_inbox_item_v1"],
    ["documentInboxReject", "reject_document_inbox_item_v1"],
    ["documentInboxProcess", "process_document_inbox_item_v1"],
  ]);
  for (const [id, command] of inboxCommands) root.getElementById(id)?.addEventListener("click", async ()=>{
    if (!selectedInboxItem) return;
    const form = root.getElementById("documentInboxConfirmedForm");
    if (["update_document_inbox_proposal_v1", "confirm_document_inbox_values_v1"].includes(command) && !form?.reportValidity()) return;
    const values = form ? Object.fromEntries(new FormData(form)) : {};
    values.acknowledge_warnings = root.getElementById("documentInboxAcknowledgeWarnings")?.checked;
    try {
      await writes.command(command, selectedInboxItem, values);
      root.getElementById("documentInboxDialog")?.close();
      selectedInboxItem = null;
      await controller.activate("inbox", { force: true });
    } catch {
      setText(root, "documentInboxActionStatus", "Actie kon niet veilig worden uitgevoerd. Vernieuw de actuele status.");
    }
  }, { signal: listeners.signal });
  root.getElementById("documentInboxExtract")?.addEventListener("click", async ()=>{
    if (!selectedInboxItem) return;
    try {
      await writes.extractInboxDocument(selectedInboxItem);
      await controller.activate("inbox", { force: true });
    } catch {
      setText(root, "documentInboxActionStatus", "Documentanalyse is niet beschikbaar.");
    }
  }, { signal: listeners.signal });
  root.getElementById("documentInboxClose")?.addEventListener("click", ()=>{
    selectedInboxItem = null;
    root.getElementById("documentInboxDialog")?.close();
  }, { signal: listeners.signal });

  for (const link of shell.querySelectorAll("[data-finance-tab]")) {
    link.addEventListener("click", (event)=>{
      event.preventDefault();
      const tab = link.dataset.financeTab;
      const url = new URL(link.href, globalThis.location?.href || "https://operator.invalid/operator/dashboard/");
      if (navigate) navigate(url);
      else globalThis.history?.pushState?.({}, "", `${url.pathname}${url.search}${globalThis.location?.hash || ""}`);
      void controller.activate(tab);
    }, { signal: listeners.signal });
  }
  globalThis.addEventListener?.("popstate", ()=>{ void controller.activate(financeTab(globalThis.location?.href)); }, { signal: listeners.signal });

  const disposeController = controller.dispose.bind(controller);
  controller.dispose = ()=>{
    if (disposed) return;
    disposed = true;
    listeners.abort();
    writes.dispose();
    disposeController();
    for (const id of FINANCE_DIALOG_IDS) {
      const dialog = root.getElementById(id);
      if (dialog?.open) dialog.close();
      for (const form of dialog?.querySelectorAll("form") || []) form.reset();
    }
    for (const target of shell.querySelectorAll("ul, [id$='CurrencyTotals']")) target.replaceChildren();
    selectedExpense = null;
    selectedInboxItem = null;
    delete shell.operatorFinanceController;
  };
  shell.operatorFinanceController = controller;
  const initialTab = financeTab(globalThis.location?.href || "https://operator.invalid/operator/dashboard/");
  present(controller.state);
  void controller.activate(initialTab);
  return controller;
}
