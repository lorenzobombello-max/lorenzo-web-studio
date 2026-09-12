# LWS Dossier Continuity Regression Gate v1

## Doel

Deze releasepoort blokkeert iedere Operator-, Edge- of Pages-release zodra een bestaand dossier niet meer zichtbaar of leesbaar is. De poort is fail-closed: een ontbrekende check, credential, snapshot, responseveld of sentinel resulteert in `PRODUCTION_RELEASE_ALLOWED=NEE`.

Beschermde keten:

`Operator UI -> commercial-operator-command -> caller JWT -> list_pending_intakes -> list_applications_v2 -> get_dossier_substance -> pending projection -> active projection -> trash projection -> personal queue -> operator binding -> CORS`

De productiecontrole is uitsluitend read-only. Zij verstuurt alleen `OPTIONS` en `POST` voor `list_pending_intakes`, `list_applications_v2` en `get_dossier_substance`. De gate voert geen create-, update-, assign-, restore-, trash- of delete-actie uit.

## Incidentcontract

De gate bewaakt de regressieklasse waarbij de Edge-readpath een service client gebruikte of de caller-JWT niet doorstuurde. Daardoor konden SQL-wrappers met `auth.uid()` fail-closed reageren en dossiers uit de UI verdwijnen. Dezelfde poort bewaakt de aangrenzende regressies:

- CORS-preflight accepteert `https://lorenzowebsolutions.be` en de headers `apikey`, `authorization`, `content-type`, `x-client-info`.
- Caller reads gebruiken `clientFor(jwt)`; de service client is niet toegestaan voor deze reads.
- Pending DTO behoudt `dossier_state`, `dossier_revision` en `seen_at`.
- Active list behoudt de envelope `items`, `next_cursor` en `has_more`.
- Een transportfout wordt nooit als `0 dossiers` of een succesvolle lege lijst weergegeven.
- AAL1 blijft toegestaan voor gewone reads; kritieke mutaties blijven AAL2-plichtig.

## RPC's en autoriteit

| Edge action | PostgreSQL RPC | Autoriteit |
| --- | --- | --- |
| `list_pending_intakes` | `public.list_operator_pending_intakes_v1` | authenticated caller; `auth.uid()` moet aanwezig zijn en gelijk zijn aan `p_actor_auth_user_id`; owner/admin actief |
| `list_applications_v2` | `public.list_operator_applications_v2` | authenticated caller; `auth.uid()` moet aanwezig zijn en gelijk zijn aan `p_actor_auth_user_id`; owner/admin actief |
| `get_dossier_substance` | `public.get_operator_dossier_substance_v1` | authenticated caller; `auth.uid()` moet aanwezig zijn en gelijk zijn aan `p_actor_auth_user_id`; owner/admin actief |
| personal queue | `public.get_operator_personal_dossier_queue_v1` | caller afgeleid van `auth.uid()`; alleen actieve operator; alleen eigen assignment; trash uitgesloten |
| operator binding | `public.get_current_operator_identity_v1` | auth-userbinding, rol en status worden fail-closed gevalideerd |

De wrappers hebben `EXECUTE` voor `authenticated`, niet voor anonieme callers. Algemene list/detail-reads zijn assignment-onafhankelijk voor actieve owner/admin-operators. Alleen de personal queue is assignment-afhankelijk.

## Projecties

De synthetische tests gebruiken uitsluitend fictieve UUID's en referenties uit 2099. Nathalie en Yuna zijn nooit fixtures. Zij mogen alleen als read-only continuiteitsevidence worden genoemd en hun persoonsgegevens mogen niet in logs, snapshots of testdata terechtkomen.

Verplichte scheiding:

- Pending bevat alleen pending projectie en geen trash.
- Active bevat alleen actieve dossiers.
- Trash bevat alleen getrashte dossiers.
- Personal queue bevat alleen aan de caller toegewezen, niet-getrashte dossiers.
- List en detail blijven zichtbaar zonder assignment wanneer de caller een geldige actieve owner/admin is.
- Ongeldige, inactieve of verkeerd gebonden operators falen gesloten.

