# Final Production Checkpoint 2026-08-14

## Document authority

Dit document is vanaf 14 augustus 2026 de primaire hervattingsbron voor Lorenzo Web Solutions / `lorenzo-web-studio`.

- Repository: `lorenzobombello-max/lorenzo-web-studio`
- Production branch: `origin/main`
- Finale productiecommit: `258a2c98064b51112bd9b02bd1d300e2fbf602b5`
- Commit: `feat(operator): add authoritative financial projection`
- Website status: **KLAAR / PRODUCTION READY voor de huidige goedgekeurde scope**
- Live URL: `https://lorenzowebsolutions.be/`
- Statusdatum: 2026-08-23

De code, migrations en runtimeconfiguratie blijven de technische bron van waarheid. Dit checkpoint vervangt geen historische evidence; het bepaalt welke Git- en projectstatus bij hervatting actueel is. Neem nooit secrets, raw tokens, private capabilities, service-role credentials of private environmentwaarden op in repositorydocumentatie.

## CURRENT continuity - Legacy test cleanup authority release - 24-08-2026

Deze sectie is de **CURRENT / AUTHORITATIVE resume** voor de volgende sessie. Zij actualiseert de productie- en vervolgstatus; oudere checkpoints en de onderstaande eerdere fasesecties blijven historisch bewijs en mogen niet als actuelere Git- of open-statusauthority worden gebruikt.

### Production release

| Eigenschap | Actuele authority |
|---|---|
| Fase | Legacy test cleanup authority, met behoud van alle eerdere Operator- en commercial foundations |
| Status | **PRODUCTION RELEASE COMPLETE** |
| Production SHA | `9413e5867b67a79e8dbdd3aff202d9be5c22103f` |
| Previous main | `258a2c98064b51112bd9b02bd1d300e2fbf602b5` |
| Commit | `feat(operator): add legacy test cleanup authority` |
| Migration | `20260823190000_add_legacy_test_cleanup_authority.sql` |
| Migrationstatus | **APPLIED**; linked ledger parity; pending migrations `0`; drift `0` |
| Edge Function | geen deployment nodig of uitgevoerd; bestaande `commercial-operator-command` blijft behouden |
| Edge hash | `4a9b6ad49474a214acf2b834eb933088a78bc4e02343c36a5da0fd8f5bb3a562` |
| GitHub Pages | **SUCCESS**; run `32696991750`; approved SHA `9413e5867b67a79e8dbdd3aff202d9be5c22103f` |

Productionbewijs na de gecontroleerde release:

- legacy test cleanup authority bevat exact `11/11` migration-owned UUID's;
- frozen identities en identity snapshots zijn `11/11` intact;
- `record_classification = production` is voor `11/11` dossiers behouden;
- de bestaande `internal_e2e` authority is behouden en ontvangt geen legacy authority;
- beide legacy-authoritytabellen hebben RLS enabled en `FORCE RLS`;
- runtime table- en function-ACL violations voor `anon`, `authenticated` en `service_role` zijn `0`;
- authority is immutable en consumption evidence is append-only guarded;
- de consumption table is aanwezig en de production consumption count is `0`;
- quotation-, acceptance-, commercial-, payment-, document/artifact- en SDF-blockers zijn voor de elf dossiers allemaal `0`;
- deze release introduceert geen delete- of cleanupcommand, cleanup-RPC, browserpermission of businessdatarewrite;
- `support_reference` is een actieve stored generated authority;
- format- en unique constraints zijn actief;
- production supportreference-collisioncount is `0`;
- `commercial_project_sites` heeft RLS enabled en `FORCE RLS`;
- directe table-writegrants voor `anon`, `authenticated` en `service_role` zijn `0`;
- de guarded bind/rotate-RPC is aanwezig;
- `financial_summary` production contract is **PASS**;
- authorization, fixed `search_path` en bestaande execute-ACL zijn **PASS**;
- expected gebruikt uitsluitend projectgebonden authoritative payment expectations;
- invoiced en outstanding blijven fail-closed unavailable zolang volledige productionauthority ontbreekt;
- received telt uitsluitend exact gematchte en bevestigde paymentauthority, maximaal eenmaal per milestone expectation;
- raw, unreconciled, PARTIAL en MATCHED-zonder-confirmation evidence telt niet als ontvangen;
- sensitive payment-evidencemetadata wordt niet rechtstreeks geprojecteerd;
- 40/40/rest paymentauthority is **PRESERVED**;
- production bevat `0` commercial projects; runtime business-record verification is **NOT APPLICABLE / NO PRODUCTION PROJECT AVAILABLE**;
- release findings: BLOCKER `0`, HIGH `0`, MEDIUM `0`, LOW `1`; de LOW is uitsluitend de niet-blokkerende GitHub Actions Node.js 20-deprecationwaarschuwing;
- er is geen handmatige businessdatawijziging, cleanup of fictieve customer/project/sitecreatie uitgevoerd.

### Referentiecontract - DONE / PRESERVE

| Identiteit | Productionwaarde |
|---|---|
| Interne aanvraag-/dossierreferentie | `LWS-AAN-2026-0001` |
| Publieke klant-/supportreferentie | `#F98B2F08` |
| Technische identiteit | UUID van het quote request/dossier |

De interne en publieke referentie zijn afzonderlijke identiteiten en worden niet semantisch samengevoegd. Beide zijn production lookup-capable en resolveren aantoonbaar exact hetzelfde quote request/dossier. De UUID blijft de technische identiteit en fallback.

### Project/site foundation - DONE / PRESERVE

Gerealiseerd en niet opnieuw ontwerpen:

- canonical application -> customer -> commercial project foundation;
- projectgebonden site authority met initial bind;
- append-only controlled site rotation en immutable site history;
- expected revision/concurrency, project locking en idempotency;
- owner/admin-only write-authority en cross-project isolation;
- een customer kan meerdere onafhankelijk gebonden projecten/sites hebben;
- intakevelden zoals `existing_website_url` en `domain_name` blijven evidence en worden niet automatisch canonical projectsite;
- project/site-readprojectie en veilige HTTPS/exact-origin websitelink met `_blank` en `noopener noreferrer`.

Production bevat momenteel `0` commercial projects. Daarom zijn `project = null` en `project_site = null` in het bestaande productiondossier correct en geen bug. Er is bewust geen fictief project of site aangemaakt.

### Test- en reviewbewijs

- support/site pgTAP: `47/47` PASS;
- application handoff en financial projection: `118/118` PASS;
- Operator: `58/58` PASS;
- Edge handler: `15/15` PASS;
- volledige lokale migration reset: PASS;
- Edge bundling: PASS;
- independent review: BLOCKER `0`, HIGH `0`, MEDIUM `0`, LOW `0`.

### Reeds afgewerkt - DONE / PRESERVE

- Operator search en **Open in Operator**;
- 7-day intake lifecycle en uitnodigingsmail met exact zeven dagen;
- interne `application_reference` en afzonderlijke publieke `#supportreference`;
- supportreference foundation;
- application/customer/project binding;
- customer/application/project/site foundation;
- project/site foundation;
- M1 invoice policy-neutral foundation;
- bestaande commerciele en documentauthority;
- 40/40/rest paymentauthority;
- authoritative financial projection met expected, fail-closed invoiced, confirmed received en fail-closed outstanding;
- confirmed-payment authority als voorwaarde voor ontvangen inkomsten;
- project-isolated en multi-project-isolated financial projection;
- bestaande customer preview authority waar reeds checkpointed;
- bestaande Drive documentauthority.
- immutable legacy test cleanup allowlist voor exact elf historische test-/ontwikkelingsdossiers;
- fail-closed identity- en blockerassertions, zonder delete- of cleanupauthority;
- append-only consumption evidence foundation, production count `0`.

Deze onderdelen zijn geen opdracht voor heranalyse of herontwerp in een volgende sessie.

### Capabilitystatus

Gebruik voor iedere vervolgscope vier afzonderlijke statussen. **AUTHORITY EXISTS** of **BACKEND EXISTS** betekent nooit automatisch dat **OPERATOR UI EXISTS** of **PRODUCTION READY** waar is.

