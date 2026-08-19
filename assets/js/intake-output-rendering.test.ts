import { assertFalse, assertStringIncludes } from "jsr:@std/assert@1";

const intakeSource = await Deno.readTextFile(new URL("./intake.js", import.meta.url));
const adminSource = await Deno.readTextFile(new URL("./admin-intake.js", import.meta.url));
const intakeHtml = await Deno.readTextFile(new URL("../../pages/intake.html", import.meta.url));
const adminHtml = await Deno.readTextFile(new URL("../../pages/admin-intake.html", import.meta.url));

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