## Sentinel

De enige vaste productie-sentinel is `LWS-AAN-2026-0006`.

Iedere smoke moet bewijzen:

- `RAW_PRESENT=JA`
- `LIST_PRESENT=JA`
- `DETAIL_PRESENT=JA`
- zone is `ACTIVE`
- sentinel komt niet in `TRASHED` voor
- geen mutatie is uitgevoerd

`RAW_PRESENT` betekent in deze read-only gate dat het sentinel-ID aanwezig is in de gededupliceerde toegankelijke dossier-read-surface. Er wordt bewust geen rechtstreekse productietabelscan met verhoogde rechten uitgevoerd.

## Lokale poort

```powershell
node --test scripts/dossier-continuity-regression-gate.test.mjs
node scripts/dossier-continuity-regression-gate.mjs local
npx playwright test scripts/dossier-continuity-live-preview.test.mjs
```

De live preview controleert desktop en mobiel voor pending, active, trash, load failure, succesvolle empty en succesvolle populated. Een failure toont de aparte laadfout; alleen een succesvolle lege response toont `Geen dossiers gevonden.`

De bestaande forward-only releasecontrole roept de lokale fase verplicht aan. Gebruik voor een losse controle dezelfde runner:

```powershell
./scripts/invoke-dossier-continuity-release-gate.ps1 -Phase Local
```

## Productie-smoke

Gebruik een kortlevende geldige owner/admin caller-JWT en de publieke anon key uitsluitend via procesomgeving. Schrijf deze waarden nooit naar repository, snapshot of log.

```powershell
$env:LWS_SUPABASE_ANON_KEY='<anon-key>'
$env:LWS_OPERATOR_JWT='<kortlevende-caller-jwt>'
node scripts/dossier-continuity-regression-gate.mjs smoke
```

De smoke faalt wanneer credentials ontbreken, CORS niet exact slaagt, een read geen 200 retourneert, de envelope afwijkt, detail ontbreekt of de sentinel niet actief is.

## Pre/post count guard

Maak direct vóór en direct na een voorgenomen release een snapshot met dezelfde caller en zonder tussentijdse klantmutatie:

```powershell
node scripts/dossier-continuity-regression-gate.mjs snapshot --output .gate/dossiers-before.json
# voer pas na een volledig groene before-gate de release uit
node scripts/dossier-continuity-regression-gate.mjs snapshot --output .gate/dossiers-after.json
node scripts/dossier-continuity-regression-gate.mjs compare --before .gate/dossiers-before.json --after .gate/dossiers-after.json
```

Snapshots bevatten exact vier niet-negatieve gehele getallen en geen persoonsgegevens:

- `TOTAL_RAW`: gededupliceerde unieke dossier-ID's uit pending, active, archived en trash reads
- `TOTAL_PENDING`: pending-items
- `TOTAL_ACTIVE`: active-items
- `TOTAL_TRASHED`: trash-items

Ieder verschil blokkeert de release. Een legitieme tussentijdse wijziging vereist nieuwe before/after-snapshots; de mismatch wordt nooit handmatig genegeerd.

## Verplichte productie-integratie

Pages-releases lopen uitsluitend via `.github/workflows/deploy-pages.yml`. Edge-releases van de beschermde dossier-readpath lopen uitsluitend via de handmatig gestarte workflow `.github/workflows/deploy-commercial-operator-command.yml` vanaf `main`; deze deployt alleen `commercial-operator-command`.

Beide workflows voeren exact dezelfde keten uit:

1. `PreDeploy`: gerichte tests, statische/lokale gate en een authenticated read-only before-snapshot.
2. Deploy: alleen na een groene predeploy-job.
3. `PostDeploy`: authenticated production-smoke, after-snapshot en exacte countvergelijking.
4. `release-approved`: alleen na een groene postdeploy-job; uitsluitend deze job mag `PRODUCTION_RELEASE_ALLOWED=JA` publiceren.

De before- en after-snapshots worden één dag als workflow-artifact bewaard en bevatten alleen de vier totalen. De benodigde GitHub-configuratie is:

