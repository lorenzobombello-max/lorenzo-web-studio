# LWS Quotation Technical Master v1

## Identity

- Template ID: `LWS_QUOTATION_NL_BE`
- Template version: `1.0.0-technical`
- Status: `CANDIDATE`
- Locale: `nl-BE`
- Renderer version: `quotation-docx-v1`
- Technical master: `assets/docs/quotation/LWS_QUOTATION_NL_BE_TECHNICAL_v1.docx`
- SHA-256: `3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE`
- Final presentation phase: `DEFERRED`

The technical master is repository-controlled and is not quotation-template authority. It does not replace or modify the protected business source.

## Toolchain

- `docx` creates the valid OpenXML candidate master.
- `docxtemplater` and `pizzip` render disposable local DOCX artifacts.
- Node tests validate required OpenXML parts, relationships, extracted content, tag removal, and leakage exclusions.
- Microsoft Word is used only for optional local PDF visual inspection. No Office configuration is modified.

## Renderer Input

The renderer accepts the D3E5 `PREVIEW_PACKAGE` plus this technical master. Structural ISSUE readiness uses the same D3E4 generation payload contract with an unmistakably synthetic `TEST-LWS-OFF-*` number. The renderer never queries a database.

## Semantic Tags

| Category | Tags |
|---|---|
| PREVIEW | `preview_markers[].primary`, `preview_markers[].secondary` |
| QUOTATION | `issue_identity[].quotation_number`, `quotation_version`, `status` |
| SELLER | `seller.legal_name`, address, enterprise/VAT number, email, website, optional contact |
| CUSTOMER | `customer.legal_name`, contact, address, enterprise/VAT number, email |
| PROJECT | title, type, summary, languages, pages, features, exclusions, assumptions, timing |
| LINES | `lines[]`: description, quantity, unit, formatted unit price/discount/VAT/net amount |
| TOTALS | one-time, recurring, discount, VAT base, VAT amount, gross total |
| VAT | approved rate display only |
| PAYMENT | `payment_milestones[]`: label, approved allocation, trigger, due terms |
| VALIDITY | approved from/until/days |
| LEGAL | customer-visible terms and optional agreement reference/version |
| ACCEPTANCE | `acceptance_instruction` only |

## Repeats And Conditionals

- Repeats: quotation lines, payment milestones, features, exclusions, assumptions.
- Conditionals: preview marker, issue identity, recurring notice, optional seller/customer fields, timing, agreement reference.
- Empty optional values produce no labels, punctuation, placeholder paragraphs, or literal `null`/`undefined`.

## Presentation Adapter

Allowed transformations are nl-BE date, currency, percentage and list formatting; optional-value suppression; and display labels. Money formatting uses integer minor units and `BigInt` division. The adapter cannot calculate prices, choose VAT, alter discounts/scope/payment/validity, create numbers, or convert PREVIEW to ISSUE.

## Security Exclusions

Capability tokens, HMAC data, service-role secrets, raw intake/pricing/approval records, operation ledger data, source hashes and audit-only metadata are forbidden. Tests reject known forbidden keys and scan extracted document text for leakage.

## Known Limitations

- This is a technical baseline, not final customer-facing styling.
- ISSUE rendering is structural only until template authority and issue validation are approved.
- PDF conversion depends on locally installed Microsoft Word and is not part of renderer output.
- Fine typography, branding, spacing and pagination refinement remain deferred.