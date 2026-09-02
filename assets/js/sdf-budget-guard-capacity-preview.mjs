const PACKAGE_ORDER = Object.freeze(["start", "groei", "pro", "maatwerk"]);
const PACKAGE_LABELS = Object.freeze({ start: "START", groei: "GROEI", pro: "PRO", maatwerk: "MAATWERK" });
const DIMENSION_LABELS = Object.freeze({
  flow_count: "Aantal flows",
  document_type_count: "Aantal documenttypes",
  normalized_monthly_pages: "Genormaliseerd maandvolume",
  user_count: "Aantal gebruikers",
});
const UNAVAILABLE_REASON = "Past niet bij huidige capaciteit";

const availableStates = () => ({
  start: { disabled: false, reason: "" },
  groei: { disabled: false, reason: "" },
  pro: { disabled: false, reason: "" },
  maatwerk: { disabled: false, reason: "" },
  advice_requested: { disabled: false, reason: "" },
});

const base = () => ({
  heading: "Budget Guard — voorlopige capaciteitscheck",
  badge: "Voorlopig · alleen capaciteit",
  minimumLabel: "",
  reasons: [],
  disabledPackages: [],
  packageStates: availableStates(),
  unavailableReason: UNAVAILABLE_REASON.toLowerCase(),
  finalDecisionPending: true,
});

function safeReasons(reasons) {
  if (!Array.isArray(reasons)) return [];
  return reasons.flatMap((reason) => {
    const label = DIMENSION_LABELS[reason?.dimension];
    const packageLabel = PACKAGE_LABELS[reason?.minimum_capacity_package];
    if (!label || !packageLabel || !Number.isSafeInteger(reason?.value) || reason.value < 1) return [];
    return [`${label}: ${reason.value} — minimaal ${packageLabel} op basis van capaciteit.`];
  });
}

export function buildSdfCapacityPreviewPresentation(result) {
  const presentation = base();
  if (!result || result.preview_kind !== "CAPACITY_ONLY") {
    return {
      ...presentation,
      state: "error",
      message: "Budget Guard kon momenteel niet worden berekend. Controleer de gegevens of probeer opnieuw.",
      detail: "Er wordt geen pakket verondersteld zolang de capaciteitscheck niet beschikbaar is.",
    };
  }

  if (result.preview_status === "INCOMPLETE") {
    return {
      ...presentation,
      state: "incomplete",
      message: "Budget Guard wordt berekend zodra de vereiste capaciteitsgegevens ingevuld zijn.",
      detail: "Complexiteit en eventuele uitzonderlijke scope worden na indiening nog beoordeeld.",
    };
  }

  const minimum = result.preview_status === "READY" && result.final_decision_pending === true
    && Array.isArray(result.pending_authorities)
    && result.pending_authorities.includes("complexity_level")
    && result.pending_authorities.includes("exceptional_scope")
    && PACKAGE_ORDER.includes(result.minimum_capacity_package)
    ? result.minimum_capacity_package : "";
  if (!minimum) return buildSdfCapacityPreviewPresentation(null);

  const minimumRank = PACKAGE_ORDER.indexOf(minimum);
  const disabledPackages = PACKAGE_ORDER.filter((packageName, rank) => rank < minimumRank && packageName !== "maatwerk");
  const packageStates = availableStates();
  for (const packageName of disabledPackages) packageStates[packageName] = { disabled: true, reason: UNAVAILABLE_REASON };

  if (minimum === "maatwerk") {
    return {
      ...presentation,
      state: "ready",
      minimumLabel: PACKAGE_LABELS[minimum],
      message: "Maatwerk is vereist op basis van de opgegeven capaciteit.",
      detail: "De volledige scope wordt na indiening commercieel bevestigd, inclusief complexiteit en uitzonderlijke scope.",
      reasons: safeReasons(result.reasons),
      disabledPackages,
      packageStates,
    };
  }

  const message = minimum === "start"
    ? "Op basis van capaciteit past START momenteel."
    : `Op basis van de ingevulde capaciteit is momenteel minimaal ${PACKAGE_LABELS[minimum]} aangewezen.`;
  return {
    ...presentation,
    state: "ready",
    minimumLabel: PACKAGE_LABELS[minimum],
    message,
    detail: minimum === "start"
      ? "De definitieve minimale formule volgt na beoordeling van complexiteit en uitzonderlijke scope."
      : "De definitieve minimale formule kan na beoordeling van complexiteit en uitzonderlijke scope alleen gelijk blijven of hoger uitvallen.",
    reasons: safeReasons(result.reasons),
    disabledPackages,
    packageStates,
  };
}