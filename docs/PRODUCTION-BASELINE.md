# Production Baseline

> **Current authority (2026-08-14):** This document preserves the verified 2026-08-09 baseline and later historical additions. For the current production commit, final website status, Git/worktree preservation state and safe resume procedure, use [`FINAL-PRODUCTION-CHECKPOINT-20260814.md`](FINAL-PRODUCTION-CHECKPOINT-20260814.md) as the primary source.

## Identificatie

- Project: Lorenzo Web Solutions / `lorenzo-web-studio`
- Statusdatum: 2026-08-09
- Laatste geverifieerde productiecommit: `21d65e6dad1d64bdbc9cdd43706585d579a5da14`
- Branch: `main`
- Linked Supabase-project: `xcsptvntvrizwhskaphr`
- Supabase-regio: `eu-west-1`
- PostgreSQL major: 17

Dit document legt de gecontroleerde productiebaseline vast. Code, migrations en runtimeconfiguratie blijven de technische bron van waarheid. Neem nooit secrets, raw tokens, private capabilities, service-role credentials of private environmentwaarden op in repositorydocumentatie.

## Git En Publicatie

- `.github/workflows/deploy-pages.yml` publiceert pushes naar `main` via GitHub Pages.
- `scripts/prepare-pages-dist.ps1` bouwt een allowlisted `dist/`-artifact uit de publieke HTML, `pages/`, `assets/`, metadata en optionele `CNAME`.
- `scripts/verify-pages-dist.ps1` controleert vereiste paden, verboden bestandstypen, lokale links en de verwachte Functions-base-URL in de homepage en contactpagina.
- Alleen het gegenereerde artifact wordt gepubliceerd; Supabase-bronnen, repositorymetadata, Markdown en lokale configuratie horen niet in het Pages-artifact.
- Verwachte Git-baseline: branch `main`, HEAD gelijk aan `origin/main`, divergentie `0 0` en geen tracked wijzigingen. Lokale brandinginput en Supabase CLI-metadata kunnen bewust untracked zijn.
- GitHub Pages deployment van productiecommit `21d65e6dad1d64bdbc9cdd43706585d579a5da14`: succesvol.

## Projectstructuur

- `index.html`: publieke homepage.
- `pages/`: publieke content-, contact-, review- en intakepagina's.
- `pages/demos/`: tien zelfstandige sectordemo's.
- `assets/`: gedeelde en demo-specifieke CSS, JavaScript, iconen en afbeeldingen.
- `scripts/`: voorbereiding en verificatie van het Pages-artifact.
- `supabase/functions/`: drie quote/intake-Edge Functions, de privacyfunctie en gedeelde security-, validatie- en e-mailmodules.
- `supabase/migrations/`: twaalf chronologische PostgreSQL-migrations.

## Database

### `quote_requests`

Slaat gevalideerde offerteaanvragen en hun reviewstatus op.

- Statusenum: `pending`, `approved`, `rejected`.
- Het klanttype onderscheidt `Particulier` en `Onderneming`.
- Zakelijke aanvragen bevatten conditioneel bedrijfsnaam, ondernemingsnummer, btw-nummer, facturatieadres en facturatie-e-mail.
- De officiële btw-validatiestatus is `valid`, `invalid`, `unavailable` of `not_checked`.
- Voor Belgische ondernemingsnummers wordt de lokale status `format_valid_not_externally_verified` vastgelegd na geslaagde formaat- en checkdigitcontrole.
- De idempotency key is uniek.
- Approval capability-hashes zijn uniek wanneer aanwezig.
- Een pending request vereist een capability-hash en expiratie.
- Reviewactie en reviewtijd worden bij de statusovergang vastgelegd.
- Publieke rollen hebben geen directe tabeltoegang; backendbewerkingen lopen via service-role-bevoegde code en afgeschermde databasefuncties.

### `quote_request_email_jobs`

Beheert leveringswerk voor `admin_notification`, `customer_confirmation`, `intake_invitation` en `intake_submitted_notification`.