| Workflow | Authority | Backend | Operator UI | Production ready |
|---|---|---|---|---|
| Offerte -> verzenden -> acceptatie | EXISTS | EXISTS | gedeeltelijk/bestaand | alleen volgens bestaande checkpoints |
| M1 -> betaling -> project release/start | EXISTS | foundation/bestaand | niet volledig end-to-end | NEE als volledige Operatorflow |
| Preview -> M2 -> betaling -> final approval | EXISTS | foundation/bestaand | niet volledig end-to-end | NEE als volledige customer-facing flow |
| Restfactuur -> volledige betaling -> transfer -> delivery -> receipt -> archive | EXISTS | foundation/bestaand | niet volledig end-to-end | NEE als volledige Operatorflow |

De bestaande workflowauthority blijft behouden in deze volgorde: offerte -> verzenden -> acceptatie -> M1 -> betaling -> project release -> project start -> preview -> M2 -> betaling -> final approval -> restfactuur -> volledige betaling -> transfer -> delivery -> receipt -> archive. Specificatie of backendfoundation mag niet als volledige production-UI worden gepresenteerd.

### OPEN / NEXT

#### A. Dossierbeheer / Operator structure

**OPEN / NEXT.** Dit checkpoint start geen implementatie en autoriseert geen deletefunctie.

- testdossiers moeten later gecontroleerd verwijderd kunnen worden, maar verwijderen mag niet onmiddellijk permanent zijn;
- voor verwijderen is een tweede bevestiging/pop-up vereist met exact: **"Ben je zeker dat je dit dossier wilt verwijderen?"**;
- verwijderde testdossiers gaan eerst naar een prullenmand-/trash-status en moeten vanuit de prullenmand herstelbaar blijven;
- de bewaartermijn van trash is een afzonderlijke OPEN authoritybeslissing; `30` of `60` dagen zijn uitsluitend voorbeelden en worden hier niet gekozen;
- officiele, production-, commerciele of boekhoudkundige records krijgen niet dezelfde cleanup-authority zonder afzonderlijke wettelijke/business authority;
- ontwerp geen hard delete van officiele records zonder expliciete authority;
- offerte-, factuur-, contract-, payment- en overige wettelijke bewaarplichten moeten worden gerespecteerd;
- inventariseer voor implementatie de bestaande data-authority, relaties, auditvereisten en het onderscheid TEST versus echte production-/commercial records;
- de huidige lijst mag niet onbeperkt blijven groeien: structureer dossiers per jaar en daarbinnen als Q1 / Q2 / Q3 / Q4;
- het Operator-overzicht vereist een statusoverzicht en schaalbaar zoeken/filteren; status moet een bruikbare index/filter zijn;
- geannuleerde dossiers moeten extern duidelijk herkenbaar zijn met status **Geannuleerd** en een rode statusweergave naast/bij bestaande statussen zoals **Ingediend**;
- SDF moet in de latere dossierflow worden meegenomen;
- bestaande offertes, facturen, contracten/wijzigingen en documentenflow blijven gekoppeld aan dezelfde dossierauthority;
- de bestaande 40/40/rest paymentauthority blijft onaangeraakt.

##### Actieve Operatorwerkruimte

De toekomstige primaire Operatorweergave is een dagelijkse werkruimte en geen onbeperkte lijst waarin alle dossiers jarenlang permanent zichtbaar blijven. Zij bevat in hoofdzaak operationeel relevante dossiers, waaronder nieuwe aanvragen, ingediende dossiers, dossiers in behandeling, dossiers die wachten op actie, actieve klanten/projecten en andere dossiers waarvoor nog werk nodig is.

##### Archief en heractiveren

Afgewerkte of niet langer operationeel actieve dossiers moeten uit de dagelijkse actieve lijst kunnen verdwijnen zonder het onderliggende dossier of officiele documenten te verwijderen. **Archiveren is niet hetzelfde als verwijderen.** Een gearchiveerd dossier en zijn relevante gegevens, historiek en documenten blijven bewaard volgens de nog vast te stellen wettelijke/business-retentieauthority.

Een gearchiveerd dossier moet later opnieuw vindbaar en rechtstreeks oproepbaar zijn. Wanneer een klant na een of meerdere jaren opnieuw contact opneemt, moet de Operator het bestaande dossier kunnen vinden en openen, de historiek en documenten kunnen raadplegen en, waar functioneel toegestaan, het dossier opnieuw actief kunnen markeren. Heractivering laat het bestaande dossier terugkeren in de actieve Operatorwerkruimte en maakt niet uitsluitend wegens hernieuwde activiteit een duplicaat klant- of dossierrecord.

##### Globale search en schaalbare navigatie

De toekomstige search doorzoekt conceptueel niet alleen de actieve werkruimte, maar ook gearchiveerde dossiers en, waar toegestaan, verwijderde testdossiers in trash. Ieder zoekresultaat toont duidelijk zijn zone/status, bijvoorbeeld **Actief**, **Gearchiveerd**, **Geannuleerd** of **Prullenmand**. Een gearchiveerd resultaat moet rechtstreeks oproepbaar zijn zonder eerst door oude jaar- of kwartaalpagina's te navigeren.

Jaar en Q1 / Q2 / Q3 / Q4 zijn filter- en navigatiestructuur, geen eeuwige hoofdlist met tientallen permanent zichtbare jaarknoppen. Oudere jaren blijven via archief, filter en search bereikbaar zonder de dagelijkse interface te belasten. Het ontwerp moet ook bij duizenden dossiers schaalbaar blijven:

- laad nooit duizenden dossiers in een keer naar de browser;
- haal alleen de benodigde subset op via server-side filtering/pagination of een gelijkwaardig schaalbaar mechanisme;
- scheid actieve en gearchiveerde views logisch;
- ontwerp search eveneens server-side en schaalbaar;
- kies in deze fase nog geen concrete pagination-, search- of UX-techniek.

##### Archiveren, trash en Geannuleerd blijven afzonderlijk

- **Archiveren** is normaal lifecyclebeheer: het dossier blijft geldig en bewaard, documenten blijven bestaan, het dossier blijft oproepbaar en kan potentieel worden geheractiveerd.
- **Trash** is uitsluitend voor records waarvoor toekomstige authority gecontroleerde verwijdering toestaat, in het bijzonder testdata. Trash vereist de beveiligde bevestiging, blijft tijdelijk herstelbaar en heeft nog geen gekozen retentieperiode (`30` of `60` dagen blijft OPEN). Hard delete na retentie mag alleen als toekomstige authority dit expliciet toestaat.
- Voor officiele/business records wordt geen hard-delete-authority aangenomen.
- **Geannuleerd** blijft een duidelijke rode status in overzicht en index, niet automatisch een verwijdering. Een geannuleerd dossier kan afhankelijk van de toekomstige lifecycle later worden gearchiveerd.

Archiveren of heractiveren mag offertes, facturen, SDF, documentenflow, klant-/projecthistoriek of paymentauthority niet loskoppelen of wijzigen. De bestaande 40/40/rest paymentauthority blijft onaangeraakt.

##### Expliciet OPEN authoritybeslissingen

Deze documentatiefase maakt de volgende keuzes niet definitief:

- exacte archiefstatus en database-representatie;
- exacte lifecycle-state-machine;
- wanneer automatisch of handmatig archiveren is toegestaan;
- exacte permissies voor heractiveren;
- trash-retentie van `30` versus `60` dagen;
- wettelijke/business-retentie per documenttype;
- concrete pagination- en searchtechniek;
- UX-detail van de actieve werkruimte en archiefweergave.

#### B. Echte project/site businessbinding

De foundation bestaat, maar er is nog geen werkelijk production commercial project/site geregistreerd. Initial bind of rotation mag alleen plaatsvinden wanneer een echt klantproject dit vereist en afzonderlijk is geautoriseerd.

#### C. Preview + feedback

Hergebruik de bestaande authority/foundation. De customer-facing end-to-end Operatorflow moet nog verder worden aangesloten en is niet als volledig production-ready bewezen.

#### D. Projectgeisoleerde uploadflow

**OPEN.** Een gedeelde klantuploadbak is verboden. Iedere toekomstige uploadauthority moet minimaal zijn gebonden als:

`customer -> application/dossier -> project -> upload authority/batch -> file metadata`

Klant A mag nooit bestanden van klant B zien of uploaden. Een customer met meerdere projecten blijft per project geisoleerd. De Operator kan later een afzonderlijke tijdelijke actie **Uploadlink versturen** krijgen. Hergebruik eerst bestaande intake-/artifactcomponenten waar dat aantoonbaar veilig is.

