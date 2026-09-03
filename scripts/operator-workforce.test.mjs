import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  createOperatorWorkforceController,
  initializeOperatorWorkforce,
  loadOperatorWorkforce,
  operatorWorkforceResponse,
} from "../assets/js/operator-workforce.mjs";

const employee = {
  employee_id: "f7020000-0000-4000-8000-000000000001",
  display_name: "Synthetic Medewerker",
  role_title: "Projectcoordinator",
  team_name: "Operations",
  employment_status: "ACTIVE",
  start_date: "2026-01-15",
};

test("dedicated Workforce module accepts only the exact minimal Personnel DTO", ()=>{
  assert.deepEqual(operatorWorkforceResponse({ employees: [employee] }), { employees: [employee] });
  assert.throws(()=>operatorWorkforceResponse({ employees: [{ ...employee, salary: 10 }] }), /INVALID_OPERATOR_WORKFORCE_RESPONSE/);
  assert.throws(()=>operatorWorkforceResponse({ employees: [{ ...employee, employment_status: "ON_LEAVE" }] }), /INVALID_OPERATOR_WORKFORCE_RESPONSE/);
});

test("Workforce loader uses only the narrow caller-JWT RPC", async ()=>{
  const calls = [];
  const result = await loadOperatorWorkforce({ rpc: async (name, parameters)=>{
    calls.push([name, parameters]);
    return { data: { employees: [employee] }, error: null };
  } });
  assert.deepEqual(calls, [["list_operator_workforce_v1", {}]]);
  assert.deepEqual(result.employees, [employee]);
});

test("Workforce authorization failure fast-locks through the generic callback", async ()=>{
  const failures = [];
  await assert.rejects(()=>loadOperatorWorkforce({ rpc: async()=>({ data: null, error: { code: "42501", message: "WORKFORCE_MANAGEMENT_READER_REQUIRED" } }) }, { onAuthorizationFailure: (error)=>failures.push(error.message) }));
  assert.deepEqual(failures, ["WORKFORCE_MANAGEMENT_READER_REQUIRED"]);
});

test("Workforce controller clears state and suppresses pending work after dispose", async ()=>{
  let resolveLoad;
  const renders = [];
  const controller = createOperatorWorkforceController({
    load: ()=>new Promise((resolve)=>{ resolveLoad = resolve; }),
    onChange: (state)=>renders.push(state),
  });
  const pending = controller.refresh();
  controller.dispose();
  resolveLoad({ employees: [employee] });
  assert.equal(await pending, false);
  assert.equal(renders.length, 1);
  assert.deepEqual(controller.state.items, []);
  assert.equal(await controller.refresh(), false);
});

test("Workforce background refresh preserves valid data and recovers after failure", async ()=>{
  const responses = [
    { employees: [employee] },
    new Error("TEMPORARY"),
    { employees: [{ ...employee, display_name: "Bijgewerkt" }] },
  ];
  const renders = [];
  const controller = createOperatorWorkforceController({
    load: async ()=>{
      const response = responses.shift();
      if (response instanceof Error) throw response;
      return response;
    },
    onChange: (state)=>renders.push(state),
  });
  await controller.refresh();
  const renderCount = renders.length;
  assert.equal(await controller.refresh({ background: true }), false);
  assert.equal(renders.length, renderCount);
  assert.equal(controller.state.items[0].display_name, employee.display_name);
  assert.equal(await controller.refresh({ background: true }), true);
  assert.equal(controller.state.items[0].display_name, "Bijgewerkt");
  controller.dispose();
});

test("Workforce initializer rejects unauthorized browser identity before any RPC", ()=>{
  let rpcCalls = 0;
  assert.throws(()=>initializeOperatorWorkforce({}, { rpc() { rpcCalls += 1; } }, { role: "operator" }), /WORKFORCE_MANAGEMENT_READER_REQUIRED/);
  assert.equal(rpcCalls, 0);
});

test("Workforce module has no cross-island local-only mutation or sensitive-field dependency", async ()=>{
  const source = await readFile(new URL("../assets/js/operator-workforce.mjs", import.meta.url), "utf8");
  assert.doesNotMatch(source, /commercial-operator-command|recruitment|application-dossier|sdf|Website|Marketing|Zernio/i);
  assert.doesNotMatch(source, /salary|national|medical|bank|address|family|localhost|127\.0\.0\.1|Mailpit|Playwright|SERVICE_ROLE|JWT_SECRET/i);
  assert.match(source, /new AbortController\(\)/);
  assert.match(source, /listeners\.abort\(\)/);
  assert.match(source, /createOperatorAutoRefresh\(\{[\s\S]*moduleKey: "workforce"[\s\S]*background: true/);
  assert.match(source, /autoRefresh\.dispose\(\)/);
  assert.doesNotMatch(source, /(create|update|delete|upload)_workforce|client\.(from|functions)|fetch\(/i);
});

test("embedded dashboard and generic child use the same dedicated Workforce initializer", async ()=>{
  const [dashboard, dashboardHtml, registry, childHtml] = await Promise.all([
    readFile(new URL("../assets/js/operator-dashboard.js", import.meta.url), "utf8"),
    readFile(new URL("../operator/dashboard/index.html", import.meta.url), "utf8"),
    readFile(new URL("../assets/js/operator-module-registry.mjs", import.meta.url), "utf8"),
    readFile(new URL("../operator/window/index.html", import.meta.url), "utf8"),
  ]);
  assert.match(dashboard, /import \{ initializeOperatorWorkforce \} from "\.\/operator-workforce\.mjs\?v=20260903-auto-refresh-8s"/);
  assert.match(dashboard, /activeModule === "workforce"\) \{\s*initializeOperatorWorkforce\(document, client, currentIdentity, \{ onAuthorizationFailure \}\);\s*return currentIdentity;\s*\}/);
  assert.match(dashboardHtml, /data-operator-window-module="workforce"[^>]*data-operator-window-slot="main"/);
  assert.doesNotMatch(dashboardHtml, /Deze module wordt in een volgende fase aangesloten/);
  assert.match(registry, /initializeOperatorWorkforce/);
  assert.match(childHtml, /id="operatorModuleTemplate-workforce"/);
});