- Foreign key naar `quote_requests(id)` met `ON DELETE CASCADE`.
- `UNIQUE (quote_request_id, kind)` garandeert maximaal een job van elke soort per request.
- Leveringsstatussen: `pending`, `processing`, `sent`, `retry_wait`, `failed`.
- Claim-, completion- en retryfuncties beheren pogingen en locking.
- Tijdelijk encrypted invitation-materiaal is alleen toegestaan voor invitation-jobs en wordt na succesvolle levering gewist.
- Directe toegang is beperkt tot `service_role`.

### `quote_request_intakes`

Slaat de websitebriefing en lifecyclemetadata op.

- Statusenum: `invited`, `in_progress`, `submitted`, `reviewed`.
- Foreign key naar `quote_requests(id)` met `ON DELETE CASCADE`.
- `UNIQUE (quote_request_id)` garandeert een intake per request.
- De access capability-hash is uniek en niet leeg.
- Een definitief ingediende intake kan afzonderlijke, verlopende admin-accessmetadata bevatten voor de beveiligde read-only briefingweergave.
- Constraints bewaken expiratie, status/timestamps, confirmation, conditionele webshop- en bookingdata, URLs en toegestane categoriewaarden.
- Directe toegang is beperkt tot `service_role`; capability-gebaseerde RPC's vormen de applicatiegrens.

## Migrations

Alle twaalf migrations zijn in productie toegepast. De twee meest recente business-validatiemigrations zijn afzonderlijk na deployment geverifieerd.

1. `20260802130000_create_quote_requests.sql`
   - Maakt requeststatus, `quote_requests`, basisvalidatie, RLS en de pending capability-index.
2. `20260802141000_grant_quote_requests_service_role.sql`
   - Kent de benodigde tabelrechten uitsluitend aan `service_role` toe.
3. `20260808120000_harden_quote_request_delivery.sql`
   - Voegt request-idempotency, e-mailjobs, jobuniqueness, reviewtransities, claim/completion en retrymechanismen toe.
4. `20260808133000_restrict_quote_table_privileges.sql`
   - Verwijdert overbodige privileges en scherpt tabelisolatie verder aan.
5. `20260808150000_create_quote_request_intakes.sql`
   - Maakt intake-enum en -tabel met foreign keys, uniqueness en lifecycle-/dataconstraints.
6. `20260808160000_create_quote_request_intake_api.sql`
   - Voegt capability-gebaseerde create- en inspect-RPC's voor intakes toe.
7. `20260808170000_add_quote_request_intake_mutations.sql`
   - Voegt server-side `save_draft` en definitieve `submit` toe, inclusief validatie, row locking en state guards.
8. `20260808180000_add_quote_request_intake_detail_inspection.sql`
   - Breidt beveiligde intake-inspectie uit met briefingdetails voor restore/read-only-weergave.
9. `20260808190000_create_quote_request_intake_invitations.sql`
   - Voegt invitation-jobtype, encrypted retrymateriaal, clear-on-sent en invitation create/retrieve-RPC's toe.
10. `20260808200000_create_submitted_intake_admin_flow.sql`
   - Voegt atomische submitted-notificationjobs, admin-accessmetadata en service-role-only inspectie van definitief ingediende briefings toe.
11. `20260809180000_add_quote_request_business_customer_fields.sql`
   - Voegt klanttype en conditionele bedrijfs-, btw- en facturatievelden toe aan offerteaanvragen en de downstream review-/intakeflow.
12. `20260809210000_add_official_business_validation_status.sql`
   - Voegt de lokale ondernemingsnummervalidatiestatus en officiële VIES-validatiestatus toe.

## Edge Functions

De quote/intake-runtimebaseline op 2026-08-09 is in productie `ACTIVE`:

### `submit-quote-request` v17

- Doel: een publieke offerteaanvraag valideren, idempotent opslaan en de adminnotificatie afleveren.
- Accepteert alleen de bedoelde HTTP-methode, content type, bodygrootte en gevalideerde velden.
- Gebruikt een UUID-idempotency key plus payloadfingerprint om herhaalde requests veilig af te handelen.
- Genereert een korte-lived approval capability; alleen de hash wordt persistent opgeslagen.
- Past honeypot- en rate-limitcontroles toe.
- Normaliseert en valideert Belgische ondernemingsnummers lokaal en voert de officiële VIES-controle uitsluitend server-side uit.
- Een tijdelijk niet-beschikbare VIES-dienst blokkeert een verder geldige aanvraag niet.
- Transitie: nieuwe request naar `pending`; bij creatie ontstaat maximaal een `admin_notification`-job.

