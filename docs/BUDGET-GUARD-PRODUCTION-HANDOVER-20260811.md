# Budget Guard Production Handover

## Status

- Datum: 2026-08-11
- Project: Lorenzo Web Solutions / `lorenzo-web-studio`
- Branch: `main`
- Eindstatus: **BUDGET GUARD / PRICING PREVIEW BUG = RESOLVED AND PRODUCTION VERIFIED**
- Git-authority: `HEAD == origin/main == cafb7a65e39b99ada5cdd5513f7958610b6b34d6`
- Deze handover vult `docs/PRODUCTION-BASELINE.md` aan voor deze afgeronde debuggingketen. Zij overschrijft geen bredere roadmap-, database- of juridische authority.

## Oorspronkelijk Productieprobleem

De Budget Guard gaf voor de concrete combinatie:

- budget: `Minder dan EUR 1.800`;
- pakket: Professional (`professional_v1`);

aanvankelijk terug:

- `selectedBudgetCategoryCode = null`;
- `comparisonStatus = "INDETERMINATE"`.

De request bevatte toen wel `budget_update_category` en `selected_package_definition_id`, maar niet de vereiste scheme/code-evidence.

## Eerdere HTTP 503-problematiek

- De eerdere HTTP 503-problematiek is afzonderlijk opgelost.
- Zij was niet de finale oorzaak van de ontbrekende budget-evidence.
- Recente Function-invocations tijdens de gecontroleerde productieanalyse gaven `POST 200` en `OPTIONS 204`.
- Begin een volgende sessie voor dit probleem niet opnieuw bij de eerdere 503.

## Serializer Root Cause

De oude `assets/js/intake.js` gebruikte deze gate:

```js
if (budgetCode && (budgetChoiceChanged || restoredBudgetEvidence)) {
```

Bij een restored legacy budget en een package-only wijziging gold:

- het zichtbare budgetlabel was herkend;
- `budgetChoiceChanged` was `false`;
- `restoredBudgetEvidence` was `null`;
- daardoor werden `budget_update_category_scheme` en `budget_update_category_code` nooit aan `collectData()` toegevoegd.

`collectPricingEvidence()` verwijderde deze velden niet. De velden bestonden al niet in de serializeroutput en konden daarom ook niet in de requestbody terechtkomen.

## Eerste Frontendfix

De serializer-gate is gewijzigd naar:

```js
if (budgetCode) {
```

Commit:

- `7683d511b8ec06cbcb76b0a01697d3af0d81eb3f`
- message: `fix: serialize recognized budget evidence`

De fix zorgt ervoor dat elk herkend budgetlabel altijd het coherente triplet serialiseert:

- `budget_update_category`;
- `budget_update_category_scheme = "budget_guard_v1"`;
- de bijbehorende `budget_update_category_code`.

Onbekende labels krijgen geen fabricated code.

## Waarom De Eerste Live Test Toch Faalde

De eerste handmatige live test na commit `7683d511` bouwde de request aantoonbaar op volgens de pre-fix JavaScriptlogica. De oude runtime produceerde exact de waargenomen onvolledige payload; de nieuwe runtime kon die payload niet produceren.

De huidige origin leverde tijdens de analyse inmiddels wel de correcte fixasset. Niet afzonderlijk bewezen is of de oude uitvoeringscontext afkomstig was van:

- een reeds geopende browsertab; of
- de browser-HTTP-cache.

Deze twee mogelijkheden hoeven niet opnieuw uit elkaar te worden onderzocht voor deze afgesloten bug.

## Structurele Cache-Busting Fix

In `pages/intake.html` is de scriptreferentie gewijzigd van:

```html
<script defer src="../assets/js/intake.js"></script>
```

naar:

```html
<script defer src="../assets/js/intake.js?v=20260811-1"></script>
```

Commit:

- `cafb7a65e39b99ada5cdd5513f7958610b6b34d6`
- message: `fix(intake): version intake script asset`

GitHub Pages:

