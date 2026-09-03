import { assertEquals, assertFalse, assertStringIncludes } from "jsr:@std/assert@1";

const intakeSource = await Deno.readTextFile(new URL("./intake.js", import.meta.url));
const adminSource = await Deno.readTextFile(new URL("./admin-intake.js", import.meta.url));
const dossierSource = await Deno.readTextFile(new URL("./application-dossier-copy.js", import.meta.url));
const operatorSource = await Deno.readTextFile(new URL("./operator-dashboard.js", import.meta.url));
const operatorGuardSource = await Deno.readTextFile(new URL("./operator-dashboard-guard.mjs", import.meta.url));
const intakeHtml = await Deno.readTextFile(new URL("../../pages/intake.html", import.meta.url));
const adminHtml = await Deno.readTextFile(new URL("../../pages/admin-intake.html", import.meta.url));
const operatorHtml = await Deno.readTextFile(new URL("../../operator/dashboard/index.html", import.meta.url));
const operatorCss = await Deno.readTextFile(new URL("../css/operator-dashboard.css", import.meta.url));
const operatorEdge = await Deno.readTextFile(new URL("../../supabase/functions/commercial-operator-command/index.ts", import.meta.url));

function functionSource(source: string, name: string) {
  const start = source.indexOf(`function ${name}(`);
  const next = source.indexOf("\n  function ", start + 1);
  return source.slice(start, next === -1 ? source.length : next);
}

Deno.test("customer confirmation renders the application DTO without technical identifiers", () => {
  for (const expected of ["intakeSuccessReference", "intakeSuccessPackage", "intakeSuccessMinimum", "intakeSuccessRecurring", "niet-bindende prijsindicatie"]) {
    assertStringIncludes(intakeHtml, expected);
  }
  assertStringIncludes(intakeSource, 'setReadOnly("submitted", body.application)');
  assertStringIncludes(intakeSource, ".textContent = application.applicationReference");
  assertFalse(/pricingConfigHash|integrity_metadata|application\.requestId/.test(intakeSource));
});

Deno.test("secure briefing uses application reference as primary identity and structured commercial output", () => {
  assertStringIncludes(adminHtml, 'id="adminBriefingApplication"');
  assertStringIncludes(adminSource, "application.applicationReference");
  assertStringIncludes(adminSource, 'appendSection("Application"');
  assertStringIncludes(adminSource, 'addDetail(list, "Indicatief projectminimum"');
  assertStringIncludes(adminSource, '`Legacy #${String(request.id).slice(0, 8).toUpperCase()}`');
});

Deno.test("customer and admin render user values through textContent", () => {
  const customerRenderer = functionSource(intakeSource, "renderSuccessSummary");
  const adminRenderer = functionSource(adminSource, "appendScalar");
  assertStringIncludes(customerRenderer, "target.textContent = text");
  assertStringIncludes(adminRenderer, "text.textContent =");
  assertFalse(/innerHTML\s*=/.test(`${customerRenderer}\n${adminRenderer}`));
});

Deno.test("historical NULL references remain reviewable without fabricated application numbers", () => {
  assertStringIncludes(adminSource, "Legacy #");
  assertStringIncludes(adminSource, "application?.applicationReference || legacyReference");
  assertStringIncludes(intakeSource, "reference.hidden = true");
  assertFalse(adminSource.includes("LWS-AAN-LEGACY"));
});

Deno.test("customer and authorized operator use one historical dossier copy module", () => {
  for (const expected of ["intakeDossierDownload", "intakeDossierPrint", "intakeDossierCopy"]) assertStringIncludes(intakeHtml, expected);
  for (const expected of ["applicationDossierDownload", "applicationDossierPrint", "applicationDossierCopyContent"]) assertStringIncludes(operatorHtml, expected);
  assertStringIncludes(intakeSource, 'from "./application-dossier-copy.js?v=20260828-dossier-ux"');
  assertStringIncludes(operatorSource, 'from "./application-dossier-copy.js?v=20260828-dossier-purge-ui"');
  assertStringIncludes(dossierSource, "buildApplicationDossierPresentation(application)");
});

