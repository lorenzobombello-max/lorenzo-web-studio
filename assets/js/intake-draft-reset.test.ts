import { assertEquals, assertExists, assertFalse, assertStringIncludes } from "jsr:@std/assert@1";
import { DOMParser } from "npm:linkedom@0.18.12";

const source = await Deno.readTextFile(new URL("./intake.js", import.meta.url));
const html = await Deno.readTextFile(new URL("../../pages/intake.html", import.meta.url));
const edgeSource = await Deno.readTextFile(new URL("../../supabase/functions/intake-quote-request/index.ts", import.meta.url));
const typesSource = await Deno.readTextFile(new URL("../../supabase/functions/_shared/types.ts", import.meta.url));
const document = new DOMParser().parseFromString(html, "text/html");

function sourceFunction(name: string) {
  const signature = `function ${name}(`;
  const start = source.indexOf(signature);
  assertFalse(start === -1, `${name} must exist`);
  const bodyStart = source.indexOf("{", start);
  let depth = 0;
  for (let index = bodyStart; index < source.length; index += 1) {
    if (source[index] === "{") depth += 1;
    if (source[index] === "}") depth -= 1;
    if (depth === 0) return source.slice(start, index + 1);
  }
  throw new Error(`Could not extract ${name}`);
}

Deno.test("reset is a secondary action with the approved confirmation contract", () => {
  const action = document.getElementById("resetDraft");
  const modal = document.getElementById("resetModal");
  assertExists(action);
  assertExists(modal);
  assertEquals(action.textContent.trim(), "Opnieuw beginnen");
  assertEquals(modal.querySelector("h2")?.textContent.trim(), "Opnieuw beginnen?");
  assertEquals(
    document.getElementById("resetModalDescription")?.textContent.trim(),
    "Alle ingevulde gegevens van deze intake worden gewist. Deze actie kan niet ongedaan worden gemaakt.",
  );
  assertEquals([...modal.querySelectorAll(".intake-modal__actions button")].map((button) => button.textContent.trim()), [
    "Annuleren",
    "Ja, opnieuw beginnen",
  ]);
  assertExists(action.closest(".intake-reset-action"));
  assertEquals(action.closest("#intakeActions"), null);
});

Deno.test("cancel controls only close the modal and never dispatch reset", () => {
  const modal = document.getElementById("resetModal");
  assertExists(modal);
  const cancel = modal.querySelector('.intake-modal__actions [data-close-modal]');
  assertExists(cancel);
  assertEquals(cancel.id, "");
  assertFalse(cancel.hasAttribute("data-reset-draft"));
  assertStringIncludes(source, 'button.addEventListener("click", () => closeModal(button.closest(".intake-modal")))');
  assertStringIncludes(source, 'confirmReset?.addEventListener("click", resetDraft)');
});

Deno.test("draft mutation requests carry revision but no selectable intake identity", () => {
  const requestSource = sourceFunction("request");
  assertStringIncludes(requestSource, 'action === "save_draft" || action === "reset_draft"');
  assertStringIncludes(requestSource, "expected_revision: draftRevision");
  assertFalse(/intake[_A-Z]?id|quote_request_id|access_token_hash|admin_access/i.test(requestSource));
  assertStringIncludes(sourceFunction("saveDraft"), 'request("save_draft", collectData())');
  assertStringIncludes(sourceFunction("resetDraft"), 'request("reset_draft")');
});

Deno.test("successful reset reuses form defaults and rebuilds dependent UI", () => {
  const resetState = sourceFunction("restoreInitialFormState");
  assertStringIncludes(resetState, "form.reset()");
  assertStringIncludes(resetState, "clearLocalFileSelection");
  assertStringIncludes(resetState, "clearErrors()");
  assertStringIncludes(resetState, "updateConditionals()");
  assertStringIncludes(resetState, "updatePriorities()");
  assertStringIncludes(resetState, "renderReviewSummary()");
  assertStringIncludes(resetState, "showStep(0, true)");
  assertStringIncludes(resetState, "schedulePricingPreview({ force: true, immediate: true })");
  assertFalse(/\.value\s*=\s*["'][^"']+["']/.test(resetState), "reset must not invent field defaults");
  assertStringIncludes(sourceFunction("resetDraft"), "draftRevision = body.intake.revision");
});

Deno.test("stale revision has explicit non-destructive conflict UX", () => {
  const presentation = sourceFunction("apiErrorPresentation");
  assertStringIncludes(presentation, 'code === "INTAKE_REVISION_CONFLICT"');
  assertStringIncludes(presentation, "Deze intake werd ondertussen in een ander venster gewijzigd. Herlaad de pagina om de meest recente versie te gebruiken.");
  assertStringIncludes(sourceFunction("handleApiError"), 'presentation.kind === "conflict"');
  assertStringIncludes(edgeSource, 'code: "INTAKE_REVISION_CONFLICT"');
  assertStringIncludes(edgeSource, 'mutationRpc = "save_quote_request_intake_draft_v2"');
  assertStringIncludes(edgeSource, 'supabase.rpc("reset_quote_request_intake_draft_v1"');
  assertStringIncludes(edgeSource, 'supabase.rpc("inspect_quote_request_intake_details_v5"');
  assertStringIncludes(typesSource, '| "reset_draft"');
});

Deno.test("final submit remains on the authoritative v5 pricing snapshot path", () => {
  assertStringIncludes(edgeSource, 'if (action === "submit")');
  assertStringIncludes(edgeSource, 'mutationRpc = "update_quote_request_intake_v5"');
  assertStringIncludes(edgeSource, 'if (action === "submit" && result.outcome === "submitted")');
  assertStringIncludes(sourceFunction("submitFinal"), 'request("submit", collectData())');
  assertFalse(sourceFunction("submitFinal").includes("expected_revision"));
});
