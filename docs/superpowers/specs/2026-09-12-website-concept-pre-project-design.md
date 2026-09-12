# LWS Website Concept / PRE_PROJECT V1

Status: ontwerp gereed voor owner review
Datum: 2026-09-12
Basis: huidige Operator Dossiers-, Multi-Screen-, Website Execution-, Requirements- en commerciële authorities
Scopebeperking: dit document is uitsluitend een ontwerp. Het autoriseert geen implementatie, migration, push, deploy of productiemutatie.

## 1. Doel

Een actief Website-dossier moet een interne technische werkruimte kunnen krijgen voordat een offerte, klantacceptatie, factuur, betaling of commerciële release bestaat.

De owner-flow wordt:

1. `ACTIEF DOSSIER` toont de server-authoritative actie `[ WEBSITE-CONCEPT STARTEN ]`.
2. De owner bevestigt exact: `Voorlopig concept starten — dit is nog geen commerciële bestelling`.
3. De server maakt idempotent één duurzame `PRE_PROJECT / CONCEPT`-authority en één stabiele website-work-context.
4. Het dossier toont `[ WEBSITE OPENEN ]`.
5. Deze actie opent de bestaande Website Execution Workspace in de bestaande Multi-Screenarchitectuur.

Een concept is uitsluitend een interne LWS-werkruimte. Het ontstaan ervan betekent uitdrukkelijk niet:

- een klantbestelling;
- een geaccepteerde offerte;
- een betalingsverplichting of openstaande betaling;
- een commerciële release;
- toestemming tot publicatie of productiegebruik;
- creatie van Finance-, factuur- of milestone-state;
- verzending van klantmail;
- toestemming om de officiële projectworkflow te omzeilen.

### 1.1 Ontwerpbeslissing

De aanbevolen architectuur is **optie B: een aparte duurzame `website_concept`-authority, gekoppeld aan één lifecycle-neutrale `website_work_context` die door Website Execution wordt gebruikt**.

`public.commercial_projects` blijft uitsluitend de root voor een geaccepteerde commerciële overeenkomst. Een pre-project wordt daar niet als fictief project ingevoegd. Websitewerk wordt evenmin gedupliceerd: concept en later officieel project wijzen naar dezelfde `website_work_context_id`.

## 2. Niet-doelen

V1 omvat niet:

- offertecreatie, -goedkeuring, -uitgifte of -acceptatie;
- facturatie, Finance, betalingsverwachtingen, payment evidence of milestones;
- commerciële projectrelease of `PROJECT_WORK_STARTED`;
- klanttoegang, klantnotificatie of automatische e-mail;
- preview-access voor klanten;
- publicatie, productie-URL-activering, DNS, hostingcutover of livegang;
- automatische repositorycreatie of externe provider-I/O;
- intakevelden automatisch omzetten naar requirements;
- een concept promoveren naar een officieel project;
- bestaande commerciële lifecycle-, startgate- of Requirements-semantiek versoepelen;
- een tweede Website builder, takenbord of repositorymodel bouwen;
- algemene refactoring van Operator Dossiers of Multi-Screen.

De laatste twee functionele onderwerpen worden wel contractueel ontworpen in secties 12 en 13, maar blijven buiten implementatie en release van V1.

## 3. Bestaande architectuur die wordt hergebruikt

### 3.1 Dossierroot

`public.quote_requests.id` blijft de canonieke dossieridentiteit. Een concept is alleen geldig voor een bestaand production-record met `request_kind = 'website'`. Een dossiernummer of andere zichtbare requestreferentie wordt via de bestaande dossierprojectie gelezen en niet als tweede identitybron gekopieerd.

### 3.2 Commerciële root blijft gesloten

`public.commercial_projects` vereist vandaag onder meer:

- een `commercial_customers`-row die aan quotation acceptance is gebonden;
- een unieke `quotation_issuance_id`;
- een unieke `acceptance_id`;
- geaccepteerde bedragen, valuta en drie milestonebedragen;
- money coherence en een commerciële lifecycle-state.

De tabel, auditlog, idempotency ledger, obligations, payment authorities en project-startgate vormen samen één commerciële invariant. Een `PRE_PROJECT`-row zonder deze feiten zou die invariant inhoudelijk breken, ook als columns technisch nullable zouden worden gemaakt. Daarom verandert dit ontwerp de betekenis van `commercial_projects` niet.

