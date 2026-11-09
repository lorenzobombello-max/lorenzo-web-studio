// GIT-001C: operator-facing "build preview" button with progress/status
// polling (checkpoint 009-git001c-astro-preview-build-plan.md §16.1/§16.3).
// Deliberately framework/DOM-agnostic and dependency-injected (matching
// this codebase's existing RPC-client-abstraction convention) so it is
// testable with Node's built-in test runner without a browser, and kept
// as its own, new, self-contained module rather than editing the
// existing operator-website-execution*.mjs files, to avoid colliding
// with unrelated, already-in-flight edits to those shared files
// elsewhere in this session.
export const TERMINAL_BUILD_STATUSES = Object.freeze([
  "PASS",
  "PASS_WITH_WARNINGS",
  "FAILED",
]);

export function isTerminalBuildStatus(status) {
  return TERMINAL_BUILD_STATUSES.includes(status);
}

export function describeConceptGenerationError(code) {
  switch (code) {
    case "CONCEPT_TARGET_ALREADY_EXISTS":
      return "De bestaande conceptbranch is behouden. Eerst is controle van de herkomst nodig.";
    case "CONCEPT_STARTER_NOT_VERIFIED":
      return "De oorspronkelijke starter kon niet worden bevestigd. Er is geen conceptbranch aangemaakt.";
    case "CONCEPT_SOURCE_STALE":
      return "De bron is ondertussen gewijzigd. Er is niets overschreven; controleer de conceptbranch.";
    case "CONCEPT_SOURCE_CONFLICT":
      return "Handmatige wijzigingen zijn behouden. Het concept is niet overschreven; controleer de bron.";
    case "CONCEPT_IN_PROGRESS":
      return "Er is al een conceptgeneratie bezig. Er is geen tweede previewbuild gestart.";
    case "CONCEPT_RECONCILIATION_REQUIRED":
    case "CONCEPT_WRITE_UNCERTAIN":
      return "De bronvastlegging is onzeker. Start niet opnieuw; eerst is een broncontrole nodig.";
    case "CONCEPT_INTAKE_STALE":
    case "CONCEPT_SOURCE_COMMITTED_STALE_INTAKE":
      return "De intake is ondertussen gewijzigd. Er is geen previewbuild gestart; controleer de actuele intake.";
    case "CONCEPT_SUBMITTED_INTAKE_REQUIRED":
      return "Een ingediende, eenduidige klantintake ontbreekt. Er is geen concept gegenereerd.";
    default:
      return typeof code === "string" && /^CONCEPT_[A-Z0-9_]{1,80}$/.test(code)
        ? "Het websiteconcept kon niet veilig worden voorbereid. Controleer de intake en bron."
        : null;
  }
}

// Only ever surfaces the fixed, safe status string and (once terminal) a
// handoff URL - never raw build logs or internal diagnostics, matching
// the CI-log-only observability convention established in the REL-002
// work earlier in this session.
export function describePreviewBuildState(status) {
  switch (status) {
    case "BUILD_REQUESTED":
      return { label: "Previewaanvraag wordt gecontroleerd\u2026", tone: "progress" };
    case "BUILD_QUEUED":
      return { label: "Preview staat in de wachtrij\u2026", tone: "progress" };
    case "DISPATCH_UNKNOWN":
      return { label: "Ontvangst van previewaanvraag onzeker \u2013 geen nieuwe aanvraag starten", tone: "warning" };
    case "BUILD_IN_PROGRESS":
      return { label: "Preview wordt gebouwd\u2026", tone: "progress" };
    case "PASS":
      return { label: "Preview gereed", tone: "success" };
    case "PASS_WITH_WARNINGS":
      return {
        label: "Preview gereed (met beperkingen \u2013 sommige bestanden geblokkeerd)",
        tone: "warning",
      };
    case "FAILED":
      return { label: "Preview mislukt \u2013 controle vereist", tone: "error" };
    default:
      return { label: "Status onbekend", tone: "error" };
  }
}

// pollIntervalMs starts at 3s and backs off to 5s after the first 30s,
// per checkpoint §16.1's frontend-polling design.
function nextPollDelayMs(elapsedMs) {
  return elapsedMs < 30_000 ? 3_000 : 5_000;
}

export function createPreviewBuildController(dependencies) {
  const {
    startBuild,
    getBuildStatus,
    onStateChange,
    now = () => Date.now(),
    wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    leaseTtlMs = 20 * 60 * 1000,
  } = dependencies;
  if (typeof startBuild !== "function" || typeof getBuildStatus !== "function") {
    throw new Error("PREVIEW_BUILD_CONTROLLER_CONFIGURATION_ERROR");
  }
  let cancelled = false;

  function emit(state) {
    if (typeof onStateChange === "function") onStateChange(state);
  }

  return Object.freeze({
    async start(input) {
      cancelled = false;
      emit({ status: "BUILD_REQUESTED", ...describePreviewBuildState("BUILD_REQUESTED") });
      const initial = await startBuild(input);
      const { leaseId } = initial;
      if (initial.status) {
        emit({ ...initial, ...describePreviewBuildState(initial.status) });
        if (isTerminalBuildStatus(initial.status)) return initial;
      }
      const startedAt = now();
      for (;;) {
        if (cancelled) return { status: "CANCELLED" };
        const elapsed = now() - startedAt;
        if (elapsed > leaseTtlMs) {
          const timedOut = { status: "FAILED", reason: "BUILD_LEASE_EXPIRED" };
          emit({ ...timedOut, ...describePreviewBuildState("FAILED") });
          return timedOut;
        }
        const result = await getBuildStatus(leaseId);
        emit({ ...result, ...describePreviewBuildState(result.status) });
        if (isTerminalBuildStatus(result.status)) return result;
        await wait(nextPollDelayMs(elapsed));
      }
    },
    cancel() {
      cancelled = true;
    },
  });
}
