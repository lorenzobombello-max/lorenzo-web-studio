import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("dedicated Finance module is standalone and exports its initializer", async () => {
  const finance = await import("../assets/js/operator-finance.mjs");
  assert.equal(typeof finance.initializeOperatorFinance, "function");
  assert.equal(typeof finance.createOperatorFinanceController, "function");
  const source = await read("assets/js/operator-finance.mjs");
  assert.doesNotMatch(source, /from ["'][^"']*(?:operator-dashboard|application-dossier|sdf-qualification|website)[^"']*["']/i);
  assert.doesNotMatch(source, /localStorage|sessionStorage|window\.name|localhost|127\.0\.0\.1/i);
  assert.match(source, /url\.pathname\}\$\{url\.search\}\$\{globalThis\.location\?\.hash/);
});

test("embedded dashboard and generic child use the same Finance initializer", async () => {
  const [dashboard, registry, childHtml] = await Promise.all([
    read("assets/js/operator-dashboard.js"),
    read("assets/js/operator-module-registry.mjs"),
    read("operator/window/index.html"),
  ]);
  assert.match(dashboard, /initializeOperatorFinance/);
  assert.match(registry, /initializeOperatorFinance/);
  assert.match(childHtml, /id="operatorModuleTemplate-finance"/);
  for (const id of ["businessExpenseForm", "supplierDocumentForm", "documentInboxUploadForm", "documentInboxConfirmedForm"]) {
    assert.match(childHtml, new RegExp(`id="${id}"`));
  }
  for (const name of ["supplier_name", "document_type", "document_reference", "document_date", "expense_date", "amount", "currency", "description", "category", "relation_type"]) {
    assert.match(childHtml, new RegExp(`name="${name}"`));
  }
});

test("standalone Finance owns every existing write flow and dashboard has no dead legacy runtime", async () => {
  const [finance, dashboard] = await Promise.all([
    read("assets/js/operator-finance.mjs"),
    read("assets/js/operator-dashboard.js"),
  ]);
  for (const operation of [
    "create_business_expense_v1",
    "supplier-document-upload",
    "create_supplier_document_v1",
    "link_business_expense_document_v1",
    "document-inbox-extract",
    "receive_document_inbox_item_v1",
    "update_document_inbox_proposal_v1",
    "confirm_document_inbox_values_v1",
    "approve_document_inbox_item_v1",
    "reject_document_inbox_item_v1",
    "process_document_inbox_item_v1",
  ]) assert.match(finance, new RegExp(operation));
  assert.doesNotMatch(dashboard, /if \(false\) \{\s*const activeFinanceTab/);
});

test("Finance remains owner-only and Dossiers remains blocked", async () => {
  const [registry, workspaceMigration] = await Promise.all([
    read("assets/js/operator-module-registry.mjs"),
    read("supabase/migrations/20260902240000_add_operator_finance_multiscreen_v1.sql"),
  ]);
  assert.match(registry, /moduleKey: "finance"[\s\S]*standaloneAllowed: true[\s\S]*multiScreenAllowed: true/);
  assert.match(registry, /moduleKey: "dossiers"[\s\S]*standaloneAllowed: false[\s\S]*multiScreenAllowed: false/);
  assert.match(workspaceMigration, /when 'finance' then p_role = 'owner'/);
  assert.match(workspaceMigration, /'messages', 'calendar', 'recruitment', 'workforce', 'finance'/);
});

test("Finance controller suppresses stale loads and disposal is terminal", async () => {
  const { createOperatorFinanceController } = await import("../assets/js/operator-finance.mjs");
  const pending = new Map();
  const states = [];
  const controller = createOperatorFinanceController({
    loadTab: (tab, isCurrent)=>new Promise((resolve)=>pending.set(tab, { isCurrent, resolve })),
    onChange: (state)=>states.push(state),
  });
  const websites = controller.activate("websites");
  const expenses = controller.activate("expenses");
  assert.equal(pending.get("websites").isCurrent(), false);
  assert.equal(pending.get("expenses").isCurrent(), true);
  pending.get("websites").resolve();
  assert.equal(await websites, false);
  controller.dispose();
  assert.equal(pending.get("expenses").isCurrent(), false);
  pending.get("expenses").resolve();
  assert.equal(await expenses, false);
  assert.equal(await controller.refresh(), false);
  assert.equal(states.at(-1).activeTab, "expenses");
});

test("Finance initializer rejects every non-owner role", async () => {
  const { initializeOperatorFinance } = await import("../assets/js/operator-finance.mjs");
  const root = { getElementById() {}, querySelector() { return {}; } };
  for (const role of ["admin", "operations_manager", "operator", "reviewer", "read_only", null]) {
    assert.throws(()=>initializeOperatorFinance(root, { rpc() {} }, { role }), /FINANCE_MANAGEMENT_OWNER_REQUIRED/);
  }
});

test("Finance write authority uses bounded server contracts and fails closed", async () => {
  const { createOperatorFinanceWriteAuthority } = await import("../assets/js/operator-finance.mjs");
  const calls = [];
  const documentId = "10000000-0000-4000-8000-000000000001";
  const client = {
    rpc: async (name, request)=>{
      calls.push({ type: "rpc", name, request });
      const data = name === "create_business_expense_v1" ? "30000000-0000-4000-8000-000000000003"
        : name === "create_supplier_document_v1" ? documentId
        : name === "link_business_expense_document_v1" ? "40000000-0000-4000-8000-000000000004"
        : { id: documentId, status: "REVIEW_REQUIRED", revision: 5 };
      return { data, error: null };
    },
    functions: {
      invoke: async (name, request)=>{
        calls.push({ type: "function", name, request });
        return { data: {
          ok: true,
          code: "STORED",
          bucket: "supplier-documents",
          object_path: `documents/${"a".repeat(64)}.pdf`,
          sha256: "a".repeat(64),
          byte_count: 42,
          mime_type: "application/pdf",
        }, error: null };
      },
    },
  };
  const authority = createOperatorFinanceWriteAuthority(client);
  await authority.createExpense({ supplier_name: "Leverancier", description: "Licentie", category: "software", amount: "12,34", expense_date: "2026-09-02" });
  assert.deepEqual(calls[0], { type: "rpc", name: "create_business_expense_v1", request: {
    p_supplier_name: "Leverancier", p_description: "Licentie", p_category: "software",
    p_amount_minor: 1234, p_currency: "EUR", p_expense_date: "2026-09-02",
  } });
  const file = { name: "factuur.pdf", type: "application/pdf", size: 42 };
  await authority.attachExpenseDocument("20000000-0000-4000-8000-000000000002", {
    document_type: "INVOICE", supplier_name: "Leverancier", document_reference: "INV-1",
    document_date: "2026-09-02", relation_type: "INVOICE",
  }, file);
  assert.equal(calls[1].name, "supplier-document-upload");
  assert.equal(calls[2].name, "create_supplier_document_v1");
  assert.equal(calls[3].name, "link_business_expense_document_v1");
  const inboxItem = { id: documentId, revision: 4, warnings: [{ code: "REVIEW" }] };
  await authority.command("update_document_inbox_proposal_v1", inboxItem, {
    supplier_name: "Leverancier", document_type: "INVOICE", document_reference: "INV-1",
    document_date: "2026-09-01", amount: "12,34", currency: "EUR", description: "Licentie",
    category: "software", expense_date: "2026-09-02", relation_type: "INVOICE",
  });
  assert.deepEqual(calls[4], { type: "rpc", name: "update_document_inbox_proposal_v1", request: {
    p_inbox_item_id: documentId, p_expected_revision: 4, p_supplier_name: "Leverancier",
    p_document_type: "INVOICE", p_document_reference: "INV-1", p_document_date: "2026-09-01",
    p_amount_minor: 1234, p_currency: "EUR", p_description: "Licentie", p_category: "software",
    p_expense_date: "2026-09-02", p_relation_type: "INVOICE", p_warnings: [{ code: "REVIEW" }],
  } });
  client.rpc = async ()=>({ data: { ok: true }, error: null });
  await assert.rejects(()=>authority.command("approve_document_inbox_item_v1", inboxItem), /INVALID_FINANCE_MUTATION_RESPONSE/);
  assert.throws(()=>authority.command("arbitrary_rpc", { id: documentId, revision: 1 }), /FINANCE_COMMAND_NOT_ALLOWED/);
  authority.dispose();
  await assert.rejects(()=>authority.createExpense({ supplier_name: "L", description: "D", category: "other", amount: "1", expense_date: "2026-09-02" }), /FINANCE_DISPOSED/);
});
