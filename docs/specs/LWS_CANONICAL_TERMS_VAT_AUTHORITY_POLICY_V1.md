# LWS Canonical Terms/VAT Authority Policy v1

Status: Formal technical specification, blocked on identified authority inputs

## 1. Purpose

Canonical Terms/VAT Authority Policy v1 removes legal-terms and VAT authority selection from quotation callers. It defines deterministic, trusted resolution of the terms and VAT authority rows supplied to `upsert_quotation_business_draft_v1`.

The target flow is:

```text
authenticated operator/client action
        |
        v
trusted server / Edge boundary
        |
        +--> canonical terms resolver
        |
        +--> canonical VAT resolver
        |
        v
service-role quotation business builder
        |
        v
upsert_quotation_business_draft_v1
```

The policy is a prerequisite for removing `terms_authority_id` and `vat_decision_authority_id` from the public business-draft request.

## 2. Scope

Version 1 covers only:

- quotation terms family `LWS_GENERAL_TERMS_NL_BE`;
- customers proven by governed server-side context to be in Belgium; and
- Lorenzo Web Solutions' registered Belgian small-enterprise VAT exemption for supported domestic transactions.

Every VAT context not positively proven to satisfy the complete governed v1 eligibility predicate fails closed.

## 3. Non-goals

Version 1 does not support or infer:

- foreign customers;
- EU B2B or intra-Community treatment;
- reverse charge;
- exemptions other than the governed LWS small-enterprise exemption;
- alternative VAT rates or treatments;
- manual operator selection of a VAT or terms authority row;
- a general VAT rules engine;
- net-price calculation;
- approval, issuance, document generation, delivery, acceptance, or promotion changes.

This specification does not define SQL or runtime implementation.

## 4. Existing Authority Context

### 4.1 Existing terms authority

`quotation_terms_authorities` already provides immutable authority rows, family/version identity, content hash and source path, `APPROVED`/`RETIRED` lifecycle, `effective_from`, one approved row per family, and governed owner/admin replacement. The production migration seeds `LWS_GENERAL_TERMS_NL_BE` version `1.0` as approved. No canonical resolver exists.

### 4.2 Existing VAT authority

`quotation_vat_decision_authorities` provides immutable authority rows, decision family/version identity, treatment, rate, source identifier, approved/retired lifecycle, one approved row per family, and governed owner/admin replacement.

It does not provide a production canonical Belgian exemption family, governed production seed, effective date, compatibility contract, or context resolver. Repository occurrences of rate `21` are test fixtures with sources such as `TEST_ONLY` and `accountant:test`; they are not production authority evidence and must not determine current LWS VAT treatment.

### 4.3 Authoritative LWS and fiscal evidence

The archived Liantis creation dossier records:

- activity start date `08/08/2026`;
- activities normally subject to VAT;
- registered VAT regime `Vrijstelling`;
- initial estimated annual turnover `EUR 2,500 excluding VAT`.