### 3.3 Website Execution Workspace

De bestaande Website Execution Workspace, child module, repositoryvalidatie en slotrouting worden hergebruikt. De huidige databasebinding is nog exact `project_id + quote_request_id` en vereist een immutable `PROJECT_WORK_STARTED`-event. Voor PRE_PROJECT wordt die commerciële locator vervangen door een canonieke `website_work_context_id`; de server resolveert vanuit die context concept- of projecteligibility.

De UI blijft één Website Execution Workspace. Er ontstaat geen concept-specifieke kopie van die module.

### 3.4 Requirements Board

De huidige `project_requirements_boards` en `project_requirements` zijn hard gebonden aan `commercial_projects.project_id`, quotation approval en accepted quotation scope. Zij blijven in V1 commercieel en worden niet gebruikt om vrijblijvende conceptrequirements te veinzen.

De Website Execution Workspace toont bij een PRE_PROJECT in V1 een stabiele, expliciete lege Requirements-state: `Requirements volgen na intake-sync.` De latere contextgebonden intake-sync staat in sectie 12. Hierdoor is de workspace nu bruikbaar zonder de bestaande Requirements-authority semantisch te verzwakken.

### 3.5 Server- en Multi-Screenpatronen

Het ontwerp hergebruikt:

- caller-JWT-propagatie naar de servercommandlaag;
- geforceerde RLS en ingetrokken directe table privileges;
- server-side operator-, rol-, status- en AAL2-resolutie;
- bounded commands met idempotency key en request fingerprint;
- immutable auditfacts;
- server-authoritative `permitted_actions`;
- de bestaande module-slotclaim, lease, duplicate-focus, revoke en invalidationprotocollen;
- child-side herresolutie van dossier en authority in plaats van vertrouwen op openerdata.

## 4. User flow

### 4.1 Starten

1. De owner opent een actief Website-dossier.
2. De dossierprojectie retourneert `website_work.state = 'NONE'` en `CAN_START_WEBSITE_CONCEPT` wanneer alle servervoorwaarden gelden.
3. De UI toont `[ WEBSITE-CONCEPT STARTEN ]` uitsluitend omdat deze actie in `permitted_actions` staat.
4. Klik opent een blocking confirmation dialog met exact de tekst: `Voorlopig concept starten — dit is nog geen commerciële bestelling`.
5. Annuleren muteert niets.
6. Bevestigen verstuurt alleen `quote_request_id`, `expected_website_work_revision` en een nieuwe `idempotency_key`.
7. De server hercontroleert identity, actieve ownerrol, AAL2, dossierclassificatie, producttype en afwezigheid van een bestaand concept of officiële projectbinding.
8. De server creëert atomair concept, work-context en immutable create-event, of retourneert idempotent het reeds door dezelfde command gecreëerde resultaat.
9. Na een complete authoritative response vervangt de UI de dossierpresentatie atomair door `PRE_PROJECT / CONCEPT` met `[ WEBSITE OPENEN ]`.

### 4.2 Openen

1. `[ WEBSITE OPENEN ]` gebruikt het bestaande slot `website-{quote_request_id}`.
2. De child leest `quote_request_id` uit het slot en haalt dossier plus canonieke website-work-context opnieuw bij de server op.
3. De server retourneert `mode = 'PRE_PROJECT'`, `concept_id`, `website_work_context_id`, briefingstatus en de bestaande technische workspaceprojectie.
4. De child toont duidelijk `Voorlopig concept` en `Niet commercieel vrijgegeven`.
5. Bestaande veilige links en repositoryreferenties worden alleen getoond wanneer zij server-side aan dezelfde work-context zijn gebonden.
6. Productie- en publicatieacties blijven afwezig.

### 4.3 Reeds bestaand officieel project

Wanneer het dossier al een geldige `commercial_project`-binding heeft, wordt `CAN_START_WEBSITE_CONCEPT` nooit aangeboden. De bestaande officiële Project- en Websiteflows blijven leidend. V1 maakt geen concept achteraf naast een officieel project.

## 5. UI-state matrix