#### E. Documentenflow -> live Operator

**OPEN.** De bestaande commerciele A->Y authority wordt niet opnieuw ontworpen. Volgende fases realiseren uitsluitend ontbrekende live Operator-koppelingen. Documentenflow moet nog zichtbaar en bedienbaar worden in live Operator.

#### F. Bestaande documenten en productkoppelingen

**OPEN.** Inventariseer en hergebruik eerst de bestaande authority; maak deze documenten niet opnieuw.

- SDF-koppeling aan de live Operatorworkflow;
- bestaande offertes en facturen;
- bestaande wijzigings- en contractdocumenten;
- koppeling van deze authority aan klant, project en Operatorworkflow.

### Vaste projectdiscipline

Na iedere bewezen belangrijke fase geldt verplicht:

review -> gecontroleerde commit/push -> production release indien van toepassing -> verificatie -> continuity/checkpoint actualiseren -> pas daarna de volgende fase.

Leg daarbij de gerealiseerde scope, tests, release-SHA, migrations, deployments, openstaande punten en exacte volgende kandidaatfase vast.

Iedere volgende sessie leest eerst deze CURRENT-sectie. Een brede heranalyse van reeds bewezen werk is niet toegestaan zonder nieuwe concrete evidence.

### Exacte volgende kandidaatfase

De logisch eerstvolgende kandidaat is **DOSSIER MANAGEMENT / OPERATOR STRUCTURE - authority inventory**. Inventariseer eerst data-authority, relaties, auditvereisten, wettelijke bewaarplichten, trash/restore en het onderscheid TEST versus echte production/commerciele records. De trash-retentie blijft een afzonderlijke OPEN authoritybeslissing. Jaar-/kwartaalstructuur, statusindex, zoeken/filteren en gecontroleerde niet-permanente verwijdering van testdossiers blijven requirements; dit checkpoint ontwerpt of bouwt geen deletefunctie, trashflow, Operator UI of andere implementatie.

Dit checkpoint kiest alleen de kandidaat en start geen implementatie.

## Intake inspect transaction mode continuity - 23-08-2026

**Status: ROOT CAUSE PROVEN / REMEDIATED / REVIEWED / PRODUCTION APPLIED / PRODUCTION VERIFIED.**

- Release-HEAD en fixcommit: `3a2a96db2737024a6eb7fefcd2b82c17ce56f019` (`fix(intake): correct inspect transaction mode`).
- Root cause: de inspect-RPC transaction mode was incompatibel met de lockingsemantiek.
- Remediation: de betrokken inspectwrappers v2-v5 zijn gecorrigeerd naar `VOLATILE`, met behoud van `FOR SHARE` en de bestaande security- en authoritycontracten.
- Productionverificatie: Lorenzo bevestigde handmatig dat de beveiligde intake opnieuw correct opent en de workspace wordt geladen.
- De production migration is toegepast en de production-RPC is zonder SQLSTATE `25006` of `INTAKE_INSPECT_FAILED` geverifieerd.
- Het niet-tracked bestand `LWS_MASTER_CONTINUITY_CONTROL_2026-08-18.md` is op 23-08-2026 niet aangetroffen in de reeds bekende projectauthoritylocaties en is niet gereconstrueerd.
- Deze incidentclosure start geen nieuwe technische fase. De hieronder vastgelegde eerstvolgende atomic Phase-B stap blijft `SDF MILESTONE 1 INVOICE AUTHORITY RECOVERY`.

## Operator Phase B continuity - 21-08-2026

Deze sectie actualiseert uitsluitend de hervattingsstatus van Operator Phase B. De productionhistoriek en overige evidence in dit document blijven ongewijzigd. Bij hervatting van Operatorwerk geldt deze sectie als CURRENT technische resume. Zij vervangt niet de bredere bedrijfscontinuiteitsbron `LWS_MASTER_CONTINUITY_CONTROL_2026-08-18.md`.

### Actuele technische basis

| Eigenschap | Waarde |
|---|---|
| Datum | 21-08-2026 |
| Worktree | `C:\Users\info\Project-Worktrees\lorenzo-web-studio-intake-output-02-20260819` |
| Branch | `feature/intake-output-implementation-02-20260819` |
| Start-HEAD van deze atomic implementation | `a8b215e0017a0f9a0c1173689cf2d747644f9045` |
| Laatste Operator implementation commit | `3d2a844d2d40584c2ab7302d7fadb769f2fafdd9` |
| Ahead/behind tegenover `origin/main` na implementation commit | `15/0` |
| Preservation gate | **PASS** |

Commit `3d2a844d2d40584c2ab7302d7fadb769f2fafdd9` (`feat(sdf): bind accepted terms to milestone one`) is de actuele lokale technische basis voor Operator Phase B. Operator Phase A.1, Customer Core, SDF package identity, SDF pricing, SDF project identity en SDF quotation identity/document/acceptance blijven **COMPLETE**.

### Phase-B matrix

| Phase-B onderdeel | WEBSITE | SDF |
|---|---|---|
| Application | DONE | DONE |
| Package identity | N/A | DONE |
| Customer | DONE | DONE |
| Project | DONE | DONE |
| Pricing | PARTIAL | DONE |
| Quotation Identity | DONE | DONE |
| Quotation Status | DONE | NOT USED / NOT REQUIRED |
| Quotation Document Evidence | N/A | DONE |
| Quotation Acceptance Evidence | N/A | DONE |
| Accepted Commercial Terms | DONE | DONE |
| Milestone 1 Expected Obligation | DONE | DONE |
| Document Status | PARTIAL | NOT USED / NOT REQUIRED |
| Workflow Status | DONE | MISSING |
| Audit Summary | DONE | MISSING |

### Product- en authoritygrenzen

1. De Websiteflow blijft een protected regression boundary.
2. Slimme Documentenflow / SDF is een bestaande afzonderlijke productfamilie. De commerciele SDF-authority bestaat en is niet open voor herbeslissing.
3. Ontbrekende SDF pricing-, recurring- en projectfunctionaliteit is een **TECHNISCHE REPRESENTATIE/PERSISTENCE GAP**, geen ontbrekende businessbeslissing.
4. SDF START, GROEI en MAATWERK en hun bestaande commerciele pricing- en recurring-authority mogen niet opnieuw als onbeslist worden behandeld.
5. De canonieke technische SDF package vocabulary is gesloten op `start | groei | maatwerk`. Zij representeert uitsluitend pakketidentiteit en voegt geen prijzen, snapshots of recurring obligations toe.
6. Nieuwe SDF-submits vereisen server-side een geldige package identity. Historische SDF-records mogen `NULL` blijven en renderen als `Niet geregistreerd`.
7. Website-aanvragen moeten `sdf_package = NULL` houden. De historische Website-idempotency fingerprint blijft ongewijzigd.
8. De reeds persistente Customer Core-data wordt voor Website en SDF door de product-aware Operator application-RPC geprojecteerd en read-only in het Customer-dossier gerenderd. Ontbrekende optionele waarden blijven neutraal.
9. `request_kind` blijft de productauthority met uitsluitend `website | slimme_documentenflow` en blijft immutable.
10. Een Website-naar-SDF fallback, coalesce of pricingovername is niet toegestaan. Onbekende product- of packagecontext moet fail-closed blijven.
11. Golden Master / Customer Core C1-C4, Website pricing, Budget Guard en Website quotation/acceptance blijven **COMPLETE / VERIFIED / FROZEN** en worden niet heropend.
12. SDF-maandbedragen zijn uitsluitend read-only commerciele pakketprijzen. Zij activeren geen recurring service, betalingsverplichting, snapshot of financiele lifecycle.
13. SDF-projectauthority is identity-only: project-ID, een-op-een aanvraaglink en creatietijd. Projectstatus en operationele status bestaan nog niet als persistente SDF-authority en blijven `Niet beschikbaar`.
14. Application en Project blijven afzonderlijke entiteiten. Een SDF-aanvraag zonder expliciete `sdf_projects`-rij blijft `Nog geen project`; er bestaat geen automatische projectcreatie.
15. SDF-quotationauthority bestaat uit afzonderlijke immutable identity-, document- en actieve acceptance-evidence. Een algemene mutable quotationstatus is **NOT USED / NOT REQUIRED**.
16. Application en Quotation blijven afzonderlijke entiteiten. Een SDF-aanvraag zonder expliciete `sdf_quotations`-rij blijft `Nog geen offerte`; document- of acceptance-evidence creëert geen quotation, project, mijlpaal, betalingsverplichting, activatie of recurring service.
17. Document- en acceptance-evidence zijn SDF-only, een-op-een aan quotation identity gekoppeld, append-once, force-RLS private en zonder publieke/browser-write-RPC.
18. Prijzen worden niet in quotation evidence gedupliceerd. Website quotation/acceptance en bestaande SDF pricing/projectauthority blijven geïsoleerd en ongewijzigd.
19. Geaccepteerde SDF-commercial terms zijn een afzonderlijke immutable snapshot van package, exact implementatiebedrag, `EUR`, exclusief-btw-basis en pricing-authority version 1; de mutable aanvraagrij is niet de financiele auditbron.
20. START en GROEI moeten exact overeenkomen met pricing authority v1. MAATWERK vereist altijd een expliciet exact geaccepteerd bedrag van minimaal de `starting_at`-authority en gebruikt dat minimum nooit als fallback.
21. Per accepted quotation bestaat exact een immutable `M1`-obligation van `4000` basispunten in state `EXPECTED`, zonder invoice-, payment-, reconciliation-, project-, activation- of recurring-semantiek.
22. `EXPECTED` / factureerbaar is niet gefactureerd; gefactureerd is niet ontvangen. Deze grenzen mogen in volgende stappen niet worden samengevoegd.