- protected environment `production-continuity`, gekoppeld aan beide continuityjobs
- environment variable `LWS_SUPABASE_PUBLISHABLE_KEY`
- environment secrets `LWS_RELEASE_SMOKE_EMAIL` en `LWS_RELEASE_SMOKE_PASSWORD` voor één dedicated actieve admin release-smoke identity
- voor Edge daarnaast repository variable `LWS_SUPABASE_PROJECT_REF` en secret `SUPABASE_ACCESS_TOKEN`

De CI-wrapper meldt deze dedicated identity bij iedere pre- en postdeployjob opnieuw aan via Supabase Auth password login. Alleen de kortlevende `access_token` wordt process-scoped als caller-JWT aan de officiële gate doorgegeven; de authresponse wordt niet geserialiseerd, een refresh-token wordt niet gebruikt en alle credentialvariabelen worden in `finally` verwijderd. De identity wordt buiten code aangemaakt, bevestigd en via haar Auth UUID als `ACTIVE admin` aan `public.commercial_operators` gekoppeld. De workflow maakt of wijzigt nooit accounts of operatorrollen.

Ontbrekende credentials, een mislukte login, een ongeldige of bijna verlopen access-token, een ontbrekend artifact, een overgeslagen check, een workflow vanaf een andere branch, een RPC/CORS/detail/sentinel-fout of countdrift stopt de job met non-zero en `PRODUCTION_RELEASE_ALLOWED=NEE`. `continue-on-error`, warning-only afhandeling, een silent skip en handmatige count-override zijn niet toegestaan. Een mislukte postdeploy-gate levert geen releasegoedkeuring op; herstel gebeurt alleen met een nieuwe volledig gecontroleerde forward-only release.

## Verplichte beslissing

De twaalf checks zijn `CORS`, `JWT_FORWARDING`, `PENDING_RPC`, `ACTIVE_RPC`, `DETAIL_RPC`, `PENDING_PROJECTION`, `ACTIVE_PROJECTION`, `TRASH_PROJECTION`, `RESPONSE_CONTRACT`, `UI_CONTINUITY`, `SENTINEL` en `PRE_POST_COUNT_GUARD`.

Alleen wanneer iedere check `PASS` is, mag de uitvoer `PRODUCTION_RELEASE_ALLOWED=JA` zijn. Iedere andere toestand, inclusief een niet-uitgevoerde productie-smoke of ontbrekende pre/postvergelijking, betekent `PRODUCTION_RELEASE_ALLOWED=NEE`.

## Bekende baseline-validatie

Op de basiscommit bestaat een brede UI-testverwachting voor de oudere assetquery `operator-dashboard.css?v=20260905-profile-welcome-r3&pulse=20260905-r1&dossier-zones=20260905-r1`, terwijl de dashboard-HTML al `v=20260910-requirements-summary-v1` gebruikt. Dit staat los van deze test-only gate. De gerichte dossiergate, UI-continuiteitstest en live preview zijn de release-autoriteit voor deze wijziging.

De bestaande gecombineerde caller-JWT-test kan door gedeelde testsuite-state 4/5 rapporteren op CORS, terwijl dezelfde `withCommercialOperatorCors`-wrapper geïsoleerd voor de productie-origin status 204 en de vereiste headers retourneert. De gate controleert CORS geïsoleerd en de productie-smoke blijft de beslissende externe controle.

Bij de read-only introductiesmoke op 12 september 2026 was `LWS-AAN-2026-0006` aanwezig in de ACTIVE-list en afwezig uit trash. De daadwerkelijk gedeployde `dossierSubstanceRequest` bouwde `{ action: "get_dossier_substance", quote_request_id }`, maar Edge retourneerde `400 INVALID_REQUEST`. Daarom waren `RAW_PRESENT=JA`, `LIST_PRESENT=JA`, `DETAIL_PRESENT=NEE`, `MUTATIONS=0` en `PRODUCTION_RELEASE_ALLOWED=NEE`. Dit is precies een blokkerende continuiteitsregressie; zij mag niet als gatefout of succesvolle smoke worden geregistreerd.
