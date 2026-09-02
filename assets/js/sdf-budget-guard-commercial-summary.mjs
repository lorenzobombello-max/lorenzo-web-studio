import { buildSdfCapacityPreviewPresentation } from "./sdf-budget-guard-capacity-preview.mjs";

const PACKAGE_ORDER = Object.freeze(["start", "groei", "pro", "maatwerk"]);
const PACKAGE_LABELS = Object.freeze({
  start: "START",
  groei: "GROEI",
  pro: "PRO",
  maatwerk: "MAATWERK",
});
const PACKAGE_PRICES = Object.freeze({
  start: Object.freeze({ implementation: "€ 2.850", recurring: "€ 175 / maand" }),
  groei: Object.freeze({ implementation: "€ 5.700", recurring: "€ 299 / maand" }),
  pro: Object.freeze({ implementation: "€ 7.500", recurring: "€ 449 / maand" }),
});
const REQUIRED_AUTHORITIES = Object.freeze(["complexity_level", "exceptional_scope"]);

const neutral = (state, packageLabel, message) => ({
  state,
  eyebrow: "Huidige inschatting",
  badge: "Voorlopig · capaciteit",
  packageLabel,
  implementationPrice: "",
  recurringPrice: "",
  priceMessage: "",
  minimumLabel: "",
  minimumContext: "",
  selectionContext: "",
  message,
  detail: "Complexiteit en uitzonderlijke scope worden na indiening nog beoordeeld.",
  reasons: [],
  capacityFacts: [],
  isPreliminary: true,
  finalReviewPending: true,
});

const integerFact = (value, singular, plural = singular) =>
  Number.isSafeInteger(value) && value >= 0 ? `${value.toLocaleString("nl-BE")} ${value === 1 ? singular : plural}` : "";

function capacityFacts(capacity) {
  if (!capacity || typeof capacity !== "object") return [];
  return [
    integerFact(capacity.flow_count, "flow", "flows"),
    integerFact(capacity.document_type_count, "documenttype", "documenttypes"),
    Number.isSafeInteger(capacity.pages_per_month) && capacity.pages_per_month >= 0
      ? `${capacity.pages_per_month.toLocaleString("nl-BE")} pagina's / maand` : "",
    integerFact(capacity.user_count, "gebruiker", "gebruikers"),
  ].filter(Boolean);
}

function isAuthoritativeCapacityPreview(result) {
  return result?.preview_status === "READY"
    && result.preview_kind === "CAPACITY_ONLY"
    && result.final_decision_pending === true
    && Array.isArray(result.pending_authorities)
    && REQUIRED_AUTHORITIES.every((authority) => result.pending_authorities.includes(authority))
    && PACKAGE_ORDER.includes(result.minimum_capacity_package);
}

function displayPackage(minimum, selectedDirection) {
  if (selectedDirection === "advice_requested") return "advice_requested";
  if (!PACKAGE_ORDER.includes(selectedDirection)) return minimum;
  return PACKAGE_ORDER.indexOf(selectedDirection) >= PACKAGE_ORDER.indexOf(minimum)
    ? selectedDirection : minimum;
}

export function shouldApplySdfCapacityPreview(responseSequence, currentSequence) {
  return Number.isSafeInteger(responseSequence)
    && Number.isSafeInteger(currentSequence)
    && responseSequence === currentSequence;
}

export function buildSdfCommercialSummary({ previewResult, selectedDirection = "", loading = false } = {}) {
  if (loading) {
    return neutral(
      "loading",
      "Nieuwe inschatting wordt berekend…",
      "Even geduld terwijl de Budget Guard de gewijzigde capaciteit controleert.",
    );
  }

  if (previewResult?.preview_status === "INCOMPLETE" && previewResult.preview_kind === "CAPACITY_ONLY") {
    return neutral(
      "incomplete",
      "Nog niet berekend",
      "Vul de capaciteitsgegevens verder aan om uw voorlopige pakket en prijs te zien.",
    );
  }

  if (!isAuthoritativeCapacityPreview(previewResult)) {
    return neutral(
      "error",
      "Tijdelijk niet beschikbaar",
      "De Budget Guard kon de huidige configuratie niet berekenen. Controleer de gegevens of probeer opnieuw.",
    );
  }

  const minimum = previewResult.minimum_capacity_package;
  const selected = displayPackage(minimum, selectedDirection);
  const adviceRequested = selected === "advice_requested";
  const pricedPackage = adviceRequested ? minimum : selected;
  const fixedPrice = PACKAGE_PRICES[pricedPackage];
  const packageLabel = adviceRequested ? "ADVIES GEWENST" : PACKAGE_LABELS[pricedPackage];
  const minimumLabel = PACKAGE_LABELS[minimum];
  const selectionContext = adviceRequested
    ? "Indicatieve pakketbasis volgens de Budget Guard"
    : pricedPackage !== minimum ? "Gekozen formule boven het capaciteitsminimum" : "Capaciteitsresultaat";

  return {
    state: "ready",
    eyebrow: "Huidige inschatting",
    badge: "Voorlopig · capaciteit",
    packageLabel,
    implementationPrice: fixedPrice?.implementation || "",
    recurringPrice: fixedPrice?.recurring || "",
    priceMessage: fixedPrice ? "" : "Prijs na beoordeling/offerte",
    minimumLabel,
    minimumContext: `Budget Guard minimum: ${minimumLabel}`,
    selectionContext,
    message: adviceRequested
      ? `Minimaal ${minimumLabel} op basis van capaciteit.`
      : `Voorlopige inschatting op basis van capaciteit: ${PACKAGE_LABELS[pricedPackage]}.`,
    detail: adviceRequested
      ? "Definitieve keuze wordt samen bevestigd. Complexiteit en uitzonderlijke scope blijven nog te beoordelen."
      : "Complexiteit en uitzonderlijke scope worden na indiening nog beoordeeld; het definitieve minimum kan daardoor later verhogen.",
    reasons: buildSdfCapacityPreviewPresentation(previewResult).reasons,
    capacityFacts: capacityFacts(previewResult.normalized_capacity),
    isPreliminary: true,
    finalReviewPending: true,
  };
}
