import { SDF_QUOTATION_TEMPLATE_AUTHORITY } from "../../supabase/functions/commercial-operator-command/sdf-quotation-renderer-edge.ts";

export const SDF_SYNTHETIC_PACKAGE_AMOUNTS = {
  start: [285000, 17500, [114000, 114000, 57000]],
  groei: [570000, 29900, [228000, 228000, 114000]],
  pro: [750000, 44900, [300000, 300000, 150000]],
  maatwerk: [null, null, [null, null, null]],
} as const;

export type SdfSyntheticPackageKey = keyof typeof SDF_SYNTHETIC_PACKAGE_AMOUNTS;

export const SDF_SYNTHETIC_EXECUTION_TERM_WEEKS: Record<SdfSyntheticPackageKey, number> = {
  start: 3,
  groei: 6,
  pro: 9,
  maatwerk: 12,
};

export function createSdfSyntheticRendererPackage(packageKey: SdfSyntheticPackageKey) {
  const [implementation, recurring, milestoneAmounts] = SDF_SYNTHETIC_PACKAGE_AMOUNTS[packageKey];
  const milestones = [40, 40, 20].map((percentage, index) => ({
    sequence: index + 1,
    label: `M${index + 1}`,
    percentage,
    amount_minor: milestoneAmounts[index],
    trigger: `trigger-${index + 1}`,
    due_terms_days: 14,
    recurring_cycle: null,
  }));
  return {
    test_only: true,
    generation_payload: {
      contract_version: 1,
      mode: "ISSUE",
      product_family: "slimme_documentenflow",
      template: {
        template_id: SDF_QUOTATION_TEMPLATE_AUTHORITY.templateId,
        template_version: SDF_QUOTATION_TEMPLATE_AUTHORITY.templateVersion,
        template_sha256: SDF_QUOTATION_TEMPLATE_AUTHORITY.templateSha256,
        authority_status: "APPROVED",
      },
      quotation: { quotation_number: "TEST-SDF-2026-0001" },
      customer: {
        legal_name: "Voorbeeldbedrijf BV",
        contact_name: "Ada Voorbeeld",
        email: "ada@example.test",
        address_line_1: "Teststraat 1",
        address_line_2: null,
        postal_code: "1000",
        city: "Brussel",
        country_code: "BE",
        enterprise_number: "0123.456.789",
        vat_number: "BE0123456789",
      },
      project: {
        scope_summary: "Gecontroleerde verwerking van inkomende facturen.",
        indicative_timing: SDF_SYNTHETIC_EXECUTION_TERM_WEEKS[packageKey],
      },
      totals: { one_time_subtotal_minor: implementation, recurring_subtotal_minor: recurring },
      payment_schedule: { milestones },
      validity: { valid_from: "2026-09-01", valid_until: "2026-10-01", validity_days: 30 },
      sdf_scope: {
        snapshot_contract_version: 1,
        source_taxonomy_version: "sdf_qualification_intake/3.0.0",
        budget_guard_authority_version: 1,
        pricing_authority_version: 2,
        package_key: packageKey,
        required_package_key: packageKey,
        implementation_amount_minor: implementation,
        recurring_amount_minor: recurring,
        payment_milestones: milestones,
        selected_document_types: ["Factuur", "Creditnota"],
        document_flow_count: 1,
        document_type_count: 2,
        normalized_monthly_pages: 500,
        user_count: 3,
        workflow_complexity: {
          custom_complexity: null,
          workflow_capabilities: ["receive", "review"],
        },
        budget_guard_result: { package: packageKey },
        extra_work_line_items: [],
      },
    },
  };
}