The primary fiscal source is FOD Financiën, [BTW-vrijstellingsregeling kleine ondernemingen](https://financien.belgium.be/nl/ondernemingen/btw/btw-plicht/vrijstellingsregeling). That page directly links the official [Brochure - 9 vragen omtrent de btw-vrijstellingsregeling voor kleine ondernemingen - Editie 2026](https://www.minfin.fgov.be/myminfin-web/pages/public/fisconet/document/0cb8f71e-6522-47c2-9134-8c15300d3507). The authority establishes that an eligible enterprise remains a VAT taxable person with a VAT identification number, charges no VAT to customers, remits no outgoing VAT to the Treasury, cannot deduct input VAT, and retains applicable invoicing obligations.

The exact exemption invoice literal could not be independently recovered from the publicly rendered brochure content during specification review. It is therefore not production authority in this version: `AUTHORITY INPUT REQUIRED - OFFICIAL EXEMPTION INVOICE WORDING`. Governed approval must record the exact literal, brochure edition, specific question/section/page or equivalent stable location, and authority-source reference before implementation planning can authorize document projection.

The general annual turnover threshold is `EUR 25,000 excluding VAT`. For an activity starting during 2026, FOD prescribes reduction in proportion to calendar days elapsed between 1 January 2026 and the activity start date. For `08/08/2026`, 219 days elapsed:

```text
EUR 25,000 - (EUR 25,000 x 219 / 365) = EUR 10,000
2026 PRO-RATA THRESHOLD = EUR 10,000
```

### 4.4 Existing builder behavior

`upsert_quotation_business_draft_v1` requires caller-supplied terms and VAT authority IDs and verifies only that selected rows are approved. Approved uniqueness is per family, so the caller can select another approved family. The builder does already persist resolved IDs and canonical terms/VAT semantics in immutable draft evidence.

## 5. Canonical Terms Policy

The only canonical terms family is `LWS_GENERAL_TERMS_NL_BE`.

Resolution requirements:

1. Family identity is fixed server-side.
2. Only that family and `APPROVED` status qualify.
3. `effective_from` is on or before the trusted resolution date.
4. Retired rows never qualify for new/rebuilt drafts.
5. Exactly one compatible row must exist; zero or multiple matches fail closed.
6. Clients cannot supply terms ID, version, hash, path, status, or date.

Existing drafts retain their originally persisted authority. New versions affect only later authorized revisions or new quotation lifecycles.

## 6. Belgian Small-Enterprise VAT Exemption Policy

The canonical v1 family identifier is `BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION`. This uppercase semantic key follows existing `decision_code`/authority naming and names the governed regime, not a general VAT rate.

Selection is permitted only when trusted context positively satisfies the governed domestic eligibility predicate. Required row properties are:

- `decision_code = BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION`;
- jurisdiction `BE`;
- regime `SMALL_ENTERPRISE_EXEMPTION`;
- outgoing VAT charged `0`;
- exemption wording: `AUTHORITY INPUT REQUIRED - OFFICIAL EXEMPTION INVOICE WORDING`;
- primary fiscal provenance pointing to the FOD authority and official 2026 brochure;
- business-evidence provenance pointing to the archived Liantis creation dossier;
- exactly one compatible, effective, approved version;
- effective-date and policy-compatibility identity;
- immutable content and retirement/replacement metadata.

The exemption leaves the frozen commercial amount unchanged: VAT charged is zero and the customer total equals the authoritative frozen amount. It does not classify that amount as VAT-inclusive and does not introduce a package price. No customer document may be finalized under this policy until the governed exemption literal is approved and immutably bound.

The v1 effective date is the LWS activity start date `08/08/2026`. The initial technical version identifier may follow repository migration conventions; activation remains an explicit governed owner/admin action. No ordinary-rate fallback is allowed.

## 7. Trust Boundary

Clients cannot authoritatively supply terms/VAT authority IDs, family, version, hash, treatment, rate, source, seller, template, policy, lifecycle state, or timestamps.

The operator boundary verifies the human JWT and derives `actorAuthUserId`. Trusted server code invokes service-role-only resolvers. SQL remains the final owner/admin authorization boundary. Resolver output is internal and both resolutions must succeed before the builder is called.

## 8. Resolver Contracts

Two resolvers match the existing authority-family architecture.

### 8.1 `resolve_quotation_terms_authority_v1`

Inputs: trusted resolution timestamp and server-fixed nl-BE quotation contract. No client family/ID input.

Execution: service-role only; no browser grant. A SQL `SECURITY DEFINER` implementation uses a fixed safe search path and qualified sensitive references.

Output: one internal row with authority ID, family, version, hash, source path, and effective date.

Selection: fixed family, approved, effective, policy-compatible, exactly one.

Errors:

- zero or retired-only: `QUOTATION_TERMS_NOT_APPROVED`;
- multiple: `QUOTATION_TERMS_AUTHORITY_AMBIGUOUS`;
- incompatible/not effective: `QUOTATION_TERMS_AUTHORITY_INCOMPATIBLE`.

### 8.2 `resolve_quotation_vat_authority_v1`

Inputs: trusted quote-request/intake identity, trusted timestamp, server-fixed policy version. The resolver loads persisted context itself; no client context or authority selector is accepted.

Execution: service-role only, read-only, no browser grant, fixed safe search path if security definer.

Output: one internal row with authority ID, decision family/version, treatment, rate, source, effective identity, and compatibility identity.

Selection:

1. Load request through trusted intake binding.
2. Evaluate the governed v1 eligibility predicate.
3. Reject missing, foreign, exceptional, or unsupported context.
4. Require trusted evidence that the active LWS regime is the small-enterprise exemption and that no governed transition/review state is open.
5. Select only `BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION`.
6. Require exactly one compatible, effective, approved row.
7. Never fall back to another approved family or ordinary VAT treatment.

Errors:

- missing context: `QUOTATION_VAT_CONTEXT_REQUIRED`;
- unsupported context: `QUOTATION_VAT_CONTEXT_UNSUPPORTED`;
- zero: `QUOTATION_VAT_DECISION_NOT_APPROVED`;
- retired-only: `QUOTATION_VAT_AUTHORITY_RETIRED`;
- multiple: `QUOTATION_VAT_AUTHORITY_AMBIGUOUS`;
- incompatible/not effective: `QUOTATION_VAT_AUTHORITY_INCOMPATIBLE`.
- governed regime transition pending: `QUOTATION_VAT_REGIME_TRANSITION_REQUIRED`;
- threshold authority uncertain/review pending: `QUOTATION_VAT_THRESHOLD_AUTHORITY_REVIEW_REQUIRED`.

Existing unavailable/not-approved codes are reused. The policy vocabulary explicitly includes context, ambiguity, compatibility, retired/not-approved, threshold-classification/review, and VAT-regime-transition states.

## 9. Required Business Context

Current persisted fields are `customer_type`, `billing_country`, billing address/postal code/city, `enterprise_number`, `enterprise_validation_status`, `vat_number`, `vat_validation_status`, and `vat_validated_at`. Intake is authoritatively bound to the request. The authority resolver additionally requires server-owned current LWS regime evidence, effective date, threshold state, and transaction classification.

The v1 transaction classification key is `SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION`. Existing context can only prequalify a request when all of these conditions hold:

1. `customer_type = business`.
2. Normalized `billing_country` matches the existing repository-recognized Belgian values `BE`, `Belgie`, `België`, or `Belgium`, case-insensitively.
3. Required persisted business identity and billing fields are present under existing constraints.
4. Current LWS authority is `BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION`, effective for the transaction time.
5. A server-owned transaction classification equals `SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION` and records its governed source, classifier/audit actor, and classification timestamp.
6. No threshold review or VAT-regime transition state is open.

Existing fields do not prove the absence of reverse charge, intra-Community treatment, an excluded transaction, or another special VAT treatment. The minimum later-required business-context field is therefore a server-owned `vat_transaction_classification` (or repository-conformant equivalent) whose only auto-resolvable v1 value is `SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION`. It cannot be copied from browser input or inferred solely from country/VAT-number presence.

Missing `customer_type`, missing/blank `billing_country`, `customer_type = individual`, or absent server-owned classification produces `QUOTATION_VAT_CONTEXT_REQUIRED`. A non-Belgian `billing_country`, any classification other than the supported value, or evidence of foreign/EU cross-border, reverse charge, intra-Community special treatment, or excluded/special treatment produces `QUOTATION_VAT_CONTEXT_UNSUPPORTED`. Unknown or conflicting evidence fails closed; no default is permitted.

VAT-number presence and `vat_validation_status` support identity validation but do not independently select fiscal treatment. The exact inclusion/exclusion classification must be governed before the supported value is assigned.

## 10. Schema Impact

Preferred approach: one minimal additive authority/resolver migration, not a VAT engine.

- Retain both existing authority tables and immutable lifecycle.
- Add no terms table; add a canonical terms resolver.
- Add VAT effective-date and minimal immutable policy-compatibility metadata because the current schema lacks them.
- Seed `BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION` with governed LWS/FOD provenance, zero outgoing VAT, approved wording only after its authority input is closed, jurisdiction, regime, effective date, lifecycle, and replacement metadata.
- Add a server-owned LWS regime/threshold authority record if no existing governed source can provide current status atomically.
- Add the minimal server-owned transaction-classification record required by section 9; browser/client roles cannot write it.
- Add a canonical VAT resolver and defensive exact-one checks.
- Preserve per-family approved uniqueness; add effective uniqueness only if intervals are introduced.
- Use an atomic wrapper/evolved builder so authority rotation cannot race resolution and draft creation.

## 11. Governed Seed Model

Future production VAT seed:

- decision code: `BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION`;
- jurisdiction: `BE`;
- regime: `SMALL_ENTERPRISE_EXEMPTION`;
- version: repository-conformant initial immutable version;
- state: `APPROVED` at governed activation;
- outgoing VAT charged: `0`;
- exemption wording: `AUTHORITY INPUT REQUIRED - OFFICIAL EXEMPTION INVOICE WORDING`;
- fiscal source: FOD Financiën exemption authority and official 2026 brochure;
- business source: archived Liantis creation dossier;
- effective date: `08/08/2026`;
- compatibility: policy v1 plus supported Belgian domestic transactions only;
- complete approval audit metadata.

Owner/admin activation atomically retires the current family version and inserts its immutable replacement. Historical rows remain immutable and addressable.

### 11.1 Turnover authority

Forecasts are never threshold authority. The Liantis initial estimate and later KBC `EUR 15,000` forecast can motivate monitoring but cannot change a threshold state or VAT regime.

`realized_relevant_turnover` means only factually realized turnover classified as relevant to the legal threshold by the governing VAT authority. It must come from an immutable governed accounting/commercial snapshot with source identity, covered period, currency, included transaction references, excluded transaction references, classification authority, generated-at timestamp, and content hash. Browser values, free counters, operator-entered totals, and forecasts are prohibited.

If existing authority does not determine whether a turnover category is legally included, that amount cannot be silently included or excluded. Resolution enters `AUTHORITY_REVIEW_REQUIRED` and fails with `QUOTATION_VAT_THRESHOLD_CLASSIFICATION_REVIEW_REQUIRED` until governed classification evidence exists.

### 11.2 Threshold state machine

The state machine uses applicable threshold `T` and governed cumulative realized relevant turnover `R`, where `R` includes the governed amount of the transaction being evaluated. The pre-transaction cumulative amount remains separately recorded so the first crossing transaction is deterministic:

- `EXEMPT_ACTIVE_BELOW_THRESHOLD`: `R <= T`; exemption remains active and no transition occurs.
- `EXEMPT_ACTIVE_WITHIN_10_PERCENT_OVERRUN`: authority has explicitly approved application of the 10% rule to the applicable `T`, and `T < R <= 1.10 x T`; exemption may remain active through the current calendar year and records normal-regime transition from the next calendar year.
- `NORMAL_REGIME_REQUIRED_NEXT_CALENDAR_YEAR`: the governed effective point at the start of the next calendar year has arrived after an approved within-10% overrun. Exemption resolution is prohibited.
- `NORMAL_REGIME_REQUIRED_FROM_TRIGGERING_TRANSACTION`: governed evidence proves an overrun above the applicable 10% boundary; the transaction that first crosses that boundary and all later transactions cannot use exemption authority.
- `AUTHORITY_REVIEW_REQUIRED`: turnover evidence is missing/stale/conflicting, a turnover category is unclassified, the triggering transaction cannot be identified, the invoice literal is unapproved, or the relevant threshold/overrun rule is not authoritatively established. New documents fail closed.

For 2026, `T = EUR 10,000`, derived from `EUR 25,000 - (EUR 25,000 x 219 / 365)`. The official FOD page states the 10% overrun rule for the general threshold but does not unambiguously establish in the recovered evidence that `1.10 x T` applies to a pro-rata start-year threshold. Therefore this specification does not authorize `EUR 11,000` as an implementation boundary. Any 2026 realized relevant turnover above `EUR 10,000` enters `AUTHORITY_REVIEW_REQUIRED` with `AUTHORITY REVIEW REQUIRED - 10% OVERRUN ON PRO-RATA START-YEAR THRESHOLD` until direct governed authority closes that question.

The official general rule is retained as future governed transition semantics: an authority-proven overrun of at most 10% leads to normal regime from the next calendar year; an authority-proven overrun above 10% leads to normal regime from the transaction that triggers the overrun. Neither state supplies a VAT rate. Exemption resolution fails closed until the correct new governed VAT authority/version is effective; no automatic ordinary-rate or 21% switch is permitted.

### 11.3 Transition evidence

Every transition record binds `detected_at`, realized-turnover snapshot/reference and hash, applicable threshold authority, triggering transaction when relevant, transaction-bound or date/time `effective_from`, old VAT authority/version, new VAT authority/version when approved, authority-review/audit actor, reason, and source. The triggering transaction is the first governed included transaction whose cumulative realized relevant turnover crosses the authority-approved boundary. If that identity is not provable, resolution enters `AUTHORITY_REVIEW_REQUIRED`.

Historical documents before the effective transition point retain their original immutable VAT and terms authority. The triggering and later transactions cannot be completed under exemption when `NORMAL_REGIME_REQUIRED_FROM_TRIGGERING_TRANSACTION` applies. A required transition with no approved new authority fails with `QUOTATION_VAT_REGIME_TRANSITION_REQUIRED`.

## 12. Error Model

| Condition | Stable code |
|---|---|
| Missing VAT context | `QUOTATION_VAT_CONTEXT_REQUIRED` |
| Unsupported/foreign/special context | `QUOTATION_VAT_CONTEXT_UNSUPPORTED` |
| Terms unavailable | `QUOTATION_TERMS_NOT_APPROVED` |
| Terms retired/non-approved | `QUOTATION_TERMS_NOT_APPROVED` |
| Terms genuinely incompatible/not effective | `QUOTATION_TERMS_AUTHORITY_INCOMPATIBLE` |
| Terms ambiguous | `QUOTATION_TERMS_AUTHORITY_AMBIGUOUS` |
| VAT unavailable | `QUOTATION_VAT_DECISION_NOT_APPROVED` |
| VAT retired | `QUOTATION_VAT_AUTHORITY_RETIRED` |
| VAT ambiguous | `QUOTATION_VAT_AUTHORITY_AMBIGUOUS` |
| VAT incompatible/not effective | `QUOTATION_VAT_AUTHORITY_INCOMPATIBLE` |
| Governed VAT transition pending | `QUOTATION_VAT_REGIME_TRANSITION_REQUIRED` |
| Threshold authority uncertain/review pending | `QUOTATION_VAT_THRESHOLD_AUTHORITY_REVIEW_REQUIRED` |
| Turnover inclusion/exclusion unclassified | `QUOTATION_VAT_THRESHOLD_CLASSIFICATION_REVIEW_REQUIRED` |

Expected context/authority failures map to stable non-500 responses without SQL detail. Unexpected technical failures remain `500 INTERNAL_ERROR`.

## 13. Security

- Family identifiers are fixed server-side.
- Resolution uses persisted data, never duplicated client context.
- Privileged resolver execution is service-role only unless a narrower trusted role is established.
- RLS and FORCE RLS remain enabled; browser roles receive no table or privileged resolver access.
- Security-definer functions use fixed safe search paths, qualified references, and minimal grants.
- Authority history is immutable; lifecycle changes remain governed owner/admin operations.
- Zero, multiple, retired, future, or incompatible states fail closed.
- Clients cannot set exemption reason/wording, threshold state, realized turnover, or regime transition state.

## 14. Historical Stability / Idempotency

Draft creation freezes terms ID/family/version/hash and VAT ID/family/version/treatment/rate/source/effective/compatibility identity. It also freezes the approved exemption wording authority, transaction classification, applicable threshold authority, and transition-state reference used for the decision. The draft record and canonical payload preserve this evidence.

A replay returns original bindings and never re-resolves to a newer version. New versions apply only to new operations/rebuilt revisions under existing revision rules. Existing approvals, issuances, and quotations remain unchanged.

Resolution and build must share one database transaction, or a combined service-role orchestration must resolve then call the builder atomically. Separate Edge lookups followed by an unguarded RPC are insufficient because authority rotation could race the operation.

Realized-turnover monitoring can raise a warning or fail-closed review state but cannot itself choose a rate or replace the registered regime. A governed regime transition activates a new immutable authority version. Existing quotations and invoices retain the exemption authority frozen when they were created.

## 15. Runtime Integration Contract

After authority implementation, `commercial-operator-command` rejects `terms_authority_id` and `vat_decision_authority_id` as unknown client fields.

```text
validated operator input
  -> verified actorAuthUserId
        -> trusted jurisdiction/context resolution
        -> atomic trusted terms/VAT policy resolution
  -> server-injected canonical IDs
  -> upsert_quotation_business_draft_v1
```

The current builder may retain internal ID parameters only if clients cannot choose them and canonical status/family/effectiveness are transactionally revalidated.

The extensibility boundary is:

```text
customer/business context
        -> jurisdiction resolver
        -> VAT policy
        -> terms/document variant
        -> quotation/invoice
```

Netherlands, France, and other EU jurisdictions can later add separate governed policies without changing historical Belgian evidence. Version 1 defines no foreign or EU VAT policy.

Still-open later runtime corrections:

1. remove selector fields from the client contract;
2. align Edge validation with SQL, including non-empty languages and valid non-empty milestones and removal of non-authoritative text limits;
3. map known business/pricing fail-closed errors to stable non-500 responses.

## 16. Test Strategy

Terms tests: one canonical approved effective row succeeds; zero, two, retired, future, incompatible, or another family fail closed.

VAT tests: only the exact supported Belgian business predicate plus server-owned transaction classification resolves canonically, charges zero outgoing VAT, and preserves the frozen amount. Missing/individual/non-Belgian, foreign, cross-border, reverse-charge, special, unclassified, zero-authority, ambiguous, retired, future, incompatible, transition-pending, threshold-review, or another-family cases fail closed. Document projection remains blocked until the exact exemption wording authority is approved.

Security tests: clients cannot choose IDs, rate, treatment, terms version/hash, or execute privileged resolvers; verified actor is preserved.

Historical tests: replacement does not alter existing quotations; retry returns original bindings; new revision may bind the new version; concurrent rotation cannot bind a retired/noncanonical row.

Threshold tests: the `08/08/2026` start produces the `EUR 10,000` pro-rata threshold; forecasts never change state; governed realized relevant turnover at/below `T` remains exempt; unclassified turnover fails review; 2026 turnover above `T` fails authority review while pro-rata 10% applicability is unresolved; authority-proven within-10% and above-10% fixtures exercise their respective transition states; triggering-transaction identity is mandatory; no automatic ordinary-rate fallback exists.

Price tests: frozen snapshot remains amount authority; exemption never changes lines/subtotal; VAT charged is zero; customer total equals the frozen amount; unresolved `FROM`/manual pricing still fails; no package-price map exists.

## 17. Migration/Implementation Scope

Future minimal implementation:

1. additive VAT effective/compatibility metadata;
2. governed exemption production seed and LWS regime/threshold evidence;
3. canonical terms and VAT resolvers;
4. atomic trusted wrapper/evolved builder;
5. service-role-only grants and preserved RLS;
6. focused SQL authority/security/history tests;
7. subsequent remediation of the existing three runtime files and focused Deno tests.

No generic VAT engine, foreign/EU policy, or other quotation phase belongs here.

## 18. Governed Transition Inputs

The registered exemption and base-threshold inputs are closed by the archived Liantis evidence and official FOD authority. Two authority inputs remain open and block implementation planning:

1. `AUTHORITY INPUT REQUIRED - OFFICIAL EXEMPTION INVOICE WORDING`, with exact brochure location.
2. `AUTHORITY REVIEW REQUIRED - 10% OVERRUN ON PRO-RATA START-YEAR THRESHOLD`.

After those inputs are closed, runtime implementation must still fail closed unless its governed data model can prove:

1. current registered LWS VAT regime and effective interval;
2. current governed realized-relevant-turnover snapshot and threshold state;
3. supported Belgian domestic transaction classification;
4. absence of excluded, cross-border, reverse-charge, or special treatment;
5. completion of any manual/governed regime transition.

These are operational authority states to implement under this specification. No implementation may infer either remaining fiscal-policy input.

## 19. Explicit Exclusions

The policy does not authorize test rates as production authority, ordinary-rate treatment for the current LWS regime, general-knowledge defaults, treatment derived solely from country or VAT-number presence, operator/client fiscal classification, automatic regime switching, foreign/EU/reverse-charge/special cases, alternative rates, net/package pricing, or any runtime/migration/deployment work in this specification phase.

Price invariants:

```text
€1.500 PACKAGE AUTHORITY PRESENT: NO
HARDCODED PACKAGE PRICES: NONE
AUTHORITATIVE EXACT PRICE SOURCE: frozen pricing snapshot
```