| Authoritative toestand | Ownerpresentatie | Andere operatorpresentatie | Toegestane actie | Verboden implicatie |
|---|---|---|---|---|
| Dossier laadt, nog geen eerdere snapshot | Bestaande loading-state | Bestaande loading-state | Geen | Geen authority afleiden uit loading |
| Website-dossier, geen concept/project, eligible | `Nog geen websiteconcept` | `Nog geen websiteconcept` | Owner: `WEBSITE-CONCEPT STARTEN` | Geen bestelling of release |
| Website-dossier, geen concept/project, niet eligible | Reden zonder startactie | Dezelfde veilige readstate | Geen | Client mag eligibility niet reconstrueren |
| Confirmation open | Exacte niet-commerciële bevestiging | Niet bereikbaar | Bevestigen of annuleren | Geen side effect vóór bevestiging |
| Startcommand in flight | Laatste geldige dossierpresentatie blijft staan; startbutton disabled | Niet van toepassing | Geen tweede submit | Geen tijdelijke lege Project/Website-state |
| Actief concept | Badge `PRE_PROJECT / CONCEPT`, briefingstatus en `WEBSITE OPENEN` | Alleen indien bestaande dossier-readrole dit toestaat; nooit startactie | Openen | Geen offerte-, Finance- of publicatiestatus |
| Actief concept, workspace nog niet gekoppeld | Zelfde conceptpresentatie; Workspace toont stabiel `Technische werkruimte nog niet gekoppeld` | Zelfde readcontract | Openen/vernieuwen | Geen fictieve repository |
| Officieel project | Bestaande Projectpresentatie en `WEBSITE OPENEN` volgens commerciële gates | Bestaand rolecontract | Bestaande acties | Geen concept-startactie |
| Same-record background refresh | Laatste volledige snapshot blijft zichtbaar | Idem | Bestaande acties blijven stabiel | Geen `-`, null, hide/show of loadingflits |
| Refreshfout na geldige snapshot | Snapshot blijft zichtbaar plus niet-destructieve foutmelding | Idem | Geen nieuwe authority uit stale data | Geen presentation reset |
| Cross-dossier switch | Vorige dossierstate wordt direct verwijderd; nieuwe loading-state | Idem | Geen tot nieuwe snapshot | Geen datalek tussen dossiers |
| Binding mismatch/revoked access | Gevoelige inhoud wordt gesloten en foutstate getoond | Idem | Geen | Geen fallback op clientcache |

## 6. Data model / lifecycle

### 6.1 Opties

| Optie | Voordelen | Risico's | Migration-impact | Promotiecomplexiteit | Website Execution / Requirements |
|---|---|---|---|---|---|
| A. `PRE_PROJECT` als state in `commercial_projects` | Eén zichtbaar project-id; weinig frontendlocators | Vereist fake acceptance, issuance en money of verzwakt bestaande not-null/moneyinvarianten; kan Finance en commerciële events onterecht activeren | Hoog en risicovol in de centrale commerciële root en alle joins | Schijnbaar laag, feitelijk veel reparatie van fake commerciële lineage | Website Execution past technisch, Requirements blijft onjuist quotation-scoped |
| B. Aparte duurzame conceptbinding met gedeelde work-context | Zuivere niet-commerciële semantiek; één technische workspace; promotie zonder kopiëren; bestaande commercial root blijft intact | Vereist een expliciete lifecycle-neutrale context en tijdelijke compatibiliteitslaag | Additieve concept/contextfoundation plus gerichte re-anchoring van technische workspace | Beheersbaar: bind later project aan dezelfde context in één transactie | Website Execution wordt contextgebonden; Requirements blijft V1 commercieel en kan later dezelfde context volgen |
| C. Een andere bestaande projectauthority hergebruiken | Mogelijk minder nieuwe tabellen | Geen bestaande authority bezit exact deze identiteit; pricing/audit/work-start roots hebben andere eligibility en lifecycle | Onvoorspelbaar en verspreid | Hoog door semantische vertaling en verborgen coupling | Leidt tot een tweede betekenis voor een bestaande authority en lost hard project-FK's niet op |

**Keuze: optie B.** Dit is de enige optie die een duurzaam concept mogelijk maakt zonder commerciële feiten te fabriceren en zonder een tweede Website Execution Workspace te creëren.

### 6.2 `website_concepts`

Conceptueel contract voor `public.website_concepts`:

| Veld | Contract |
|---|---|
| `concept_id uuid` | Primary key; duurzame conceptidentiteit. |
| `quote_request_id uuid` | Not null FK naar `quote_requests(id)`; één conceptlijn per Website-dossier. |
| `mode text` | Not null en in V1 exact `PRE_PROJECT`. |
| `briefing_status text` | Not null: `LIMITED` of `COMPLETE`; server-derived, geen commerciële gate. |
| `commercially_released boolean` | Not null, default en check exact `false`; nooit door promotie naar true gezet. |
| `concept_status text` | `ACTIVE` of `PROMOTED`; geen delete-as-lifecycle. |
| `promoted_project_id uuid` | Nullable FK naar `commercial_projects`; alleen bij `PROMOTED`. |
| `revision bigint` | Positieve optimistic-concurrencyrevision. |
| `created_by uuid` | FK naar de server-resolved actieve owneroperator. |
| `created_at`, `updated_at`, `promoted_at` | Servertimestamps met status-shapeconstraints. |

Integriteit:

- `unique (quote_request_id)` blokkeert een tweede concept, ook na promotie;
- `unique (promoted_project_id)` voor niet-null waarden;
- `ACTIVE` vereist `promoted_project_id is null` en `promoted_at is null`;
- `PROMOTED` vereist beide promotievelden;
- request-product en production-classification worden door trigger/commandguard onder lock gevalideerd;
- een conceptrow bevat geen bedragen, betaalstatus, offerteclaims, klanttoestemming of publicatierecht.

`briefing_status` is deterministisch: `COMPLETE` geldt uitsluitend wanneer voor hetzelfde dossier een intake bestaat met status `submitted` of `reviewed` en een niet-null `submitted_at`; in alle andere gevallen geldt `LIMITED`. De server berekent dit bij creatie en bij latere expliciete intake-sync opnieuw. `COMPLETE` is alleen een informatievolledigheidsclaim en verleent geen commerciële authority.

De zichtbare dossierreferentie is optioneel presentatiedata uit `quote_requests`; zij wordt niet als mutable kopie in `website_concepts` opgeslagen.

### 6.3 `website_work_contexts`

Conceptueel contract voor `public.website_work_contexts`:

| Veld | Contract |
|---|---|
| `website_work_context_id uuid` | Primary key; stabiele technische identiteit vóór en na promotie. |
| `quote_request_id uuid` | Not null en unique; canonieke dossierbinding. |
| `concept_id uuid` | Nullable, unique FK naar `website_concepts`. |
| `project_id uuid` | Nullable, unique FK naar `commercial_projects`. |
| `phase text` | `PRE_PROJECT` of `OFFICIAL_PROJECT`. |
| `revision bigint` | Positieve concurrency- en invalidationrevision. |
| `created_at`, `updated_at` | Servertimestamps. |

Shapecontract:

- `PRE_PROJECT`: `concept_id` is verplicht en `project_id` is null;
- `OFFICIAL_PROJECT`: `project_id` is verplicht; `concept_id` blijft gevuld na promotie of is null voor een project dat zonder concept begon;
- minimaal één van concept of project bestaat;
- concept, project en context moeten server-side naar exact dezelfde `quote_request_id` resolven;
- één dossier heeft maximaal één work-context;
- de context-id verandert nooit tijdens promotie.

### 6.4 Website Execution-binding

`website_execution_workspaces` wordt doelgericht aan `website_work_context_id` gebonden. Bestaande officiële rows krijgen eerst een context die naar hun huidige project en dossier verwijst. De huidige repository uniqueness, URL-, branch-, commit- en providerconstraints blijven behouden.

Tijdens een forward-only compatibiliteitsfase mogen legacy `project_id` en `quote_request_id` als gecontroleerde projectie aanwezig blijven, maar zij zijn niet langer een onafhankelijke authority. Iedere write/read verifieert equality met de work-context. Na bewezen cutover kan een latere migration redundante locators verwijderen.

V1 maakt bij conceptstart niet automatisch een repository of workspace-row. De context bestaat wel direct, zodat `[ WEBSITE OPENEN ]` een geldige lege technische workspace kan tonen en latere koppeling dezelfde identiteit gebruikt.

### 6.5 Concept-events en idempotency

`public.website_concept_events` is de immutable auditroot voor conceptcommands en bevat minimaal `event_id`, `concept_id`, `website_work_context_id`, `quote_request_id`, `event_type`, server-resolved `actor_id`, `actor_role`, `command_id`, veilige metadata en `occurred_at`. V1 staat alleen `WEBSITE_CONCEPT_STARTED` toe. Metadata mag geen token, capability, credential, klantinhoud of andere secret bevatten.

