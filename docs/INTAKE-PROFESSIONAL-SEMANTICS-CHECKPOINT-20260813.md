# Intake Professional Semantics Checkpoint

## Identificatie

- Project: Lorenzo Web Solutions
- Datum: 2026-08-13
- Scope: Professional recommendation-presentatie en permanente pricingregressies
- Git-baseline voor deze fase: `fc640a113048ac7554fc8a239146ef9c2d16431c`
- Relatie tot eerdere evidence: aanvulling op `BUDGET-GUARD-PRODUCTION-HANDOVER-20260811.md`; historische evidence blijft behouden.

## Professional semantic fix

### Probleem

Wanneer de gebruiker Professional al expliciet had geselecteerd, kon de customer-facing Budget Guard nog tonen dat Professional interessanter kon zijn en dat geen pakket automatisch was geselecteerd. Het pakket was werkelijk geselecteerd; de recommendation was daardoor redundant en verwarrend.

### Root cause

De engine berekent `packageAdvice = consider_professional` uitsluitend op basis van het aantal standaardpagina's. De frontend presenteerde die advice zonder te controleren of `professional_v2` al geselecteerd was.

### Oplossing

De frontend onderdrukt alleen de `CONSIDER_PROFESSIONAL`-presentatie wanneer:

```text
selectedPackageDefinitionId = professional_v2
and packageAdvice = CONSIDER_PROFESSIONAL
```

Professional blijft geselecteerd en zichtbaar. Pricing, package thresholds, payloads, Budget Guard-berekening en recommendationlogica blijven ongewijzigd. Als Professional niet geselecteerd is, blijft de relevante recommendation zichtbaar.

## Multilingual pricing authority

### Normale catalogiseerbare scope

Voor normale meertaligheid gelden de bestaande catalogusregels:

- eerste extra taal: vast `+ EUR 650`;
- tweede extra taal: vast `+ EUR 450`;
- elke volgende extra taal: vast `+ EUR 450`.

De regels gelden wanneer definitieve vertalingen worden aangeleverd, elke taal dezelfde structuur gebruikt, vertaling niet nodig is en geen complexe taalscope aanwezig is.

### Manual scope

Wanneer definitieve vertalingen niet worden aangeleverd en vertaling nodig is, classificeert normalization de multilingual module als `manual`:

- normale extra-language rules worden niet toegepast;
- bekende taalbijdrage blijft `EUR 0`;
- `translation` blijft manual;
- manual review wordt geactiveerd.

Dit is geen prijs van EUR 0 voor het uiteindelijke werk. Het betekent dat het onbekende taalwerk persoonlijk geprijsd wordt boven op het bekende minimum.

## Geautomatiseerd E2E-resultaat

De lokale review gebruikte uitsluitend lokaal transport en de echte repositoryketen:

```text
UI input
-> collectData
-> pricing input validation
-> normalization
-> pricing engine
-> preview DTO
-> Budget Guard rendering
```

Er werd geen vaste `knownMinimumMinor` gemockt. De lokale transport/authcontext was synthetisch en in-memory; er is geen productiecall of write uitgevoerd.

### Normal forward/reverse met Professional

| State | Taalbijdrage | Bekend minimum |
|---|---:|---:|
| NL | EUR 0 | EUR 3.500 |
| NL + FR | EUR 650 | EUR 4.150 |
| NL + FR + EN | EUR 1.100 | EUR 4.600 |
| NL + FR + EN + DE | EUR 1.550 | EUR 5.050 |
| reverse naar NL + FR + EN | EUR 1.100 | EUR 4.600 |
| reverse naar NL + FR | EUR 650 | EUR 4.150 |
| reverse naar NL | EUR 0 | EUR 3.500 |

Resultaat: PASS. DOM-bedrag, normalized scope, applied rules en engine-uitkomst bleven gelijk per revision.

### Manual multilingual

Voor `final_translations_supplied = false`, `translation_required = true` en `same_structure = true`:

- NL + FR: bekend minimum EUR 3.500;
- NL + FR + EN: bekend minimum EUR 3.500;
- NL + FR + EN + DE: bekend minimum EUR 3.500;
- classification: `manual`;
- language ladder: afwezig;
- translation: manual;
- Budget Guard: essentieel maatwerk te beoordelen.

Resultaat: PASS.

## Permanente regression coverage

De volgende permanente regressies zijn toegevoegd aan bestaande tests:

- normale multilingual A -> B -> C -> B -> A bedragen en classification;
- manual multilingual A -> B -> C -> B -> A zonder bekende taalbijdrage;
- translation manual en manual-reviewredenen;
- fingerprintwijzigingen per scopewijziging;
- actuele revision wordt geaccepteerd;
- stale en aborted responses worden geweigerd;
- Professional-selected houdt het pakket zichtbaar en onderdrukt redundante advice;
- Starter-selected behoudt relevante Professional-advice;
- opeenvolgende Starter -> Professional rendering wist oude advice uit de print-zichtbare DOM;
- intake-script cachekey is verhoogd zodat een latere release de nieuwe frontendcode ophaalt.

Native Deno was in de uitvoeringsomgeving niet beschikbaar en is niet geinstalleerd. De relevante functionele assertions zijn zelfstandig uitgevoerd via Node's TypeScript-loader, frontend function harnesses, echte lokale browserautomatisering en de officiële Pages-verificatie.

## Historical EUR 5.000 PDF case

De taalvraag is verklaard: manual multilingual scope zorgde ervoor dat FR -> FR+EN -> FR+EN+DE het bekende minimum niet verhoogde.

De ontbrekende historische bijdrage van EUR 450 blijft `AMBIGUOUS`. De PDF's tonen niet alle pricingvelden uit stappen 4 tot en met 10. Er is geen historische fixture verzonnen en er mag geen unieke oorzaak worden vastgelegd zonder authoritative payload of snapshot.

## LWS testing policy

Technisch reproduceerbare validatie wordt voortaan door VS/testautomatisering uitgevoerd voordat Lorenzo om handmatige validatie wordt gevraagd.

VS test zelfstandig waar technisch veilig mogelijk:

- pricingcombinaties en intakevelden;
- package states en multilingual scope;
- manual review en Budget Guard;
- state/reactivity en forward/reverse transitions;
- stale/aborted responses;
- links, assets, console en network;
- responsive technische checks en regressietests.

Lorenzo is primair nodig voor:

- visuele goedkeuring;
- UX- en smaakbeoordeling;
- zakelijke beslissingen;
- expliciete autorisatie voor gevoelige productiehandelingen.

Grote reeksen checkbox- of pricingtests worden niet opnieuw handmatig aan Lorenzo gevraagd wanneer ze technisch reproduceerbaar zijn.

## Release gates

Lokale code, regressieharnesses, echte lokale pricingreview, diagnostics, JavaScriptsyntax, `git diff --check` en officiële Pages build/security/linkverificatie waren voor staging groen. Productieclosure vereist daarnaast een succesvolle GitHub Pages build/deploy en read-only live validatie van de releasecommit.