### Voltooide atomic implementations

De SDF Accepted Commercial Terms + Milestone-1 Obligation Foundation is voltooid in commit `3d2a844d2d40584c2ab7302d7fadb769f2fafdd9`:

- preservation start-HEAD `a8b215e0017a0f9a0c1173689cf2d747644f9045`; implementationcommit `3d2a844d2d40584c2ab7302d7fadb769f2fafdd9`;
- additive private tabellen `sdf_accepted_commercial_terms` en `sdf_milestone_one_obligations` bewaren respectievelijk de immutable accepted snapshot en exact een immutable `EXPECTED` M1 van 40%;
- owner/admin-only RPC `create_sdf_milestone_one_foundation_v1(uuid,bigint,uuid)` vereist actieve acceptance-evidence, valideert START/GROEI tegen pricing authority v1 en vereist voor MAATWERK een expliciet exact bedrag zonder fallback;
- de RPC schrijft beide records transactioneel, serialiseert op idempotency key en quotation, retourneert dezelfde authority bij een identieke retry en faalt gesloten bij idempotency- of accepted-termsconflict;
- integer minor-unitcoherentie wordt afgedwongen; package mutation is na de financiele binding geblokkeerd;
- beide tabellen zijn force-RLS private, direct runtime-table-write is ingetrokken en uitsluitend `authenticated` kan de guarded RPC aanroepen;
- Website financial tables bleven ongewijzigd; de foundation maakt geen invoice, payment evidence, reconciliation, project, activation of recurring service;
- TDD-evidence: eerste RED op de vijf ontbrekende contractobjecten, daarna focused pgTAP `39/39`, gerichte SDF/Website-regressies `170/170`, volledige pgTAP-suite `1172/1172` over `40` bestanden, volledige lokale migration rebuild, diagnostics zonder fouten en staged `git diff --check`.

Exacte implementation-files:

- `supabase/migrations/20260821180000_bind_sdf_accepted_terms_to_milestone_one.sql`
- `supabase/tests/sdf_milestone_one_foundation.sql`

De Customer Core-uitbreiding is voltooid in commit `760f80663674e0938138ceff6d1e2f2da06e5fff`:

- additive migration `20260821120000_expose_operator_customer_core.sql` voor de bestaande beveiligde detail-RPC;
- gedeelde, read-only Customer Core-weergave voor Website en SDF;
- neutrale afhandeling van ontbrekende optionele waarden;
- gerichte productisolatie-, stale-data- en XSS-contracttests.

De SDF package identity foundation is voltooid in commit `26d2f132ae2d24435cc75573177bf00ac13359ca`:

- bestaande CTA-query `package-interest` vult een verplicht SDF-only pakketselect en de echte submitpayload;
- Edge-validatie en de storage-RPC accepteren uitsluitend `start | groei | maatwerk`; missing/unknown faalt voor nieuwe SDF-submits;
- additive migration `20260821130000_persist_sdf_package_identity.sql` voegt nullable `quote_requests.sdf_package` toe voor veilige legacy-readability en dwingt Website-isolatie af;
- `sdf_package` is voor SDF onderdeel van de idempotency fingerprint; Website behoudt zijn bestaande fingerprintvorm;
- de beveiligde Operator detail-RPC projecteert package identity; de SDF-only Application-rij toont `START`, `GROEI`, `MAATWERK` of legacy `Niet geregistreerd` via `textContent`;
- lokaal gevalideerd met migration rebuild, Node `48/48`, Deno validation `36/36`, Edge `deno check`, pgTAP `103/103`, diagnostics zonder fouten, `git diff --check` en responsive DOM-controles op `1440px` en `375px`.

Exacte implementation-files:

- `pages/contact.html`
- `assets/js/pages.js`
- `supabase/functions/_shared/types.ts`
- `supabase/functions/_shared/validation.ts`
- `supabase/functions/_shared/validation.test.ts`
- `supabase/functions/submit-quote-request/index.ts`
- `supabase/migrations/20260821130000_persist_sdf_package_identity.sql`
- `supabase/tests/request_kind_contract.sql`
- `supabase/tests/operator_application_handoff.sql`
- `operator/dashboard/index.html`
- `assets/js/operator-dashboard.js`
- `scripts/documentenflow-commercial-entry.test.mjs`
- `scripts/operator-dashboard.test.mjs`

De SDF Quotation Document + Acceptance Evidence Foundation is voltooid in commit `a6adef6668ffc269f1f404ab280b11d0c8a2c362`:

- **SDF Quotation Document Evidence = DONE** en **SDF Quotation Acceptance Evidence = DONE**;
- de business authority is **CLOSED** en de evidence foundation is **DONE**; een algemene Quotation Status enum is **NOT USED / NOT REQUIRED**;
- private tabel `sdf_quotation_documents` bevat uitsluitend quotationlink, offertedatum, werkelijke geldigheid, voorbereidingstijd, stabiele documentreferentie en lowercase SHA-256;
- private tabel `sdf_quotation_acceptances` bevat uitsluitend quotationlink, acceptatietijd, referentie van het geaccepteerde document en lowercase SHA-256;
- acceptance vereist bestaande document-evidence; beide tabellen zijn SDF-only, een-op-een, immutable, force-RLS en zonder runtimeprivileges of write-RPC;
- de guarded Operator-detailprojectie toont alleen datums en presence flags; volledige hashes en interne documentreferenties verlaten de private authority niet;
- er is geen statusenum, prijsduplicatie of automatische quotation-, project-, mijlpaal-, payment-, activation- of recurring-mutatie toegevoegd;
- Website quotation/acceptance en bestaande SDF identity-, pricing- en projectauthority bleven geïsoleerd en ongewijzigd;
- lokaal gevalideerd met volledige migration rebuild, pgTAP `234/234` (`25` evidence, `13` identity, `31` request-kind, `92` Operator handoff, `9` SDF pricing, `11` SDF project, `53` Website acceptance), Operator Node `56/56`, diagnostics zonder fouten en `git diff --check`.

Exacte implementation-files:

- `supabase/migrations/20260821170000_add_sdf_quotation_acceptance_evidence.sql`
- `supabase/tests/sdf_quotation_acceptance_evidence.sql`
- `supabase/tests/operator_application_handoff.sql`
- `operator/dashboard/index.html`
- `assets/js/operator-dashboard.js`
- `scripts/operator-dashboard.test.mjs`

De SDF Project read-only foundation is voltooid in commit `0cf9162f2062d133d3e6db6f806ec4d4f2d136aa`:

- recovery bevestigde dat `commercial_projects` uitsluitend via Website quotation issuance/acceptance ontstaat en Website money-, 40/40/20-, workflow- en lifecycleauthority draagt;
- additive private tabel `sdf_projects` bevat uitsluitend `project_id`, unieke `quote_request_id` en `created_at`;
- inserts accepteren uitsluitend een echte `slimme_documentenflow`-aanvraag; projectidentity en linkage zijn immutable;
- forced RLS en ingetrokken runtimeprivileges houden de tabel achter de bestaande owner/admin Operator detail-RPC;
- geen create-, promote- of mutation-RPC toegevoegd: alleen expliciet reeds persistente SDF-projectrijen worden gelezen;
- de guarded projectie bevat project-ID, product, gekoppelde aanvraag, klant, package en creatietijd; niet-bestaande project- en operationele status blijven `null`/`Niet beschikbaar`;
- SDF zonder project toont `Nog geen project`; legacy en mismatched linkage falen gesloten en stale UI-waarden worden gewist via `textContent`;
- Website `commercial_projects`, promotion, project-view, pricing, quotation, milestones en workflow bleven ongewijzigd;
- SDF pricingbedragen en commerciele recurring package price bleven ongewijzigd; geen recurring service, obligation, payment of lifecycle toegevoegd;
- lokaal gevalideerd met volledige migration rebuild, pgTAP-regressies `133/133`, Operator Node-regressies `50/50`, diagnostics zonder fouten, `git diff --check` en layoutmetingen zonder overflow op `1440x900` en `375x812`.

Exacte implementation-files:

- `supabase/migrations/20260821150000_expose_sdf_project_foundation.sql`
- `supabase/tests/sdf_project_foundation.sql`
- `supabase/tests/operator_application_handoff.sql`
- `operator/dashboard/index.html`
- `assets/js/operator-dashboard.js`
- `scripts/operator-dashboard.test.mjs`

De SDF Quotation Identity Foundation is voltooid in commit `27abff0b4074c46e8313108cce6c1a8d8549baaa`:

- recovery bevestigde dat de Website quotationauthority productvreemde intake-, pricing-, approval-, issuance-, numbering- en acceptance-semantiek draagt en niet voor SDF mag worden hergebruikt;
- additive private tabel `sdf_quotations` bevat uitsluitend `quotation_id`, unieke `quote_request_id` en `created_at`;
- inserts accepteren uitsluitend een echte `slimme_documentenflow`-aanvraag; quotationidentity en linkage zijn immutable;
- forced RLS en ingetrokken runtimeprivileges houden de tabel achter de bestaande owner/admin Operator detail-RPC;
- geen create-, status-, issuance-, send-, document- of acceptance-RPC toegevoegd en geen automatische quotationcreatie ingevoerd;
- de afzonderlijke guarded `sdf_quotation`-projectie bevat alleen offerte-ID, aanvraaglink, application reference en creatietijd; status blijft afwezig en rendert als `Niet beschikbaar`;
- SDF zonder quotation toont `Nog geen offerte`; legacy, cross-product en mismatched linkage falen gesloten en stale UI-waarden worden gewist via `textContent`;
- Website `quotation` en SDF pricing/projectprojecties bleven ongewijzigd;
- lokaal gevalideerd met volledige migration rebuild, gerichte pgTAP-regressies `150/150`, Operator Node-regressies `53/53`, diagnostics zonder fouten en `git diff --check`.

Exacte implementation-files:

- `supabase/migrations/20260821160000_add_sdf_quotation_identity_foundation.sql`
- `supabase/tests/sdf_quotation_identity_foundation.sql`
- `supabase/tests/operator_application_handoff.sql`
- `operator/dashboard/index.html`
- `assets/js/operator-dashboard.js`
- `scripts/operator-dashboard.test.mjs`

De SDF pricing/recurring read-only foundation is voltooid in commit `00f3f582be74d4f52a56d884da63d52c090783f9`:

- private immutable SQL-authority voor `start | groei | maatwerk`, integer minor units en expliciete `fixed | starting_at` semantics;
- exacte implementatie/maandbedragen: START `285000/17500`, GROEI `570000/29900`, MAATWERK `750000/44900`, exclusief btw;
- afzonderlijke guarded `sdf_pricing` projectie; Website `pricing` blijft ongewijzigd en Website ontvangt altijd `sdf_pricing = null`;
- legacy SDF zonder package toont `Niet geregistreerd` en `Niet beschikbaar`, zonder gefabriceerde bedragen;
- SDF-only read-only dossier met expliciete melding dat het maandbedrag geen actieve terugkerende dienst of financiele verplichting is;
- fail-closed presentatie bij product-, package-, authority- of semantic mismatch en stale clearing via `textContent`;
- geen snapshotkolom, `recurring_services`-write, verplichting, betaling, project, offerte of andere lifecyclemutatie toegevoegd;
- lokaal gevalideerd met volledige migration rebuild, gerichte pgTAP-regressies `117/117`, Operator Node-regressies `46/46`, diagnostics zonder fouten en `git diff --check`.

Exacte implementation-files:

- `supabase/migrations/20260821140000_expose_sdf_pricing_authority.sql`
- `supabase/tests/sdf_pricing_authority.sql`
- `supabase/tests/operator_application_handoff.sql`
- `operator/dashboard/index.html`
- `assets/js/operator-dashboard.js`
- `scripts/operator-dashboard.test.mjs`

### Resterende Phase-B scope

De resterende matrix is hierboven leidend. Voor SDF zijn quotation business authority, immutable document/acceptance evidence, accepted commercial terms en de verwachte M1-obligation gesloten. Invoice-authority, payment receipt/reconciliation en project-start eligibility zijn nog niet technisch gerepresenteerd en blijven afzonderlijke toekomstige lagen. Workflow Status en Audit Summary blijven technisch `MISSING`; voor Website blijven Pricing en Document Status `PARTIAL`.

De **exacte volgende atomic Phase-B stap** is: `SDF MILESTONE 1 INVOICE AUTHORITY RECOVERY`.

## Executive status

De huidige websitevormgeving en functionaliteit zijn goedgekeurd. De finale hero-reeks op `origin/main` is via gecontroleerde fast-forwards opgebouwd en luidt:

```text
17669ab Fix homepage hero descender clipping
607256e Fix commercial hero descender animation
04fc8b3 Fix clipped descenders in commercial hero headings
```

Git-verificatie op 2026-08-14:

```text
origin/main                17669ab1e649f5cbfaeee6349ba8dccdc91a76ff
origin/fix/hero-descenders 17669ab1e649f5cbfaeee6349ba8dccdc91a76ff
```

De live homepage is na de laatste release visueel goedgekeurd. De productiebranch bevat de finale commerciële en homepage-descenderfixes. De GitHub Pages-workflow wordt bij iedere push naar `main` geactiveerd; de workflowrun-ID is in dit documentatiecheckpoint niet opnieuw opgevraagd.

"Klaar" geldt voor de huidige overeengekomen scope. Toekomstig onderhoud, nieuwe klantinhoud, gewijzigde wettelijke of bedrijfsgegevens, nieuwe features en dependency/security-updates blijven normale toekomstige werkzaamheden.

## Productiearchitectuur

### Publieke frontend

De website is een statische HTML/CSS/JavaScript-site.

| Onderdeel | Primaire paden | Verantwoordelijkheid |
|---|---|---|
| Homepage | `index.html`, `assets/css/redesign.css`, `assets/js/redesign.js`, `assets/js/homepage-studio.js` | Hero, positionering, services, demo-presentatie, proces, kwaliteit, about en CTA |
| Gedeelde pagina-opbouw | `assets/css/pages.css`, `assets/js/pages.js` | Navigatie, page hero's, contentsecties, formulieren en gedeelde interacties |
| Cookie consent | `assets/css/cookie-consent.css`, `assets/js/cookie-consent.js` | Consentinterface en voorkeuren |
| Baseline/legacy styling | `assets/css/style.css` | Onder andere utility-, legal- en oudere surfaces; niet verwijderen zonder consumeraudit |
| Foutpagina en metadata | `404.html`, `robots.txt`, `sitemap.xml`, `site.webmanifest`, `CNAME` | Fallback, indexing, manifest en custom domain |

### Diensten

- Overzicht: `pages/services.html`.
- Websites op maat: `pages/websites-op-maat.html`.
- Webshops: `pages/webshops.html`.
- SEO en vindbaarheid: `pages/seo.html`.
- Integraties en automatisering: `pages/integraties-automatisering.html`.
- Klanten- en ledenomgevingen: `pages/klanten-ledenomgevingen.html`.
- Multimedia en social: `pages/multimedia-social.html`.
- Hosting en onderhoud: `pages/hosting-onderhoud.html`.
- Aanvullende detailstyling: `assets/css/service-details.css`.