`public.website_concept_idempotency_ledger` bevat minimaal `operation_id`, `actor_id`, `quote_request_id`, `command_type`, `idempotency_key`, `request_fingerprint`, `result_reference`, de complete veilige result snapshot en `created_at`. De unieke sleutel is `(actor_id, command_type, idempotency_key)`. Een tweede unieke bescherming op `(quote_request_id, command_type)` voorkomt dat verschillende keys een tweede startfact creëren. Beide tabellen volgen forced RLS, ingetrokken directe privileges en uitsluitend server-authoritative writes.

Deze roots zijn bewust gescheiden van `public.audit_events` en `public.idempotency_ledger`, omdat die een bestaand `commercial_projects.project_id` vereisen. Zij vormen geen algemeen tweede auditsysteem: hun scope is uitsluitend conceptcreatie en de latere expliciete promotie.

### 6.6 Lifecycle

```text
NONE
  -- owner start, no commercial prerequisites -->
PRE_PROJECT / ACTIVE
  -- later, all independent commercial gates green + explicit promote command -->
PRE_PROJECT / PROMOTED + OFFICIAL_PROJECT
```

Er is geen overgang van `commercially_released = false` naar true op de conceptrow. Commerciële release blijft uitsluitend afgeleid uit het officiële `commercial_project`. Conceptstatus en projectstatus blijven verschillende feiten.

## 7. Authority

### 7.1 Readmodel

De server retourneert onder het dossier één gesloten `website_work`-object:

- `state`: `NONE`, `PRE_PROJECT` of `OFFICIAL_PROJECT`;
- `quote_request_id`;
- `concept_id` of null;
- `project_id` of null;
- `website_work_context_id` of null;
- `mode`;
- `briefing_status`;
- `commercially_released`, voor PRE_PROJECT altijd false;
- `revision`;
- `permitted_actions`.

`CAN_START_WEBSITE_CONCEPT` staat alleen in `permitted_actions` wanneer de server bewijst:

- caller is via `auth.uid()` gebonden aan een `ACTIVE` commercial operator;
- role is exact `owner`;
- sessie is AAL2;
- request bestaat, is `website`, `production` en bevindt zich in de actieve dossierbucket;
- er bestaat geen concept, work-context of officieel project voor dit dossier;
- het dossier is niet trashed, purged of onder een conflicterende mutatie.

Admin, operations manager, operator, finance en customer krijgen deze actie nooit. De frontend controleert de rol niet als authority en construeert de actie niet uit losse velden.

### 7.2 Startcommand

Het publieke commandcontract is conceptueel `start_website_concept_v1(quote_request_id, expected_website_work_revision, idempotency_key)`.

De commandlaag:

1. resolveert de caller opnieuw en vereist actieve owner plus AAL2;
2. lockt de request en eventuele concept/context/projectbindings;
3. herberekent eligibility;
4. berekent een fingerprint over actor, request, expected revision en commandtype;
5. blokkeert een afwijkende payload bij hergebruik van de idempotency key;
6. maakt concept en context in één transactie;
7. schrijft een immutable `WEBSITE_CONCEPT_STARTED`-event in een concept-specifieke auditauthority;
8. schrijft geen `audit_events`-row die een `commercial_project.project_id` vereist;
9. retourneert één complete nieuwe `website_work`-snapshot.

De browser levert geen role, mode, briefingstatus, commercial release, dossierclassificatie of created-by identity aan.

### 7.3 Duplicaatcontract

Concurrente eerste starts voor hetzelfde dossier serialiseren op de requestrow en unique constraints. Exact één concept/contextpaar ontstaat. Een replay met dezelfde key en fingerprint retourneert hetzelfde resultaat; een andere key na creatie retourneert `WEBSITE_CONCEPT_ALREADY_EXISTS`; dezelfde key met andere fingerprint retourneert `IDEMPOTENCY_CONFLICT`.

## 8. Error/fail-closed gedrag

