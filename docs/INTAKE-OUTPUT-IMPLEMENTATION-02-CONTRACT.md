# Intake output implementation 02 contract

Authority baseline: `199bb1c22edd8cbb7d0b60c087e5da5ae6928482`.

## Identity

- Internal authority: `quote_requests.id` UUID.
- Human reference: nullable `quote_requests.application_reference`, format `LWS-AAN-YYYY-NNNN`.
- New references are assigned only on the first intake transition to `submitted`.
- Historical rows remain `NULL`; no historical sequence is fabricated. The secure briefing labels them internally as `Legacy #UUID-prefix` while retaining capability-based authorization.
- The reference is immutable and unique, but is never an authorization credential.
- Existing customer and admin capability tokens remain the only intake access mechanism.

## Field-preservation matrix

| Input group | Persisted source | Customer confirmation | Lorenzo email | Secure admin briefing |
| --- | --- | --- | --- | --- |
| Identity/contact | `quote_requests` | Name/company summary | Full name, company, email, phone | Full identity, contact and business/billing fields |
| Application identity | `quote_requests.application_reference` | Primary identity | Subject and identity section | Primary heading and Application section |
| Package | Snapshot V3 `packageDefinition` | Package label | Commercial section | Application section |
| Budget | Snapshot V3 `budgetEvaluation.originalLabel` | Budget label | Commercial section | Application section |
| Indicative one-time price | Snapshot V3 `calculation.knownMinimumMinor` | Project price, excl. VAT | Commercial section, excl. VAT | Application section, excl. VAT |
| Budget Guard | Snapshot V3 `budgetEvaluation.status` | Intentionally summarized by price/disclaimer | Full status | Full status |
| Care/Care+ | Snapshot V3 `recurringServices` | Applicable service, separately per month | Applicable service, separately per month | Applicable service, separately per month |
| Business/current website/goals | `quote_request_intakes` and `quote_requests` | Intentionally concise | Project section | Full Bedrijf & doelgroep and Doelen sections |
| Pages/forms/functions | `quote_request_intakes` | Key pages, webshop and booking | Website section | Full Pagina's & functies section, including detail objects |
| Languages | `quote_request_intakes` | Main and extra languages | Website section | Full page/language details |
| SEO/integrations | `quote_request_intakes` | Intentionally summarized | Website section | Full SEO & integraties section |
| Branding/logo/design | `quote_request_intakes` | Status summary | Branding & content section | Full Design & branding section |
| Copy/content/media | `quote_request_intakes` | Status summary | Branding & content section and applicable detail object | Full Content & media section and detail objects |
| Hosting/maintenance | `quote_request_intakes` | Applicable service summary | Service & planning section | Full Domein & hosting section |
| Deadline/timing/notes | `quote_request_intakes` and `quote_requests` | Planning summary | Service & planning section | Full Planning & budget and Prioriteiten & opmerkingen sections |
| Technical UUID/HMAC/config hashes | Internal tables | Never exposed | Never exposed | UUID remains available only in the authorized API payload; not primary identity |

All three price representations are built from the validated `integrity_snapshot` returned by `inspect_customer_pricing_read_v3` or `inspect_admin_pricing_read_v3`. No output layer recalculates pricing.

## Future Operator handoff

Operator Room is not implemented in this phase. Its lookup contract is:

`application_reference -> quote_requests.id -> quote_request_intakes.id -> quote_request_pricing_snapshots.intake_id -> customer`

The future **Open in Operator** button attaches where the current submitted-intake email renders **Beveiligde briefing bekijken**. It must use a separately authenticated Operator route; the application reference, UUID and existing briefing capability must not become Operator authorization.