### `review-quote-request` v14

- Doel: capability-gebaseerde inspectie en review van requests, bevestigingslevering en intake-uitnodigingen.
- Actions: `approved`, `rejected`, `retry_confirmation`, `send_intake_invitation`, `retry_intake_invitation`.
- Valideert capabilityvorm, hash, expiratie, huidige requeststatus en action/state-combinaties.
- Approval maakt idempotent de customer-confirmation-job; rejection legt de reviewtransitie vast.
- Een invitation-action maakt een intake en invitation-job of rapporteert de bestaande toestand.
- Response-serialisatie bevat requestdetails, maar geen capability-hash, raw capability of encrypted payload.
- Zakelijke velden en validatiestatussen worden conditioneel aan review en vervolgstappen doorgegeven.

### `intake-quote-request` v4

- Doel: capability-gebaseerde intakecreatie, inspectie, draftsave en definitieve submit.
- Actions: `create`, `inspect`, `save_draft`, `submit`, `inspect_submitted_intake_admin`.
- Valideert methode, content type, bodygrootte, capabilityvorm en briefingdata.
- `save_draft` brengt `invited` naar `in_progress` en bewaart gedeeltelijke data server-side.
- `submit` vereist alle verplichte velden en confirmation en brengt een bewerkbare intake naar `submitted`.
- Definitieve submit maakt atomisch maximaal een `intake_submitted_notification`-job en levert de beveiligde adminlink via de bestaande jobdelivery.
- `inspect_submitted_intake_admin` valideert een afzonderlijke admincapability en levert uitsluitend de definitief ingediende briefing voor read-only weergave.
- Een reeds submitted intake levert `already_submitted`; andere niet-bewerkbare statussen worden geweigerd.
- Zakelijke gegevens en validatiestatussen zijn beschikbaar voor admin/intake en de briefingweergave.

De afzonderlijke privacyflow is intact en blijft buiten de business-customerwijzigingen.

## Juridische Pagina's

- Privacy, cookies en algemene voorwaarden staan live.
- De gepubliceerde juridische pagina's bevatten geen open placeholders.

## Zakelijke Klantflow En Validatie

**Business customer + VIES flow: COMPLETED - PRODUCTION VERIFIED op 9 augustus 2026.**

- De offerteflow ondersteunt `Particulier` en `Onderneming` met conditionele rendering en validatie.
- Voor een onderneming lopen bedrijfsnaam, ondernemingsnummer, btw-nummer, facturatieadres en facturatie-e-mail mee door de beveiligde backendflow.
- Een Belgisch ondernemingsnummer wordt genormaliseerd en lokaal gecontroleerd met de Belgische modulo-97/checkdigitregel. Een geslaagde lokale controle krijgt `format_valid_not_externally_verified`.
- Er vindt geen KBO-scraping plaats. Automatische externe KBO-verificatie is niet geïntegreerd.
- Btw-nummers worden uitsluitend server-side gecontroleerd via de officiële VIES-dienst van de Europese Commissie.
- Mogelijke VIES-statussen zijn `valid`, `invalid`, `unavailable` en `not_checked`; `unavailable` blokkeert de aanvraag niet.
- De ruwe VIES-response wordt niet opgeslagen.

## Briefing, PDF En Offerte

- Zakelijke gegevens en validatiestatussen worden conditioneel opgenomen in review, admin/intake en briefing/PDF.
- Een particuliere aanvraag krijgt geen lege zakelijke regels in de briefing of PDF.
- Er bestaat nog geen volledig automatische offertegenerator.
- De zakelijke gegevens zijn wel beschikbaar voor handmatige verwerking en latere automatische overname.

## Interne Bedrijfsdocumenten

De interne documentenset bevat:

- `Interne Prijsgids 2026`;
- `Prijsgids 2026 Klantversie`;
- de centrale `LWS_DOCUMENTEN_INDEX_EN_KLANTWORKFLOW.md` voor documentkeuze en klantworkflow.

De vastgelegde basisprijzen zijn:

- Starter vanaf €1.800;
- Professional vanaf €3.200;
- Maatwerk op aanvraag.

Deze bedrijfsdocumenten zijn geen tracked Markdown-bestanden in deze repository; de namen worden hier alleen als actuele interne documentstatus geregistreerd.

## Emailflow

1. `admin_notification` wordt bij een nieuwe quote request aangemaakt en naar de beheerder verzonden.
2. `customer_confirmation` wordt na approval maximaal eenmaal per request aangemaakt en naar de klant verzonden.
3. `intake_invitation` wordt voor een approved request maximaal eenmaal aangemaakt en bevat de persoonlijke intake-link.
4. `intake_submitted_notification` wordt bij definitieve submit maximaal eenmaal aangemaakt en bevat voor de beheerder een beveiligde link naar de volledige read-only briefing.

De deliverymodule claimt jobs atomisch en verwerkt providerresultaten. Retrybare HTTP-statussen zijn `408`, `425`, `429` en `5xx`; netwerkfouten zijn retrybaar. Databasefuncties beheren pogingsteller, `retry_wait`, volgende poging en terminale failure. De exacte productiegedragingen onder providerstoring zijn niet volledig end-to-end gevalideerd.

## Capability En Security

- Approval- en intakecapabilities zijn cryptografisch gegenereerde of afgeleide URL-safe waarden. Raw waarden worden alleen gebruikt waar de link of request ze nodig heeft.
- Persistente verificatie gebruikt HMAC-SHA256; de securitymodule gebruikt gescheiden contexten voor verschillende hashdoelen.
- Raw approval- en intakecapabilities worden niet in de request- of intaketabellen opgeslagen.
- Tijdelijk invitation-retrymateriaal is AES-GCM-encrypted, gebonden aan de intakehash en wordt na succesvolle verzending gewist.
- Approvalcapabilities verlopen volgens de geconfigureerde korte TTL; intakecapabilities verlopen exact 14 dagen na creatie.
- Review- en intakefrontends lezen de capability eenmaal uit de URL, verwijderen de queryparameter direct met `history.replaceState`, bewaren de waarde alleen in een private JavaScript-closure en gebruiken geen `localStorage` of `sessionStorage`.
- Capabilitygevoelige intake-responses gebruiken `Cache-Control: no-store` en `Referrer-Policy: no-referrer`.
- RLS, ingetrokken publieke privileges en service-role-only RPC-rechten voorkomen directe publieke databasetoegang.

## Intake Lifecycle

```text
invited -> in_progress -> submitted -> reviewed
```

- `invited`: intake bestaat en de persoonlijke invitation kan worden geleverd.
- `in_progress`: minstens een server-side draftsave is uitgevoerd; restore haalt de opgeslagen antwoorden via `inspect` terug.
- `submitted`: definitieve briefing is gevalideerd, confirmation is vastgelegd en submitmetadata is gezet.
- `reviewed`: schema en frontend modelleren deze read-only eindstatus. In de actuele repository is geen normale applicatieworkflow aangetroffen die een intake naar `reviewed` zet.

Na `submitted` of `reviewed`:

- antwoorden blijven zichtbaar;
- alle formuliervelden zijn disabled/read-only;
- `Concept opslaan` en `Intake verzenden` zijn afwezig;
- een normale tweede submit is niet beschikbaar;
- heropenen via de persoonlijke link toont opnieuw de read-only briefing;
- de tijdelijke melding `Intake wordt verzonden...` wordt bij het ingaan van read-only status gewist.

## Idempotency En Duplicatebescherming

- Quote submit gebruikt een unieke idempotency key en payloadfingerprint; hergebruik met afwijkende data wordt niet als dezelfde aanvraag geaccepteerd.
- `UNIQUE (quote_request_id)` op intakes dwingt een intake per quote request af.
- `UNIQUE (quote_request_id, kind)` op e-mailjobs dwingt een job per soort per request af.
- Reviewtransities, intake-updates en invitationcreatie vergrendelen de relevante request- of intakerow om concurrerende statewijzigingen te serialiseren.
- Definitieve intake-submit retourneert `already_submitted` wanneer de status al `submitted` is.