### Inhoudelijke pagina's

| Surface | Pad |
|---|---|
| Pricing | `pages/pricing.html` |
| FAQ | `pages/faq.html` |
| About | `pages/about.html` |
| Process | `pages/process.html` |
| Portfolio | `pages/portfolio.html` |
| Contact/offerteaanvraag | `pages/contact.html` |

### Conceptdemo's

Tien zelfstandige conceptdemo's staan onder `pages/demos/`:

1. `aurelis-architecture`
2. `cafe`
3. `garage`
4. `industrieel-elektriciteit`
5. `luna-hair-studio`
6. `mediterranean-brasserie`
7. `nova-estate`
8. `personal-portfolio`
9. `pulse-performance`
10. `restaurant`

Demo-specifieke CSS, JavaScript en beelden staan respectievelijk onder `assets/css/demos/`, `assets/js/demos/` en `assets/images/demos/`. De demo's zijn onderdeel van de allowlisted Pages-build.

### Aanvraag-, review- en intakeflows

| Surface | Frontend | Backend |
|---|---|---|
| Offerte/contact | `pages/contact.html`, `assets/js/pages.js` | `supabase/functions/submit-quote-request/index.ts` |
| Interne review | `pages/review-request.html`, `assets/js/review-request.js`, `assets/css/review-request.css` | `supabase/functions/review-quote-request/index.ts` |
| Klantintake | `pages/intake.html`, `assets/js/intake.js`, `assets/css/intake.css` | `supabase/functions/intake-quote-request/index.ts` |
| Read-only adminbriefing | `pages/admin-intake.html`, `assets/js/admin-intake.js`, `assets/css/admin-intake.css` | intakefunctie en capability-gebaseerde inspectie |
| Privacyverzoek | juridische/privacy-interface via gedeelde pageslogica | `supabase/functions/submit-privacy-request/index.ts` |

De functies-base-URL is `https://xcsptvntvrizwhskaphr.supabase.co/functions/v1` en wordt via `lws-functions-base-url`-metadata aan relevante frontends geleverd.

### Juridische pagina's

- `pages/privacy.html`
- `pages/cookies.html`
- `pages/algemene-voorwaarden.html`
- `pages/voorwaarden.html` als compatibiliteitsroute

Juridische en bedrijfsgegevens kunnen door toekomstige wettelijke of bedrijfswijzigingen onderhoud vereisen. Wijzig ze niet zonder inhoudelijke autorisatie.

### Branding en social assets

Productie gebruikt onder meer:

- `assets/images/branding/logo/lorenzo-web-solution-logo-transparent.png`;
- `assets/images/branding/social/lws-social-share.jpg`;
- favicons en app-icons onder `assets/icons/`;
- homepagebeelden onder `assets/images/home/showcase/`;
- demo-assets onder `assets/images/demos/`.

Twee andere brandingbestanden bestaan uitsluitend untracked in de originele werkboom en zijn geen production authority; zie **Beschermde originele werkboom**.

## Supabase en datalaag

### Configuratie

- Project-ID in `supabase/config.toml`: `xcsptvntvrizwhskaphr`.
- PostgreSQL major in lokale config: 17.
- Vier functies zijn geconfigureerd met `verify_jwt = false`; de functies handhaven hun publieke/capability-contracten zelf.
- Runtime function-versies en actuele production-applied migrationstatus zijn in deze documentatietaak niet opnieuw via het Supabase-platform opgevraagd. Gebruik historische checkpoints als evidence en voer voor een toekomstige backendrelease opnieuw een read-only runtimegate uit.

### Edge Functions

1. `submit-quote-request`: publieke offerteaanvraag, validatie, idempotency, business/VAT-context, rate limiting en adminnotificatie.
2. `review-quote-request`: capability-gebaseerde inspectie, approve/reject, bevestiging en intake-uitnodiging.
3. `intake-quote-request`: intake inspect/save/submit, Budget Guard/pricing preview, snapshots en adminbriefing.
4. `submit-privacy-request`: privacyverzoeken.

### Gedeelde backendmodules

- Pricingcatalogus en configuratie: `pricing-catalog.ts`, `pricing-config.ts`, `package-definitions.ts`.
- Normalisatie en engine: `pricing-normalization.ts`, `pricing-engine.ts`.
- Preview/read DTO's: `pricing-preview-handler.ts`, `pricing-preview-dto.ts`, `pricing-read-*.ts`.
- Snapshotintegriteit: `pricing-snapshot-integrity.ts`, `pricing-contract.ts`, `authoritative-intake.ts`.
- Security: `security.ts`, `validation.ts`, `vat-validation.ts`, `cors.ts`.
- Rate limiting: `rate-limit.ts`, `preview-rate-limit.ts`.
- E-mail: `email-templates.ts`, `email-delivery.ts`.
- Centrale types: `types.ts`.

### Database en migrations

De productieboom bevat 28 chronologische migrations onder `supabase/migrations/`. Hoofdverantwoordelijkheden:

- `quote_requests`, status, idempotency en business/VAT-velden;
- `quote_request_email_jobs`, deliveryclaims, retry en status;
- `quote_request_intakes`, invitation/save/submit/admin-inspect lifecycle;
- privacy requests;
- Budget Guard-compatibiliteit en intake-evidence;
- pricing snapshots v2/v3, read projections en integriteit;
- preview-rate-limit buckets;
- master pricing catalog v1;
- Phase D evidencevalidatie;
- intake/pricing contract v2 alignment.

Voer migrations nooit opnieuw of handmatig uit op basis van alleen dit document. Controleer eerst remote applied state, backups, SQL-impact en expliciete productieautorisatie.

### Budget Guard en pricing preview

De huidige repository bevat een package-aware pricingcatalogus, normalisatie, Budget Guard-evaluatie, preview DTO's, evidenceprovenance en snapshotintegriteit. Belangrijke surfaces zijn:

- `assets/js/intake.js`;
- `supabase/functions/_shared/pricing-*.ts`;
- `supabase/functions/_shared/package-definitions.ts`;
- `supabase/functions/_shared/preview-rate-limit.ts`;
- migrations vanaf `20260810120000_add_budget_guard_compatibility_layer.sql`.

Historische en semantische details staan in:

- `docs/BUDGET-GUARD-PRODUCTION-HANDOVER-20260811.md`;
- `docs/INTAKE-PROFESSIONAL-SEMANTICS-CHECKPOINT-20260813.md`;
- `docs/PHASE-D-CATALOG-CLASSIFICATION.md`.

### E-mail, capabilities en security

De aanvraagketen gebruikt jobgebaseerde e-maildelivery voor adminnotificatie, klantbevestiging, intake-uitnodiging en ingediende-intakenotificatie. Gedeelde templates en deliverylogica staan in `_shared/email-templates.ts` en `_shared/email-delivery.ts`.

Securitylagen in bron en migrations omvatten:

- capabilitytokens en HMAC-hashes;
- AES-GCM voor tijdelijk invitation-retrymateriaal;
- service-role-only databasegrenzen en ingetrokken publieke privileges;
- RLS en capability-gebaseerde RPC's;
- inputvalidatie en body-/method-/content-typegrenzen;
- idempotency en unieke databaseconstraints;
- IP-/preview-rate-limitlogica;
- VIES-validatie uitsluitend server-side.

Leg nooit secretwaarden of raw capabilities vast in Git, logs of documentatie.

## Tests en validatie

De repository bevat:

- frontend intake- en pricingtests onder `assets/js/*.test.ts`;
- gedeelde Deno-tests onder `supabase/functions/_shared/*.test.ts`;
- SQL/pgTAP-suites onder `supabase/tests/`;
- Pages-build- en verificatiescripts onder `scripts/`.

`package.json` bevat alleen de Supabase CLI als dev dependency en geen npm scripts. Gebruik daarom de expliciete Deno/Node/SQL-harnesses uit de relevante checkpointdocumenten. De volledige testset is in deze documentatietaak niet opnieuw uitgevoerd.

Een zoekactie op `TODO`, `FIXME`, `HACK` en `XXX` vond geen echte markers in de productiebron. Een eerdere tekstzoekhit zat in synthetische security-testdata en was geen taakmarker.

## Deployment en hosting

