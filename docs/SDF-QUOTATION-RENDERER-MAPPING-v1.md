# SDF quotation renderer mapping v1

## Authority boundary

- Product: `slimme_documentenflow` only.
- Generation contract: version `1`, mode `ISSUE`.
- Template: `LWS_SDF_QUOTATION_NL_BE`, version `1.0.0-official`, status `APPROVED`.
- Template SHA-256: `33da6dbbeef02876d0624d28fb17a16787cb1e7d0bde8ee74026664ba7739c1d`.
- Scope versions: snapshot `1`, taxonomy `sdf_qualification_intake/3.0.0`, Budget Guard `1`, pricing `2`.
- `sdf_scope.package_key` must equal `sdf_scope.required_package_key`.
- The renderer formats authoritative values. It does not select packages, calculate prices, allocate milestones, or derive capacities.

## Field mapping

| Source | Target | Formatting | Requirement |
| --- | --- | --- | --- |
| `quotation.quotation_number` | Table 1, `Offertenummer` value | Canonical `LWS-OFF-YYYY-NNNN`; synthetic tooling permits `TEST-SDF-YYYY-NNNN` through renderer metadata | Required |
| `validity.valid_from` | Table 1, `Datum` value | `YYYY-MM-DD` to `DD/MM/YYYY` | Required |
| `validity.valid_until` | Table 1, `Geldig tot` value | `YYYY-MM-DD` to `DD/MM/YYYY` | Required |
| `customer.legal_name` | Table 2, name; table 9, customer signature name | Trimmed text | Required |
| `customer.enterprise_number` | Table 2, enterprise number | Value or `Niet opgegeven` | Optional |
| `customer.vat_number` | Table 2, VAT number | Value or `Niet opgegeven` | Optional |
| Customer address fields | Table 2, address | Non-empty fields joined with comma-space | Address line 1 required |
| `customer.country_code` | Table 2, country | Trimmed text | Required |
| `customer.contact_name` | Table 2, contact | Value or `Niet opgegeven` | Optional |
| `customer.email` | Table 2, email | Trimmed text | Required |
| `project.scope_summary` | `Projectomschrijving`, unique underscore paragraph within the section | Exact approved text; no title, notes, or free-text fallback | Required |
| `sdf_scope.package_key` | Table 3, `Aangeduid` | Exactly one `☒`; all others `☐` | Required |
| `sdf_scope.implementation_amount_minor` | Selected fixed-package row, implementation | Integer minor EUR to `€ 1.234,56` | Required except MAATWERK |
| `sdf_scope.recurring_amount_minor` | Selected fixed-package row, recurring | Integer minor EUR plus ` / maand` | Required except MAATWERK |
| `sdf_scope.document_flow_count` | Table 5, `Documentflows` | Non-negative integer | Required |
| `sdf_scope.normalized_monthly_pages` | Table 5, processing volume | Non-negative integer | Required |
| `sdf_scope.selected_document_types` | Table 5, `Documenttypes` | Ordered comma-separated values | Count must equal `document_type_count` |
| `sdf_scope.user_count` | Table 5, `Gebruikers` | Non-negative integer | Required |
| Project summary, workflow complexity, extra work | Table 5, `Overige scope-afspraken` | Authority text joined into one bounded scope statement | Required authority objects |
| `payment_schedule.milestones[*].amount_minor` | Table 7, selected fixed-package row | EUR formatting; percentages must be exactly `40,40,20` | Required except MAATWERK |
| `payment_schedule.milestones[*].due_terms_days` | Paragraph `Facturen zijn betaalbaar binnen ___ dagen...` | Exact integer, only when all three approved milestone values are identical | Required and must be unambiguous |
| `project_scope.indicative_timing` → `project.indicative_timing` | Unique `Uitvoeringstermijn` paragraph: `De geschatte uitvoeringstermijn tot functionele oplevering/testfase bedraagt ___ weken, te rekenen vanaf ontvangst van de eerste betaling (mijlpaal 1) en ontvangst van alle benodigde input van de klant — niet vanaf ondertekening van deze offerte. Deze termijn is indicatief.` | Renderer formats only the exact approved positive whole number as `<waarde> weken` | Required; project-specific owner approval only; missing or invalid values fail closed |

## Execution-term authority

For SDF, approved authority path `project_scope.indicative_timing` means the project-specific owner-approved indicative period in positive whole weeks from project start to functional delivery/test phase. The owner-only business-draft v2 boundary places it in the immutable canonical approval payload; generation projects it to `project.indicative_timing`. The existing approval-payload SHA-256 and final SDF generation-payload SHA-256 therefore bind the exact value. The renderer only formats this approved value and fails closed when it is missing or invalid. It is not a guaranteed legal completion date unless separately agreed. Package, scope volume, title, free text, and frontend values never provide a default or fallback.

## Structural contract

Before mutation, `word/document.xml` must contain exactly nine tables in the registered order. Every table must match its registered row count, column count, and first-cell labels. Tables 4, 6, and 8 are not changed, but remain part of this structural validation.

Only target cells in tables 1, 2, 3, 5, 7, and 9 plus the uniquely anchored project-description, payment-term, and execution-term paragraphs are changed. All other ZIP parts remain sourced from the official template. ZIP timestamps are fixed to make repeated rendering deterministic.

## Fail-closed behavior

Rendering stops on template hash or identity mismatch, Website payloads, missing scope, package mismatch, unsupported scope versions, malformed XML, table drift or ambiguity, forbidden raw authority data, totals/scope disagreement, milestone disagreement, a missing/non-positive/non-integer execution term, or non-null MAATWERK amounts without a concrete approved authority contract.