- Onbekende, niet-Website-, niet-production-, trashed of niet-actieve dossiers: geen permitted action en geen mutatie.
- Niet-owner of niet-AAL2: `42501`, geen concept/event/context.
- Bestaand concept, officieel project of conflicterende context: geen tweede root.
- Mismatch tussen request, concept, context, project of workspace: `WEBSITE_WORK_CONTEXT_BINDING_MISMATCH`; gevoelige childinhoud wordt gesloten.
- Stale expected revision: concurrency error; client haalt een nieuwe volledige snapshot op en herhaalt nooit automatisch de mutatie.
- Transactiefout: concept, context en event rollen samen terug.
- Edge/network timeout na submit: de UI behoudt de laatste snapshot en resolveert via idempotency key; zij neemt succes niet aan.
- Background-refreshfout: laatste geldige presentatie blijft gemount; een niet-destructieve status meldt dat vernieuwen niet lukte.
- Ontbrekende workspace/repository: geldige lege state, geen fout en geen verzonnen link.
- Ontbrekende Requirements Board: geldige V1-state `Requirements volgen na intake-sync.`
- Geen enkele fout activeert klantmail, Finance, milestones, project release, preview access of publicatie.

Tabellen krijgen forced RLS en geen directe privileges voor `public`, `anon`, `authenticated` of browserbereikbare `service_role`-routes. Reads en writes lopen uitsluitend via minimaal geprivilegieerde security-definer authorities met vaste `search_path` en caller-JWT-context.

## 9. Multi-Screen binding

De bestaande modulekey voor Website Execution en het slot `website-{quote_request_id}` blijven behouden. De dossieridentiteit is stabiel vóór en na promotie; een tweede `concept-*`-slot zou duplicate windows en promotieomleiding veroorzaken en is daarom verboden.

Contract:

- de master opent/bestaat de bestaande Website-module met dezelfde module-slot singleton policy;
- de child accepteert alleen een geldig UUID uit het slot;
- de child resolveert zelf dossier, caller authorization en `website_work_context` bij de server;
- openerpayload, DOM-state en URL-querydata zijn geen authority;
- server lease, local lock, claim, epoch, sequence, revoke en duplicate-focus blijven ongewijzigd;
- invalidations richten zich op de bestaande Websiteslotkey plus de nieuwe contextrevision;
- bij promotie blijft hetzelfde slot open en wordt na invalidation de phase atomair `OFFICIAL_PROJECT`;
- een binding mismatch, revoked claim of verloren authorization sluit de inhoud fail-closed;
- een refresh verandert nooit de module- of slotidentiteit.

De Website-child mag in PRE_PROJECT geen `projectWorkspaceRequest(detail)` als verplichte locator gebruiken. Zij vraagt de canonieke website-work-context op met `quote_request_id`; de server retourneert alleen een project-id wanneer een officiële binding bestaat.

## 10. UI Stability Contract

Voor Dossiers en Website Execution geldt een verplicht snapshotcontract:

1. De eerste load mag een loading-state tonen zolang nog geen geldige snapshot bestaat.
2. Een same-record refresh wist nooit een geldige dossier-, concept-, workspace-, repository- of Requirements-presentatie.
3. Componenten blijven tijdens background refresh gemount en zichtbaar.
4. Geen enkel geldig veld verandert tijdelijk naar `-`, null, lege tekst, `hidden` of een generieke loading-state.
5. De client bouwt eerst een volledige, gevalideerde authoritative snapshot en commit die daarna atomair.
6. Een gedeeltelijke of binding-inconsistente response wordt geheel verworpen.
7. Een refreshfout behoudt de laatste geldige snapshot; alleen een afzonderlijke niet-destructieve foutstatus mag wijzigen.
8. Een startcommand behoudt de oude snapshot totdat de complete nieuwe PRE_PROJECT-snapshot is gevalideerd.
9. Een cross-dossier switch moet de vorige dossierdata onmiddellijk verwijderen en mag vervolgens loading tonen.
10. Revocation of authorization failure heeft voorrang op retentie en sluit gevoelige inhoud fail-closed.

De testbare definitie van stabiel is: bij frame- of MutationObserver-sampling over minimaal drie automatische refreshcycli zijn er nul frames waarin een eerder geldige same-dossierpresentatie ontbreekt, verborgen is of placeholders toont.

## 11. V1 scope

V1 levert uitsluitend het volgende functionele contract:

- owner-only `CAN_START_WEBSITE_CONCEPT` in de authoritative dossierprojectie;
- exacte confirmation dialog;
- idempotente durable creatie van `website_concepts` en `website_work_contexts`;
- concept-specifiek immutable create-event;
- zichtbare `PRE_PROJECT / CONCEPT`-status en briefingstatus;
- `[ WEBSITE OPENEN ]` vanuit een actief concept;
- bestaande Website Execution Workspace via dezelfde Multi-Screenslot;
- een geldige lege technische workspace wanneer nog geen repository is gekoppeld;
- expliciete lege Requirements-state tot intake-sync bestaat;
- same-record snapshotretentie en cross-dossierclear;
- negatieve bewijzen voor mail, Finance, commercial release en publication rights.

V1 creëert geen extern technisch resource. Een reeds later door een afzonderlijke geautoriseerde flow gekoppelde repository/site-reference behoort aan de work-context, niet aan concept of project afzonderlijk.

## 12. Later: intake-sync

Een latere, afzonderlijk goed te keuren fase mag intake-inhoud naar contextgebonden conceptrequirements synchroniseren. Die fase moet:

- `website_work_context_id` als root gebruiken;
- de originele intake als immutable bronreferentie en hash bewaren;
- LIMITED briefing accepteren zonder commerciële volledigheid te suggereren;
- idempotent dezelfde intakeversie verwerken;
- handmatig websitewerk niet overschrijven;
- conflicten expliciet markeren in plaats van stil samenvoegen;
- geen accepted quotation, prijs of betaling afleiden;
- bij promotie dezelfde requirements en taken behouden.

De bestaande `project_requirements_boards` worden niet in V1 polymorf gemaakt. Voor de latere fase wordt eerst een apart migrationdesign gereviewd dat ofwel deze tabellen veilig naar `website_work_context_id` re-anchort, ofwel een bewezen compatibele contextgebonden requirementsauthority introduceert. De beslisregel ligt vast: er mag uiteindelijk slechts één zichtbaar Requirements Board per website-work-context bestaan en promotie mag geen items kopiëren.

## 13. Later: concept → officieel project promotie

Promotie is een afzonderlijk ownercommand en is geen onderdeel van V1. Het toekomstige contract is:

```text
PRE_PROJECT
  + quotation issued and accepted
  + canonical commercial_project exists
  + exact dossier/project lineage valid
  + explicit owner promotion command
  -> OFFICIAL_PROJECT on the same website_work_context_id
```

De promotietransactie:

1. vereist actieve owner, AAL2, idempotency key en expected contextrevision;
2. lockt concept, context en officieel project;
3. bewijst exact dezelfde `quote_request_id`, issuance en acceptance lineage;
4. zet `website_concepts.concept_status = 'PROMOTED'` en bindt `promoted_project_id`;
5. zet op dezelfde context `project_id` en `phase = 'OFFICIAL_PROJECT'`;
6. bewaart dezelfde `website_work_context_id`;
7. schrijft een immutable promotie-event met concept-, context-, project- en request-id;
8. verplaatst of kopieert geen workspace, repository, site-reference, requirement of taak;
9. invalideert het bestaande Websiteslot voor atomische herresolutie.

Promotie bewijst uitsluitend identitybinding. Zij:

- bevestigt geen betaling;
- maakt geen payment evidence;
- verandert geen milestone;
- voert geen commercial release uit;
- schrijft geen `PROJECT_WORK_STARTED`;
- verleent geen preview-, publicatie- of klantrecht;
- verzendt geen klantmail.

Na promotie blijven de bestaande commerciële startgate en alle Finance-/releasevoorwaarden onafhankelijk leidend. Websitewerk dat vóór promotie bestond blijft technisch aanwezig, maar commerciële uitvoering/publicatie wordt pas toegestaan door de bestaande afzonderlijke authorities.

## 14. Teststrategie

### 14.1 Schema- en contracttests

- concept/context shapeconstraints en unique dossierbinding;
- geen concept voor niet-Website-, niet-production-, trashed of onbekend dossier;
- geen fake of gewijzigde `commercial_projects`-row;
- workspacebinding resolveert PRE_PROJECT zonder project-id;
- bestaande officiële workspacebindings blijven exact werken na backfill;
- context-, dossier-, concept- en projectmismatch falen gesloten;
- forced RLS, revoke/grant en security-definer search paths zijn aantoonbaar correct.

### 14.2 Authoritytests