`.github/workflows/deploy-pages.yml` triggert op pushes naar `main` en op handmatige dispatch.

1. `scripts/prepare-pages-dist.ps1` bouwt een expliciet allowlisted `dist/`-artifact.
2. `scripts/verify-pages-dist.ps1` controleert vereiste paden, verboden bestanden, lokale links, Functions-base-URL en social metadata.
3. Alleen het artifact wordt geupload en via GitHub Pages gedeployed.

`docs/`, `supabase/`, repositorymetadata, TypeScript, SQL, Markdown, secrets en packagebestanden zijn uitgesloten van het publieke artifact. `CNAME` koppelt de custom domainflow aan `lorenzowebsolutions.be`.

## Finale hero-fixes - goedgekeurd

Deze fixes zijn productie-goedgekeurd. Wijzig ze niet opnieuw zonder een nieuwe concrete reproduceerbare aanleiding.

### Commerciële dienstenpagina's

**Oorspronkelijk probleem**

De compacte headingtypografie gebruikte `line-height: .92`. Descenders van `g`, `j`, `y`, `p` en `q` liepen buiten de `h1`-box. De algemene `page-title-entry`-animatie hield een `clip-path` actief en sneed die glyph-overhang af.

**Tijdelijke workaround en vervolgprobleem**

Commit `04fc8b3` voegde eerst toe:

```css
.page-hero--commercial h1:has(em) { animation-fill-mode:backwards; }
```

Na de animatie verviel de clip en werden descenders volledig zichtbaar. Tijdens de animatie bleef de clip echter actief, waardoor de onderste staart pas rond het eindmoment verscheen: een zichtbaar tweestaps- of "hup"-effect.

**Definitieve oplossing**

Commit `607256e` verving de workaround door een scoped animatienaam in `assets/css/pages.css`:

```css
.page-hero--commercial h1:has(em) { animation-name:page-title-entry-unclipped; }
```

Het private keyframe behoudt opacity en transform maar bevat geen `clip-path`:

```css
@keyframes page-title-entry-unclipped {
  from { opacity:0; transform:translate3d(0,22px,0); }
  to { opacity:1; transform:none; }
}
```

De bestaande algemene shorthand blijft duration `720ms`, delay `.08s`, easing `cubic-bezier(.16,1,.3,1)` en fill-mode `both` leveren.

**Validatie**

- Alle acht commerciële split-headings getest op desktop, tablet en circa 390 px.
- `clip-path:none` tijdens en na de animatie.
- `g/j/y/p/q` vanaf het eerste zichtbare frame volledig aanwezig.
- Geen pixelsprong meer rond 799 -> 801 ms.
- Font-size, line-height, letter-spacing, margins, regelafbreking en geometrie bleven gelijk.
- Geen layout shift, console-error of page-error in de gecontroleerde matrix.
- Pricing en Intake matchen de selector niet.

### Homepage

**Probleem en afzonderlijk systeem**

De witte `g` in `Resultaatgericht werkt.` werd onderaan afgesneden. De homepage gebruikt niet de commerciële headingcomponent, maar drie `.hero__line`-spans in `index.html` en eigen animaties in `assets/css/redesign.css`.

De derde regel gebruikte een initiële `clip-path: inset(100% 0 0 0)` en `title-from-depth` eindigde op `clip-path: inset(0)`. Met `animation-fill-mode: forwards` bleef die clip na afloop actief. In combinatie met de goedgekeurde compacte `line-height: .98` werd glyph-ink buiten de line-box afgesneden.

Gemeten overhang:

| Glyphs | Desktop | Mobiel circa 390 px |
|---|---:|---:|
| `g`, `j`, `y` | circa 13.11 px | circa 7.54 px |
| `p`, `q` | circa 12.11 px | circa 7.54 px |

**Definitieve oplossing**

Commit `17669ab` verwijderde uitsluitend de twee homepage-clips:

- `clip-path: inset(100% 0 0 0)` uit `.hero__line:nth-child(3)`;
- `clip-path: inset(0)` uit `@keyframes title-from-depth`.

Opacity, starttransform `translate3d(0,70px,0) rotateX(-18deg) scale(.92)`, transform-origin, duration `960ms`, delay `.56s`, easing en `forwards` bleven ongewijzigd.

**Validatie**

- Desktop en circa 390 px tijdens en na de animatie gecontroleerd.
- `clip-path:none` op alle meetmomenten.
- Opacity- en transformcurves exact gelijk aan de oorspronkelijke referentie.
- Font-size, `line-height:.98`, font-family, font-weight, letter-spacing, margins en eindgeometrie bleven gelijk.
- Geen layout shift, console-error of page-error.
- Commerciële headings afzonderlijk opnieuw gecontroleerd en onaangeraakt.
- Live visuele controle bevestigde dat de `g` volledig zichtbaar is.

## Git- en worktreesituatie

### Productieauthority

- `origin/main`: `17669ab1e649f5cbfaeee6349ba8dccdc91a76ff`.
- `origin/fix/hero-descenders`: dezelfde commit.
- Productiereeks: `04fc8b3` -> `607256e` -> `17669ab`.

### Beschermde originele werkboom

| Eigenschap | Waarde |
|---|---|
| Pad | `C:\Users\info\OneDrive\lorenzo-web-studio` |
| Branch | `main` |
| Lokale HEAD | `a1f3ecf719efc9dd541e7148c0ec7f7d4ba788eb` |
| Divergentie | `ahead 2, behind 29` tegenover `origin/main` |
| Staged | niets |
| Tracked unstaged | 19 bestanden |
| Untracked | 5 entries |

De twee lokale commits `bf70163` en `a1f3ecf` zijn patch-equivalent aan wijzigingen die reeds via andere commit-ID's in productie staan. Verplaats lokale `main` desondanks niet blind: de werkboom bevat beschermd, niet-geintegreerd werk.

**Tracked unstaged**

```text
README.md
assets/js/admin-intake.js
assets/js/intake.js
assets/js/review-request.js
docs/BUDGET-GUARD-PRODUCTION-HANDOVER-20260811.md
docs/PRODUCTION-BASELINE.md
pages/algemene-voorwaarden.html
pages/cookies.html
pages/demos/nova-estate/index.html
pages/intake.html
pages/privacy.html
supabase/functions/_shared/email-templates.test.ts
supabase/functions/_shared/email-templates.ts
supabase/functions/_shared/preview-rate-limit.test.ts
supabase/functions/_shared/preview-rate-limit.ts
supabase/functions/_shared/pricing-preview-dto.test.ts
supabase/functions/_shared/pricing-preview-dto.ts
supabase/functions/_shared/pricing-preview-handler.test.ts
supabase/functions/_shared/pricing-preview-handler.ts
```

Alle 19 huidige file-inhouden verschillen van `origin/main`. De diff bevat onder meer request-referencepresentatie, intake/packagecompatibiliteit, cacheversionering, e-mailtemplates, preview-rate-limitdiagnostiek, pricing-previewlogica en tests, historische documentatie en juridische/demo-copy. Niet voor ieder bestand is de uiteindelijke businessintentie alleen uit Git vast te stellen; aanvullende verificatie is nodig voordat iets wordt geïntegreerd of weggegooid.

**Untracked**

```text
assets/images/branding/logo/ChatGPT Image 7 aug 2026, 21_01_13.png
assets/images/branding/social/Instagram_LorenzoWebSolution.jpg
assets/js/intake-budget-guard-rendering.test.ts
pages/redesign-preview/index.html
supabase/.branches/_current_branch
```

Deze items zijn bewust behouden en geen production authority. Verwijder, verplaats, overschrijf of stage ze niet zonder expliciete toestemming.

**Waarom niet gebruikt voor hero-integraties**

De originele worktree was zowel inhoudelijk dirty als historisch gedivergeerd. De hero-fixes zijn daarom in een schone worktree vanaf de toen actuele `origin/main` gemaakt, getest en uitsluitend via fast-forward geïntegreerd. Zo bleven alle lokale wijzigingen behouden.

### Finale geïsoleerde worktree

| Eigenschap | Waarde |
|---|---|
| Pad | `C:\Users\info\lws-hero-descenders-worktree-20260814` |
| Branch | `fix/hero-descenders` |
| HEAD | `17669ab1e649f5cbfaeee6349ba8dccdc91a76ff` |
| Tracking | `origin/fix/hero-descenders` |
| Divergentie met `origin/main` | `0 0` |
| Status voor deze documentatietaak | schoon vóór documentatie |

