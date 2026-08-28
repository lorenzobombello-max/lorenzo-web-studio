import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { buildApplicationOutput, type ApplicationOutput } from "./application-output.ts";
import { verifyPricingSnapshotIntegrity } from "./pricing-snapshot-integrity.ts";

export interface SubmittedApplicationOutputContext {
  requestId: string;
  output: ApplicationOutput;
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

const REQUEST_FIELDS = "id, record_classification, application_reference, name, company, email, phone, website_type, budget, timing";
const INTAKE_EVIDENCE_FIELDS = [
  "id", "quote_request_id", "status", "submitted_at", "business_description", "target_audience",
  "has_existing_website", "existing_website_url", "elements_to_keep", "improvement_areas",
  "website_goals", "primary_conversion_goal", "requested_pages", "other_pages", "requested_features",
  "shop_required", "shop_details", "booking_required", "booking_details", "languages", "primary_language",
  "additional_languages", "page_scope_details", "quote_form_details", "multilingual_details", "download_details",
  "newsletter_details", "integrations", "social_channels", "seo_priority", "seo_details", "brand_status",
  "logo_status", "brand_colors", "design_styles", "inspiration_sites", "disliked_styles", "content_status",
  "image_status", "image_support", "content_media_details", "domain_status", "domain_name", "hosting_status",
  "maintenance_interest", "hosting_support", "hosting_maintenance_details", "deadline_date", "deadline_reason",
  "deadline_details", "priorities", "budget_notes", "additional_notes",
].join(", ");
const SNAPSHOT_FIELDS = "id, intake_id, snapshot_contract_version, config_version, config_hash, normalized_evidence, calculation, package_advice, budget_evaluation, package_definition, recurring_services";

type SnapshotVerifier = (snapshot: object, context: string, integrity: unknown) => Promise<boolean>;
type FailureReporter = (reason: string) => void;

const reportOperatorOutputFailure: FailureReporter = (reason) => {
  console.error(`[submitted-application-output] ${reason}`);
};

function validRequest(request: Record<string, unknown> | null, requestId: string): request is Record<string, unknown> {
  return Boolean(request && request.id === requestId &&
    ["production", "internal_e2e"].includes(String(request.record_classification)) &&
    typeof request.name === "string" && typeof request.email === "string");
}

function buildOutputContext(
  request: Record<string, unknown>,
  intake: Record<string, unknown>,
  authoritativeSnapshot: Record<string, unknown>,
): SubmittedApplicationOutputContext | null {
  try {
    return {
      requestId: request.id as string,
      output: buildApplicationOutput({
        recordClassification: request.record_classification,
        applicationReference: request.application_reference,
        submittedAt: intake.submitted_at,
        request,
        evidence: intake,
        authoritativeSnapshot,
      }),
    };
  } catch {
    return null;
  }
}

export async function loadSubmittedApplicationOutput(
  supabase: SupabaseClient,
  intakeTokenHash: string,
): Promise<SubmittedApplicationOutputContext | null> {
  const { data: intake, error: intakeError } = await supabase
    .from("quote_request_intakes")
    .select("quote_request_id, status, submitted_at")
    .eq("access_token_hash", intakeTokenHash)
    .maybeSingle();
  if (intakeError || !intake || !["submitted", "reviewed"].includes(intake.status) || !isUuid(intake.quote_request_id) || typeof intake.submitted_at !== "string") return null;

  const { data: quoteRequest, error: requestError } = await supabase
    .from("quote_requests")
    .select(REQUEST_FIELDS)
    .eq("id", intake.quote_request_id)
    .maybeSingle();
  if (requestError || !validRequest(quoteRequest, intake.quote_request_id)) return null;

  const [{ data: detailsData, error: detailsError }, { data: pricingData, error: pricingError }] = await Promise.all([
    supabase.rpc("inspect_quote_request_intake_details_v4", { p_access_token_hash: intakeTokenHash }),
    supabase.rpc("inspect_customer_pricing_read_v3", { p_access_token_hash: intakeTokenHash }),
  ]);
  const details = Array.isArray(detailsData) ? detailsData[0] : null;
  const pricing = Array.isArray(pricingData) ? pricingData[0] : null;
  if (detailsError || pricingError || !details || !pricing?.snapshot_present) return null;
  const evidence = details.intake_data && typeof details.intake_data === "object" && !Array.isArray(details.intake_data)
    ? details.intake_data as Record<string, unknown> : {};
  const authoritativeSnapshot = pricing.integrity_snapshot && typeof pricing.integrity_snapshot === "object" && !Array.isArray(pricing.integrity_snapshot)
    ? pricing.integrity_snapshot as Record<string, unknown> : null;
  if (!authoritativeSnapshot) return null;

  return buildOutputContext(quoteRequest, { ...evidence, submitted_at: intake.submitted_at }, authoritativeSnapshot);
}

export async function loadSubmittedApplicationOutputForOperator(
  service: SupabaseClient,
  requestId: string,
  verifySnapshot: SnapshotVerifier = verifyPricingSnapshotIntegrity,
  reportFailure: FailureReporter = reportOperatorOutputFailure,
): Promise<SubmittedApplicationOutputContext | null> {
  if (!isUuid(requestId)) return null;
  const [{ data: intakeData, error: intakeError }, { data: requestData, error: requestError }] = await Promise.all([
    service.from("quote_request_intakes").select(INTAKE_EVIDENCE_FIELDS).eq("quote_request_id", requestId).maybeSingle(),
    service.from("quote_requests").select(REQUEST_FIELDS).eq("id", requestId).maybeSingle(),
  ]);
  const intake = record(intakeData);
  const request = record(requestData);
  if (intakeError || requestError || !intake || !validRequest(request, requestId) ||
      intake.quote_request_id !== requestId || !isUuid(intake.id) ||
      !["submitted", "reviewed"].includes(String(intake.status)) || typeof intake.submitted_at !== "string") return null;

  const { data: snapshotData, error: snapshotError } = await service
    .from("quote_request_pricing_snapshots")
    .select(SNAPSHOT_FIELDS)
    .eq("intake_id", intake.id)
    .maybeSingle();
  const snapshot = record(snapshotData);
  if (snapshotError || !snapshot || !isUuid(snapshot.id) || snapshot.intake_id !== intake.id) {
    reportFailure("snapshot_record_unavailable");
    return null;
  }
  const authoritativeSnapshot: Record<string, unknown> = {
    snapshotContractVersion: snapshot.snapshot_contract_version,
    pricingConfigVersion: snapshot.config_version,
    pricingConfigHash: snapshot.config_hash,
    normalizedScope: snapshot.normalized_evidence,
    calculation: snapshot.calculation,
    packageAdvice: snapshot.package_advice,
    budgetEvaluation: snapshot.budget_evaluation,
    ...(snapshot.snapshot_contract_version === 3 ? { packageDefinition: snapshot.package_definition } : {}),
    ...(snapshot.recurring_services === null ? {} : { recurringServices: snapshot.recurring_services }),
  };
  const { data: integrityData, error: integrityError } = await service.rpc(
    "get_pricing_snapshot_integrity_for_operator_v1",
    { p_snapshot_id: snapshot.id },
  );
  const integrity = record(Array.isArray(integrityData) ? integrityData[0] : null);
  if (integrityError || !integrity) {
    reportFailure("integrity_record_unavailable");
    return null;
  }
  if (!await verifySnapshot(authoritativeSnapshot, intake.id, {
    algorithmVersion: integrity.algorithm_version,
    keyId: integrity.key_id,
    mac: integrity.mac,
  })) {
    reportFailure("integrity_verification_failed");
    return null;
  }

  const context = buildOutputContext(request, intake, authoritativeSnapshot);
  if (!context) reportFailure("output_build_failed");
  return context;
}