- actieve owner met AAL2 krijgt `CAN_START_WEBSITE_CONCEPT` wanneer eligible;
- owner zonder AAL2, admin, operations manager, operator, finance en customer krijgen de actie niet en kunnen het command niet uitvoeren;
- browservelden kunnen role, mode, briefingstatus of release niet beïnvloeden;
- replay met dezelfde key/fingerprint geeft hetzelfde concept;
- dezelfde key met andere fingerprint faalt;
- parallelle commands maken exact één concept en context;
- bestaand concept of project blokkeert een duplicaat.

### 14.3 Negatieve side-effecttests

Voor en na conceptstart blijven aantallen en snapshots gelijk voor:

- quotation approvals, issuances en acceptances;
- commercial projects en commercial customers;
- obligations, payment expectations/evidence en reconciliations;
- Finance- en milestone-events;
- customer emailjobs;
- preview access en publication/live-site authorities.

Alleen concept, context, idempotency en concept-auditstate mogen veranderen.

### 14.4 UI- en Multi-Screentests

- exacte buttontekst en confirmationtekst;
- annuleren veroorzaakt nul requests met muterende intent;
- succes toont PRE_PROJECT en `WEBSITE OPENEN` zonder page reload;
- Website-child opent via `website-{quote_request_id}` en re-resolveert server-side;
- duplicate open focust dezelfde module-slotclaim;
- revoke, leaseverlies en authorization failure sluiten fail-closed;
- promotie-invalidation behoudt in de latere fase hetzelfde slot;
- PRE_PROJECT toont geen Finance-, release-, publicatie- of klantactie.

### 14.5 Stabiliteitstests

- deterministic DOM-contracttest voor retained same-dossier snapshot;
- cross-dossiertest die de vorige snapshot direct verwijdert;
- network- en malformed-responsefout behouden de laatste geldige view;
- MutationObserver plus 16 ms frame sampling over minimaal drie 8-secondenrefreshcycli;
- nul verborgen Project/Websiteframes, nul tijdelijke `-`/nullwaarden en nul loadingflitsen na de eerste geldige snapshot;
- dezelfde meting in master en managed child.

### 14.6 Latere promotietests

- dezelfde context-, workspace-, repository-, site-, requirements- en task-id's vóór en na promotie;
- geen duplicate rows of data copy;
- promotie geblokkeerd zonder geldige commercial lineage;
- promotie wijzigt geen betaling, release, milestone, mail of publicatierecht;
- replay en concurrency gedragen zich idempotent en fail-closed.

## 15. Releasecriteria

Een toekomstige V1-release is alleen toegestaan wanneer alle onderstaande machineleesbare criteria `JA` zijn:

```text
ACTIVE_DOSSIER_SHOWS_WEBSITE_WORK=JA
OWNER_CAN_START_CONCEPT=JA
CONFIRMATION_DIALOG=JA
PRE_PROJECT_PERSISTS=JA
WEBSITE_OPEN_VISIBLE=JA
WEBSITE_EXECUTION_OPENS=JA
NO_QUOTE_REQUIRED=JA
NO_PAYMENT_REQUIRED=JA
NO_COMMERCIAL_RELEASE_REQUIRED=JA
NO_CUSTOMER_NOTIFICATION=JA
NO_FINANCE_MUTATION=JA
NO_PUBLICATION_RIGHT=JA
DUPLICATE_CONCEPT_BLOCKED=JA
SAME_DOSSIER_REFRESH_STABLE=JA
```

Aanvullende hard stops:

- alle bestaande Website commerciële lifecycle-, Requirements-, Multi-Screen- en Dossiers-tests blijven groen;
- schema- en role-diff tonen geen verruiming van directe table privileges;
- een productiepreflight bewijst nul identityconflicten tussen bestaande project/workspacebindings;
- de release is forward-only en gebruikt het beschermde productieproces;
- intake-sync en promotie worden niet stil in V1 meegenomen;
- owner review keurt dit ontwerp en daarna een afzonderlijk implementatieplan expliciet goed.

## Besluitstatus

- Aanbevolen architectuur: aparte `website_concepts`-authority plus stabiele `website_work_contexts`-identity.
- V1-boundary: volledig bepaald.
- Open ontwerpbeslissingen binnen V1: geen.
- Latere ontwerpbeslissingen: alleen de fysieke Requirements-re-anchoring; de semantische eis van één contextgebonden board zonder kopiëren staat vast en blokkeert V1 niet.