- workflow: `Deploy Static Site to GitHub Pages`;
- run: `#75`;
- run ID: `31455089120`;
- build: **SUCCESS**;
- deploy: **SUCCESS**;
- live HTML verwijst naar `../assets/js/intake.js?v=20260811-1`;
- de versie-URL geeft HTTP 200;
- de versie-asset bevat `if (budgetCode)`;
- de oude gate is afwezig in de versie-asset.

## Finale Productie-evidence

De finale handmatige productietest is uitgevoerd op de echte persoonlijke intake. Er is bewezen dat de requestpayload onder `data` bevatte:

```text
budget_update_category = "Minder dan EUR 1.800"
budget_update_category_code = "below_1800"
budget_update_category_scheme = "budget_guard_v1"
selected_package_definition_id = "professional_v1"
```

De finale response bevatte bewezen:

```text
selectedBudgetCategoryCode = "below_1800"
comparisonStatus = "KNOWN_MINIMUM_ABOVE_BUDGET"
knownMinimumMinor = 320000
knownMinimumExceedsBudget = true
selectedPackageDefinitionId = "professional_v1"
```

Daarmee is de oorspronkelijke combinatie niet langer `INDETERMINATE`: het gekozen budget ligt aantoonbaar onder het bekende Professional-minimum.

## Commerciele Prijsauthority

- Starter: vanaf EUR 1.800 excl. btw.
- Professional: vanaf EUR 3.200 excl. btw.
- EUR 1.500 mag niet opnieuw als publieke instapprijs of budgetminimum worden geintroduceerd.

## Validatieketen

Voor de serializer- en cache-bustingwijzigingen zijn onder meer uitgevoerd:

- focused serializer-tests: 3/3 geslaagd;
- `node --check assets/js/intake.js`: geslaagd;
- `git diff --check`: geslaagd;
- lokale Pages allowlist-build: geslaagd;
- Pages-verificatie: 0 forbidden files, 0 broken links, 0 metadata mismatches, 0 ontbrekende vereisten en 0 gepubliceerde legacy paths;
- GitHub Pages workflow `#75`: build en deploy geslaagd;
- live HTML- en versie-assetcontrole: geslaagd;
- finale handmatige productiecontrole van payload, response en Budget Guard: geslaagd.

## Beschermde Lokale Worktree

De volgende reeds bestaande modified/untracked paden horen niet bij deze handover of de afgesloten cache-bustingcommit. Laat ze bij vervolgwerk ongemoeid en buiten staging totdat hun eigen taak expliciet wordt hervat:

```text
README.md
assets/js/admin-intake.js
assets/js/review-request.js
docs/PRODUCTION-BASELINE.md
pages/algemene-voorwaarden.html
pages/cookies.html
pages/demos/nova-estate/index.html
pages/privacy.html
supabase/functions/_shared/email-templates.test.ts
supabase/functions/_shared/email-templates.ts
supabase/functions/_shared/preview-rate-limit.test.ts
supabase/functions/_shared/preview-rate-limit.ts
supabase/functions/_shared/pricing-preview-handler.test.ts
supabase/functions/_shared/pricing-preview-handler.ts
assets/images/branding/logo/ChatGPT Image 7 aug 2026, 21_01_13.png
assets/images/branding/social/Instagram_LorenzoWebSolution.jpg
pages/redesign-preview/index.html
supabase/.branches/_current_branch
```

Controleer voor elke toekomstige stagingactie opnieuw `git status --short --untracked-files=all` en `git diff --cached --name-only`.

## Hervattingspunt

- Budget Guard-debugging is afgesloten.
- Begin niet opnieuw bij de eerdere HTTP 503 of bij de cachebug.
- Hervat de normale roadmap/faseplanning vanaf de actuele projectstatus.
- Er is in de huidige repositorydocumentatie en Git-history geen expliciete actuele authority voor fase 3.2D gevonden.
- Controleer daarom eerst read-only wat de actuele status van fase 3.2D is voordat verdere implementatie start.
- Vergelijk daarbij de actuele worktree, Git-history en relevante projectcheckpoints zonder bestaande lokale wijzigingen te overschrijven.
- Start geen functionele ontwikkeling totdat die read-only fase-status is vastgesteld en de vervolgstap expliciet is geautoriseerd.