Deno.test("operator dossier output is built server-side after authorized detail lookup", () => {
  const detailLookup = operatorEdge.indexOf('input.action === "get_application_detail"');
  const sharedBuild = operatorEdge.indexOf("loadSubmittedApplicationOutputForOperator(", detailLookup);
  assertEquals(detailLookup >= 0, true);
  assertEquals(sharedBuild > detailLookup, true);
  assertStringIncludes(operatorEdge, "return enrichOperatorApplicationDetailWithOutput(data, context)");
  assertFalse(/access_token_hash|integrity_snapshot|pricingConfigHash/.test(operatorSource));
  assertFalse(/access_token_hash|integrity_snapshot|pricingConfigHash/.test(dossierSource));
});

Deno.test("dossier assets use their current intake and operator cache identities", () => {
  const intakeCssVersion = "20260828-dossier-copy-remediation";
  const intakeVersion = "20260901-intake-context";
  const dossierCopyVersion = "20260828-dossier-ux";
  const operatorCssVersion = "20260903-multiscreen-ux-r1";
  const operatorGuardVersion = "20260903-multiscreen-ux-r1";
  const operatorVersion = "20260903-trash-refresh-r1";
  const operatorDossierVersion = "20260903-trash-refresh-r1";
  assertStringIncludes(intakeHtml, `intake.css?v=${intakeCssVersion}`);
  assertStringIncludes(intakeHtml, `intake.js?v=${intakeVersion}`);
  assertStringIncludes(operatorHtml, `operator-dashboard.css?v=${operatorCssVersion}`);
  assertStringIncludes(operatorHtml, `operator-dashboard-guard.mjs?v=${operatorGuardVersion}`);
  assertStringIncludes(operatorGuardSource, `operator-dashboard.js?v=${operatorVersion}`);
  assertStringIncludes(intakeSource, `application-dossier-copy.js?v=${dossierCopyVersion}`);
  assertStringIncludes(operatorSource, `operator-dossiers.mjs?v=${operatorDossierVersion}`);
});

Deno.test("operator dossier stays compact and opens the shared copy in a document dialog", () => {
  const dossierIndex = operatorHtml.indexOf('id="applicationDossierCopy"');
  const dashboardGridIndex = operatorHtml.indexOf('class="dashboard-grid"');
  assertEquals(operatorHtml.match(/id="applicationDossierCopy"/g)?.length, 1);
  assertEquals(dossierIndex > dashboardGridIndex, true);
  assertStringIncludes(operatorHtml, 'id="applicationDossierActions"');
  assertStringIncludes(operatorHtml, 'id="applicationDossierView"');
  assertStringIncludes(operatorHtml, 'id="applicationDossierDownload"');
  assertStringIncludes(operatorHtml, 'id="applicationDossierPrint"');
  assertStringIncludes(operatorHtml, 'id="applicationDossierPreview"');
  assertStringIncludes(operatorHtml, 'id="applicationDossierPreviewClose"');
  assertFalse(operatorHtml.includes("operator-dossier-copy"));
  assertStringIncludes(operatorSource, "applicationDossierPreview.showModal()");
  assertStringIncludes(operatorSource, "downloadApplicationDossierPdf(dossierOutput)");
  assertStringIncludes(operatorSource, "printApplicationDossier(dossierOutput)");
  assertStringIncludes(operatorSource, "applicationDossierActions.hidden = true");
  assertStringIncludes(operatorSource, "applicationDossierActions.hidden = false");
  const hideActions = operatorSource.indexOf("applicationDossierActions.hidden = true", operatorSource.indexOf("function renderDetail("));
  const renderCopy = operatorSource.indexOf("renderApplicationDossier", hideActions);
  const showActions = operatorSource.indexOf("applicationDossierActions.hidden = false", renderCopy);
  assertEquals(hideActions < renderCopy && renderCopy < showActions, true);
  assertStringIncludes(operatorSource.slice(renderCopy, showActions + 200), "catch {");
  assertStringIncludes(operatorCss, ".dossier-preview-dialog");
});