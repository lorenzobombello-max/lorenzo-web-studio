# Official SDF quotation template mapping v1

## Authority

- Repository asset: `assets/docs/quotation/LWS_SDF_QUOTATION_NL_BE_OFFICIAL_v1.docx`
- SHA-256: `33da6dbbeef02876d0624d28fb17a16787cb1e7d0bde8ee74026664ba7739c1d`
- Size: 178977 bytes
- Product: `slimme_documentenflow`
- Template identity: `LWS_SDF_QUOTATION_NL_BE` / `1.0.0-official`
- Renderer: not implemented in this phase

## OpenXML structure

- Valid DOCX ZIP package with 18 entries.
- No bookmarks, content controls, simple fields, complex field characters, or mustache tokens.
- Nine tables provide the strongest deterministic anchors.
- Free-entry positions use underscore runs; two unresolved authority texts use `[TE BESLISSEN]`.

## Stable anchors

| Table | Stable first-row or section anchor | Future payload area |
| --- | --- | --- |
| 1 | `Offertenummer` | quotation identity, dates, validity |
| 2 | `KLANTGEGEVENS` | customer identity and address |
| 3 | `Pakket` / `Eenmalige implementatie` | selected package and prices |
| 4 | `Documentflows` / `Documenttypes/templates` | package capacity limits |
| 5 | `Onderdeel` / `Omschrijving voor deze offerte` | agreed SDF scope |
| 6 | `Categorie` / `Prijs (excl. btw)` | Budget Guard and extra-work prices |
| 7 | `40%` / `40%` / `20%` | implementation milestones |
| 8 | `Inbegrepen normale support / maand` | recurring support authority |
| 9 | `Voor akkoord` | seller and customer acceptance |

The document also exposes `Kop2` paragraph anchors for Klantgegevens, Projectomschrijving, Gekozen pakket, Capaciteitsgrenzen per pakket, Overeengekomen scope, Meerwerkprijzen, Implementatiebetaling, Recurrente dienstverlening, Contractduur, Acceptatie, Maatwerkspecificaties, Uitvoeringstermijn, Geldigheid, Toepasselijke voorwaarden, and Voor akkoord.

## Mapping constraint

A future renderer must map by verified table and heading structure, fail closed on structural drift, and preserve the immutable template hash as input evidence. This report does not define or implement rendering behavior.