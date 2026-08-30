const packageDirections = new Set(["start", "groei", "pro", "maatwerk", "advice_requested"]);
const periods = new Set(["weekly", "monthly", "quarterly", "yearly"]);

const nonEmptyString = (value) => typeof value === "string" && value.trim().length > 0;
const boundedInteger = (value, minimum, maximum) => Number.isInteger(value) && value >= minimum && value <= maximum;

export function deriveSdfStepState(data = {}, confirmationAccepted = false) {
  const categories = data.documentPurpose?.categories;
  const commercial = data.commercialQualification;
  const volumes = commercial?.documentVolumes;
  const selectedTypes = Array.isArray(categories) ? new Set(categories) : new Set();
  const volumeTypes = Array.isArray(volumes) ? new Set(volumes.map((volume) => volume?.documentType)) : new Set();
  const volumesValid = selectedTypes.size > 0 && Array.isArray(volumes) &&
    volumes.length === selectedTypes.size && volumeTypes.size === selectedTypes.size &&
    volumes.every((volume) => selectedTypes.has(volume?.documentType) &&
      boundedInteger(volume?.documentCount, 1, 1000000) && periods.has(volume?.period) &&
      boundedInteger(volume?.averagePagesPerDocument, 1, 1000));
  const stepOneValid = packageDirections.has(commercial?.packageDirection) &&
    (commercial.packageDirection !== "maatwerk" || nonEmptyString(commercial.customComplexity)) &&
    selectedTypes.size > 0 &&
    (!selectedTypes.has("other_custom") || nonEmptyString(data.documentPurpose?.otherDescription)) &&
    volumesValid;
  const stepTwoValid = Array.isArray(data.workflowCapabilities) && data.workflowCapabilities.length > 0;
  const requirements = data.businessRequirements;
  const samples = data.sampleDocumentMetadata;
  const stepThreeValid = nonEmptyString(requirements?.currentWorkflow) && nonEmptyString(requirements?.desiredWorkflow) &&
    nonEmptyString(requirements?.volumeBand) && nonEmptyString(requirements?.frequency) &&
    Array.isArray(requirements?.relevantDocumentTypes) && requirements.relevantDocumentTypes.length > 0 &&
    Array.isArray(requirements?.rolesUsers) && requirements.rolesUsers.length > 0 &&
    typeof samples?.available === "boolean" && typeof samples?.requestedByLws === "boolean" &&
    typeof samples?.uploadRequiredLater === "boolean" && confirmationAccepted === true;
  const valid = [stepOneValid, stepTwoValid, stepThreeValid];
  const unlocked = [true, stepOneValid, stepOneValid && stepTwoValid];
  const completed = [stepOneValid, stepOneValid && stepTwoValid, stepOneValid && stepTwoValid && stepThreeValid];
  return { valid, unlocked, completed };
}

export function canActivateSdfStep(state, targetStep) {
  return Number.isInteger(targetStep) && targetStep >= 0 && targetStep < state.unlocked.length && state.unlocked[targetStep] === true;
}