Deze worktree is gebruikt omdat zij geïsoleerd, schoon en production-aligned was. De documentatie van dit checkpoint wordt hier voorbereid en blijft tot review ongecommit.

### Overige geregistreerde worktrees

Op 2026-08-14 waren veertien worktrees geregistreerd. Behalve de originele werkboom en de hieronder genoemde mobile-root-canvas-worktree waren de overige gecontroleerde worktrees schoon.

| Worktree/branch | HEAD | Statusopmerking |
|---|---|---|
| `lorenzo-web-studio-budget-guard-compat` / `fix/budget-guard-cache-compat-20260811` | `28d6a3b` | schoon, achter production |
| `lorenzo-web-studio-rollback` / `rollback/package-clarity-20260811` | `1d41dbc` | schoon, achter production |
| `content-completion-20260813` / `feature/process-about-faq-content-20260813` | `fc640a1` | schoon |
| `intake-i1-hosting-normalization-20260813` | `74ac8ff` | schoon, remote tracking aanwezig |
| `mobile-root-canvas-20260813` / `fix/mobile-root-canvas-20260813` | `24fd33a` | **dirty:** unstaged `assets/css/pages.css` en `assets/css/redesign.css`; voegt alleen `html`-achtergrondkleur toe |
| `preview-semantics-20260811` / `integration/preview-budget-semantics-20260811` | `a9e936e` | schoon |
| `pricing-catalog-v1-20260812` / featurebranch | `e54ec3b` | schoon, gedivergeerd van production |
| `pricing-integration-20260812` | `c8ac524` | schoon, remote tracking aanwezig |
| `production-db-release-20260812` | `24fd33a` | schoon, detached HEAD |
| `professional-semantics-tests-20260813` | `6f3951c` | schoon |
| `service-details-20260813` | `6bb4c29` | schoon |
| `website-p1-completion-20260813` | `4bf37e3` | schoon |

Oudere worktrees en branches zijn historische/operationele state. Verwijder ze niet automatisch. Hun actuele zakelijke noodzaak is niet vastgesteld; aanvullende verificatie is nodig voor eventuele archivering.

### OneDrive/Git-housekeeping

Na `commit` of `fetch` kan Git onder OneDrive herhaaldelijk vragen:

```text
Deletion of directory '.git/objects/XX' failed. Should I try again? (y/n)
```

Dit trad op tijdens automatische Git-housekeeping/mapverwijdering. De veilige werkwijze in de afgeronde sessies was:

1. antwoord `n`; forceer geen verwijderingsretry;
2. verifieer commit of remote ref read-only in een aparte shell;
3. beëindig alleen de vastgelopen housekeepingterminal als de prompt per objectmap blijft herhalen;
4. voer geen handmatige objectcleanup uit zonder aparte diagnose en toestemming.

Een mislukte housekeepingmapverwijdering betekent niet automatisch dat de voorafgaande commit/fetch is mislukt.

## DO NOT DESTROY / PRESERVATION GATE

Voor iedere volgende sessie:

- voer nooit `git reset --hard` uit op de originele werkboom;
- voer nooit `git clean` uit;
- voer nooit `git restore` uit op onbekende lokale wijzigingen;
- verwijder nooit modified of untracked bestanden zonder expliciete toestemming;
- zet lokale `main` nooit blind gelijk aan `origin/main`;
- gebruik nooit force push of `--force-with-lease` zonder afzonderlijke expliciete autorisatie;
- verwijder geen branches of worktrees als automatische cleanup;
- controleer altijd eerst `git status --branch --short`, staged diff, unstaged diff, `HEAD`, `origin/main` en merge-base;
- gebruik voor nieuwe gerichte fixes bij voorkeur een nieuwe schone geïsoleerde worktree/branch vanaf de actuele remote basis;
- stage altijd expliciet per bestand, nooit met `git add .` of `git add -A`;
- controleer voor commit `git diff --cached --name-only`, `git diff --cached` en `git diff --check --cached`;
- fetch en controleer remote basis opnieuw voor push;
- integreer alleen via een aantoonbare fast-forward of een afzonderlijk goedgekeurde reviewflow;
- wijzig of deploy Supabase niet zonder runtime-, migration-, backup- en secretgates;
- noteer nooit secrets of raw capabilities in chat, Git of documentatie.

## Openstaande zaken

### A. Blokkerend voor productie

- Geen blokkades vastgesteld voor de huidige goedgekeurde websitescope.
- Websitecode en live visuele toestand zijn goedgekeurd op productiecommit `17669ab`.

### B. Niet-blokkerend operationeel

- Originele werkboom bevat beschermd lokaal werk; niet integreren of verwijderen zonder aparte analyse.
- Mobile-root-canvas-worktree bevat twee unstaged CSS-wijzigingen; niet automatisch opruimen.
- Oudere worktrees/branches zijn nog geregistreerd; zakelijke archiveringsbehoefte niet vastgesteld.
- OneDrive kan Git-housekeeping blokkeren met objectmap-prompts.
- Exacte actuele Supabase runtimeversies en production-applied migrationstatus zijn in deze documentatietaak niet opnieuw vastgesteld.
- Historische checkpoints noemen minder volledig gevalideerde reject/retry/providerfailure/rate-limit-under-load/`reviewed`-paden; actuele aanvullende productievalidatie niet vastgesteld.
- `package.json` bevat geen test/lint/buildscripts; tests vereisen expliciete harnesses.
- De Pages-verificatie controleert de Functions-base-URL expliciet in homepage en contactpagina; uitbreiding naar alle function-consuming utilitypagina's is niet vastgesteld als nodig.

### C. Toekomstige verbetering

Alleen starten na nieuwe opdracht:

- nieuwe klantinhoud of service-uitbreidingen;
- wijzigingen aan wettelijke of bedrijfsgegevens;
- dependency- en securityonderhoud;
- aanvullende failure-path- en belastingtests;
- automatische offertegeneratie: niet vastgesteld als geïmplementeerd;
- externe KBO-verificatie naast lokale Belgische ondernemingsnummercontrole: niet vastgesteld als geïmplementeerd;
- technische standaardisering of herbruikbare demo-/klantprojecttemplates;
- historische notitie over mogelijk extra mobiel scrollgebied onder de footer: in dit checkpoint niet opnieuw gereproduceerd, aanvullende verificatie nodig.

### D. Bewust lokaal/onafgewerkt

- De 19 tracked unstaged en vijf untracked entries in de originele werkboom.
- De twee unstaged root-backgroundregels in de mobile-root-canvas-worktree.
- Oudere branches/worktrees waarvan de toekomstige noodzaak niet is vastgesteld.

## Veilige hervatting

1. Lees eerst dit document.
2. Controleer `origin/main` en deploymentstatus opnieuw.
3. Inventariseer alle worktrees en voer preservation gates uit.
4. Kies production source, niet de gedivergeerde originele `main`, als technische basis.
5. Gebruik een nieuwe schone worktree voor een nieuwe gerichte scope.
6. Lees voor intake/pricingwerk ook de drie gespecialiseerde checkpoints.
7. Voer reproduceerbare tests zelfstandig uit voordat menselijke visuele validatie wordt gevraagd.
8. Vraag expliciete toestemming vóór staging, commit, push, deployment, migration of cleanup.

## Documentenhiërarchie

- **Primair actueel:** `docs/FINAL-PRODUCTION-CHECKPOINT-20260814.md`.
- Historische brede baseline: `docs/PRODUCTION-BASELINE.md`.
- Vorige master handover: `docs/LWS_MASTER_HANDOVER_CHECKPOINT_2026-08-13.md`.
- Budget Guard evidence: `docs/BUDGET-GUARD-PRODUCTION-HANDOVER-20260811.md`.
- Professional semantics: `docs/INTAKE-PROFESSIONAL-SEMANTICS-CHECKPOINT-20260813.md`.
- Catalog/evidenceclassificatie: `docs/PHASE-D-CATALOG-CLASSIFICATION.md`.

Wanneer oudere statusclaims conflicteren met dit checkpoint, geldt dit checkpoint voor Git-, website- en hervattingsstatus op 2026-08-14. Historische technische evidence blijft geldig binnen haar gedocumenteerde datum en scope.