## Productievalidatie

### Bewezen In Productie

**Websitebriefing-flow: PASS — end-to-end productievalidatie 8 augustus 2026.**

Phase6B is de referentie-E2E-test voor de volledige keten:

```text
aanvraag
-> goedkeuring
-> intake-uitnodiging
-> klantbriefing
-> definitieve submit
-> databaseopslag
-> admin-notificatie
-> beveiligde adminweergave volledige briefing
```

De volgende keten is gecontroleerd met een beheerste synthetische request en UUID-gebonden metadata-inspectie:

- quote submit;
- admin notification;
- approval;
- customer confirmation;
- intake invitation;
- een intake per request;
- draft save;
- draft restore via de normale maillink;
- definitieve submit;
- exact een verzonden `intake_submitted_notification`-job;
- beveiligde adminmailactie en volledige read-only adminweergave;
- submitted read-only reopen met zichtbare antwoorden;
- geen normale save- of tweede submitmogelijkheid na submit;
- post-submit loading-messagepolish live.

**Business customer + VIES flow: PASS - productievalidatie 9 augustus 2026.**

- zakelijke klantvelden live van aanvraag tot review, intake en briefing/PDF;
- lokale Belgische ondernemingsnummer-checkdigitcontrole actief;
- officiële VIES-validatie server-side actief;
- migrations `20260809180000_add_quote_request_business_customer_fields.sql` en `20260809210000_add_official_business_validation_status.sql` production-applied;
- `submit-quote-request` v17, `review-quote-request` v14 en `intake-quote-request` v4 `ACTIVE`;
- tijdelijk synthetisch productietestrecord verwijderd via databasebeheerrechten;
- afsluitende verificatiequery retourneerde nul resterende synthetische records;
- geen databaseprivileges of policies aangepast en geen repositorybestanden gewijzigd tijdens cleanup.

### Geimplementeerd Maar Niet Volledig Productiegetest

- reject;
- confirmation retry;
- invitation retry;
- providerfouten, backoff en terminale failure;
- rate limiting onder belasting;
- de gemodelleerde `reviewed` lifecycle.

### Gepland, Niet Geimplementeerd

- nieuwe branding toepassen;
- Instagram-QR toepassen;
- professioneel homepage-redesign.

## Branding Baseline

De nieuwe, nog niet geimplementeerde input staat onder `assets/images/branding/`:

| Bestand | Type | Afmetingen |
|---|---|---:|
| `logo/ChatGPT Image 7 aug 2026, 21_01_13.png` | PNG | 1254 x 1254 |
| `logo/lorenzo-web-solution-logo-transparent.png` | PNG | 1254 x 1254 |
| `social/Instagram_LorenzoWebSolution.jpg` | JPEG | 1194 x 1099 |

Deze bestanden waren tijdens de audit untracked en werden niet hernoemd, verplaatst, geconverteerd of geimplementeerd.

## Bekende Beperkingen En Open Punten

- Een volledig automatische offertegenerator bestaat nog niet.
- Automatische externe KBO-verificatie bestaat nog niet; alleen lokale normalisatie en modulo-97/checkdigitvalidatie zijn actief.
- Interne bedrijfsdocumenten en klantworkflows kunnen later verder worden uitgebreid.
- `package.json` bevat geen geautomatiseerde test-, lint- of buildscripts.
- De Pages-verificatie controleert de Functions-base-URL expliciet in homepage en contactpagina, niet in review- en intakepagina.
- Reject, retrypaden, providerfailure, rate limiting onder belasting en de `reviewed` lifecycle zijn minder volledig in productie gevalideerd dan de hoofdflow.
- Runtimefunctieversies zijn deploymentmetadata; controleer ze opnieuw voor een toekomstige recovery of release.
- De bekende untracked brandingassets, `pages/redesign-preview/` en Supabase CLI-metadata blijven bewust buiten deze documentatietaak.
