# GIT-001C Astro preview build - lokaal verificatiecheckpoint (§18 vervolg)

Datum: 2026-09-23
Status: **OPEN**
Scope: uitsluitend lokale worktree en lokale Supabase; geen productie- of hostingactivatie.

## C1 - Operatorbesturing

Lokaal bewezen:

- De gemonteerde Website Execution-child verstuurt één build-start bij twee synchrone klikken.
- De controller pollt status tot een terminale toestand en vraagt daarna een previewsessie aan.
- De UI opent uitsluitend de servergeretourneerde handoff-URL.
- De commandhandler accepteert alleen de gesloten start/status/session-acties en vereist caller-JWT plus AAL2.

Bewijs: `node scripts/operator-website-execution.test.mjs` - 76/76 geslaagd.

## C2 - Artifactautoriteit en ontvangst

Lokaal bewezen:

- GitHub Actions OIDC wordt cryptografisch als RS256 tegen JWKS gecontroleerd. De claims worden exact gebonden aan de platform-workflowrepository, repository-id, ref, workflow-ref, run-id en audience; legacy en immutable GitHub-subjectvormen zijn getest. Klantrepository en klantcommit komen uitsluitend uit de leaseautoriteit en worden niet langer met platformclaims verward.
- Acquire maakt één servergeautoriseerde build-ID. Authority-resolve en database-triggers weigeren iedere andere build-ID bij receipt-token- en uploadsession-inserts.
- Alleen SHA-256-hashes van het 256-bit receipt-token en het afzonderlijke 256-bit uploadsession-token worden opgeslagen.
- Het eenmalige receipt-token opent atomair precies één lease/build/repository/commit/workflow-gebonden uploadsession met een vast verwacht manifest.
- Ieder bestand komt als afzonderlijke raw request body binnen; de handler stopt en annuleert bij 5 MiB + 1, ook bij een onjuiste `Content-Length`. Pad, MIME, grootte en SHA-256 worden vóór een atomische `EXPECTED -> UPLOADING`-claim gecontroleerd.
- Een duplicate/concurrent fileclaim heeft precies één winnaar. Replay, verkeerde binding en expiry worden geweigerd.
- Workflow-finalize is een aparte `service_role`-RPC en vereist dat ieder verwacht bestand `RECEIVED` is. De bestaande operator-`finalize_v2` blijft uitsluitend `authenticated` en vereist ongewijzigd caller-AAL2.
- Incomplete en late finalize aborteren fail-closed; de database levert de cleanup-paden en de private Storage-objecten worden werkelijk verwijderd.

Bewijs:

- Gerichte receipt/OIDC/handler-runs - 14/14 geslaagd, inclusief immutable OIDC-subject, bounded streaming, completion-cleanup en cleanup-herhaling na een mislukte Storage-delete.
- `node scripts/website-preview-artifact-receipt-concurrency.integration.cjs` - één winnaar; replay, verkeerde repository en expiry geweigerd.
- `node scripts/website-preview-upload-session.integration.cjs` - echte lokale RPC/private Storage: claimrace, receipt-replay, verkeerde binding, incomplete finalize, expiry, cleanup en succesvolle finalize geslaagd.
- Migraties `20260923100000_add_website_project_preview_upload_session_v1.sql` en `20260923110000_authorize_website_project_preview_build_id_v1.sql` lokaal toegepast.
- `deno test -A --no-check supabase/functions/_shared/website-project-preview-e2e-real-build.integration.test.ts` - 1/1 geslaagd in 1m45s. De test gebruikt authenticated acquire, de productie-runtimefactory en echte HTTP-handler, de workflow-upload-CLI, echte lokale PostgreSQL-RPC's en private Storage. Verkeerde buildbinding, verlopen OIDC, receipt-replay en incomplete finalize worden aan de HTTP-grens geweigerd; abort verwijdert het reeds ontvangen object.

De GitHub-providergrens in deze lokale proef is bewust gesimuleerd: een lokale RSA-provider geeft tokens met officiële GitHub issuer-, audience-, platformrepository-, workflow-, ref- en runclaims uit en levert gecontroleerde JWKS. De productie-OIDC-verifier en volledige applicatieketen zijn echt; GitHub-hosted tokenuitgifte en live JWKS-ophaling zijn dit nog niet.

**C2 lokale integratie via applicatie-endpoints bewezen.**

## C3 - Build, database, Storage en serving

Lokaal bewezen met exact repository `lorenzo-web-solutions/lws-web-a88b1e8792714ad199ccb385b7982a8b` op commit `1f19bf01c61c6da79fa4c7374333a91b70f9bf48`:

- De test clonet alleen die remote, checkt detached exact die SHA uit, verifieert `origin` en `HEAD`, en verwijdert `.git` vóór de buildmount.
- De klantbron bevat een lockfile; de container gebruikt `npm ci` en Astro 7.3.2.
- De buildcontainer draait op een intern Docker-netwerk; directe outbound HTTPS naar `example.com` faalt in dezelfde run.
- Alleen de tinyproxy met npm-registryallowlist heeft externe netwerktoegang.
- Authenticated acquire levert de servergebonden lease en build-ID; receipt issuance, uploadsession, afzonderlijke bestandsoverdracht en workflow-finalize lopen door de echte artifact-handler en productieadapters.
- De bestaande workflow-upload-CLI bouwt het manifest, haalt OIDC op, opent de ontvangst/sessionketen en uploadt alle geaccepteerde bestanden.
- `favicon.svg` en `social-card.svg` worden als waarschuwing afgewezen; ieder geaccepteerd Storage-object is bytegelijk aan de buildoutput en heeft de verwachte SHA-256.
- Workflow-finalize persisteert uitsluitend na volledige ontvangst. Buildstatus, primary artifact, totaalbytes en het volledige manifest zijn daarna via echte lokale PostgreSQL bewezen.

Bewijs: `deno test -A --no-check supabase/functions/_shared/website-project-preview-e2e-real-build.integration.test.ts` - 1/1 geslaagd in 1m45s.

## C3 - Zichtbare lokale operator- en klantpreview

Lokaal zichtbaar en bruikbaar bewezen met de bestaande operatorpagina en controllers:

- Operator: `http://127.0.0.1:61588/operator/window/?module=dossiers`.
- Klantpreview: `https://preview.local/#principles` binnen het door de launcher gestarte Chromiumprofiel; `preview.local` is bewust een geïsoleerde Playwright DNS/TLS-route en geen publieke host.
- De zichtbare flow doorloopt `Preview bouwen / vernieuwen` -> `Preview wordt gebouwd` -> `Preview gereed` -> `Preview openen`.
- De geopende preview toont de echte opgeslagen `index.html`, de berekende body-CSS is toegepast en de zichtbare navigatielink `Principles` brengt de pagina naar `#principles`.
- De klantbron bevat geen zichtbaar `<img>`-element; C3 verzint daarom geen klantbeeld en presenteert uitsluitend de werkelijk gebouwde bron.
- De launcher leest de bestaande 0006-binding, buildmetadata en private Storage-objecten read-only. Er zijn geen klantrecords, tweede repository of productieobjecten aangemaakt.
- Voor iedere zichtbare run wordt eerst bewezen dat een request zonder previewsessie door de echte hostinggateway met HTTP 401 wordt geweigerd en dat een verlopen operator-AAL2-sessie fail-closed `C3_OPERATOR_SESSION_EXPIRED` oplevert.
- De zwarte strook in het gemaximaliseerde demo-venster kwam niet uit de gedeelde operator-CSS, maar uit de vaste Playwrightviewport van 1440 bij 960 binnen een groter native Chromiumwindow. De launcher gebruikt nu voor de hele context `--start-maximized` en `viewport: null`; operatorvensters en previewtabs benutten daardoor de native browserruimte, terwijl lange inhoud via de ongewijzigde documentscroll bereikbaar blijft. Een gemaximaliseerde Windows-opname van 2575 bij 1407 px toont het operatorvlak zonder letterboxing en met de klantpreview in de naastliggende tab.

Gericht bewijs: `node --test scripts/git001c-local-c3-demo.test.mjs` - 6/6 geslaagd. De headed launch voltooide daarnaast alle browserasserties en meldde build `7bca8377-f4d0-4403-a8ab-f7f6cc525159` als `PASS_WITH_WARNINGS` met zes private Storage-artifacts.

Reëel in deze proef: operatorpagina en controllers, status-/resultaatweergave, private Storage-bytes, eenmalige hostinggateway-handoff/session, CSS en navigatie. Lokaal gesimuleerd: operator session/AAL2 backendresponses, builddispatch/polltiming en de `preview.local` DNS/TLS-route.

## Productiegang stap 1 - hostingvoorstel

**Aanbevolen route:** Cloudflare Pages Functions op Workers Paid met custom subdomain `preview.lorenzowebsolutions.be`, vóór een purpose-authenticated Supabase Edge Function origin. Een catch-all Pages Function ontvangt alle normale websitepaden op een afzonderlijke origin; de Supabase origin houdt service-role, sessie-RPC en private Storage afgeschermd. Er wordt geen Supabase custom domain aangeschaft.

1. **Passend bij de bestaande code.** `LWS_PREVIEW_HOST_URL` accepteert al een zelfstandige HTTPS-origin en geeft `/handoff?token=...` terug. De database heeft reeds actor/build-gebonden hash-only previewsessies, 30-minutenexpiry, service-role resolution en cleanup. De lokale gateway bewijst `/`, `/about/`, assets, directory-indexen en sessie-isolatie. Cloudflare Pages Functions ondersteunen een catch-allroute en `_routes.json` met `/*`; path/query/cookie kunnen daarom onveranderd naar de Supabase origin.
2. **Waarom Supabase custom domain afvalt.** Supabase documenteert dat custom domains niet bedoeld zijn voor frontendhosting, dat Edge Functions geen HTML ondersteunen en dat functies bereikbaar blijven onder `/functions/v1/<function>`. De add-on toont dus wel een branded API-host en kan HTML-content-typegedrag veranderen, maar levert geen root-router voor `/`, `/about/` en `/_astro/...`, geen aparte function-only origin en verandert bovendien Supabase Auth-callbacks projectbreed.
3. **Kosten.** Bestaande OVH-, GitHub- en Supabasebedragen zijn niet uit read-only accountdata af te leiden. Het Supabase-project is `ACTIVE_HEALTHY`, maar de custom-domain API meldt alleen dat de organisatie geen entitlement heeft; exact plan en spend cap blijven onbekend. Extra vast: Cloudflare Workers Paid minimaal `$5 USD per account per maand`, exclusief belasting; Pages Functions vallen onder die Workersquota. Inbegrepen: 10 miljoen Function/Workerrequests en 30 miljoen CPU-ms per maand; daarboven `$0.30 USD per miljoen requests` en `$0.02 USD per miljoen CPU-ms`. Cloudflare rekent geen Worker-egress. Supabase Function/Storage-egress blijft gebruik binnen het bestaande, onbekende plan; officiële planoverschrijdingen zijn niet per klant en worden vóór activatie tegen billing/spend cap gecontroleerd. De Supabase custom-domainadd-on van `$10/domain/maand/project` is niet nodig.
4. **DNS/TLS en impact.** Huidige nameservers blijven `dns106.ovh.net` en `ns106.ovh.net`; apex, `www`, MX en TXT blijven ongewijzigd. `preview` heeft nu geen A/CNAME. Na associatie van het custom subdomain in Cloudflare Pages komt bij OVH precies één record: CNAME `preview` naar de nog toe te wijzen `<project>.pages.dev`; Cloudflare beheert het certificaat. Geen nameserver-, apex-, `www`-, MX-, SPF-, DKIM- of DMARC-wijziging. Website en e-mail hebben daarom geen routingimpact. Supabase Auth blijft op `xcsptvntvrizwhskaphr.supabase.co`; OAuth/SAML-callbacks wijzigen niet. CAA-compatibiliteit moet vóór TLS-activatie read-only worden gecontroleerd.
5. **Ontbrekende code en volgorde.** Eerst een additive RPC voor eenmalige handoffconsumptie en rotatie naar een afzonderlijke viewer-sessionhash; daarna de Supabase originhandler met purpose-secret, pathnormalisatie, bestaande session resolver en private Storage streaming; vervolgens een catch-all Cloudflare Pages Function plus `_routes.json` voor `/*`, content types en no-store; daarna gerichte lokale integratie. Pas na afzonderlijke goedkeuring: Cloudflare-account/Pages-project/Workers Paid, origin deploy, Pages direct upload, custom-domainassociatie, één OVH CNAME, TLS, `LWS_PREVIEW_HOST_URL`, negatieve authprobes en één gecontroleerde 0006-dispatch.
6. **Publicatiestatus.** Gereed: C1/C2, exacte 0006-build, private Storage-artifacts, operatorflow, sessionschema/resolver/cleanup, lokale veilige hostingsemantiek en secretvrije configuratievoorbeelden. Niet gereed: handoffrotatiemigratie, Supabase originhandler, Pages Function, origin-authintegratie, Cloudflare-account/Pages-project/Workers-plan, toegewezen `pages.dev`-hostname, productieconfiguratie, deployment en live negatieve probes.
7. **Beslissing voor Lorenzo.** Goedkeuring gevraagd voor de vaste Cloudflare Workers Paid-basis van **`$5 USD per maand per account` plus alleen officieel gemeten overage**, en later precies één OVH CNAME voor `preview.lorenzowebsolutions.be`. Dit akkoord activeert nog niets; deployment, CNAME en 0006-dispatch blijven afzonderlijke uitvoeringsgates.

Officiële bronnen gecontroleerd op 2026-09-23: [Supabase custom domains](https://supabase.com/docs/guides/platform/custom-domains), [Supabase Edge routing](https://supabase.com/docs/guides/functions/http-methods), [Supabase pricing](https://supabase.com/pricing), [Cloudflare Pages custom domains](https://developers.cloudflare.com/pages/configuration/custom-domains/), [Pages Functions routing](https://developers.cloudflare.com/pages/functions/routing/), [Pages Functions pricing](https://developers.cloudflare.com/pages/functions/pricing/) en [Cloudflare Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/).

## Productiegang stap 2 - releaseklare lokale koppeling

Lokaal geïmplementeerd, zonder externe mutatie:

- `website-project-preview-source-token` accepteert alleen POST plus GitHub Actions OIDC en de drie authoritysleutels `leaseId`, `buildId` en `workflowRunId`. De server resolveert repository, repository-ID, commit, run en build; daarna wordt precies één GitHub App-installatietoken met `repository_ids: [resolved_id]` en `contents:read` uitgegeven. App-JWT, private key en providerdetails verlaten de server niet.
- De workflow haalt zijn eigen fetch-OIDC op, gebruikt het installatietoken alleen voor de exacte klantcheckout, verifieert `HEAD`, verwijdert `.git` en draagt geen credential over aan build of upload. Build heeft `permissions: {}`; upload vraagt afzonderlijk OIDC aan voor artifactontvangst. De workflow blijft uitsluitend `workflow_dispatch`.
- De Cloudflare Pages Function is catch-all via `_routes.json` met `/*`, stuurt alleen path/query/cookie plus een purpose-token naar de vaste Supabase-origin, zet no-store, verwijdert interne headers en redirect de standaard `pages.dev`-host naar `preview.lorenzowebsolutions.be`.
- De Supabase-origin weigert requests zonder purpose-token vóór RPC/Storage, consumeert een handoff atomair naar een nieuwe 256-bit viewer-sessionhash en zet een host-only `HttpOnly; Secure; SameSite=Lax; Path=/`-cookie. Assetselectie loopt uitsluitend via session -> build -> manifest -> private Storage; build-ID en Storageprefix zijn niet client-selecteerbaar.
- Migratie `20260923120000_add_website_project_preview_handoff_rotation_v1.sql` is lokaal toegepast. Een SQL-probe bewees eenmalige consumptie, replayweigering en behoud van dezelfde buildbinding en is teruggerold. Alleen de lokale migratieledger is gerepareerd voor de reeds aanwezige, inhoudelijk geverifieerde migratie `20260923110000`; productie is niet geraakt.
- De echte lokale integratie doorloopt Pages -> Supabase origin -> handoff-RPC -> session-RPC -> private Storage, bewijst bij twee concurrente handoffs exact één 302-winnaar en één 403-replay, en verwijdert zijn tijdelijke sessie en object. Bewijs: 1/1 geslaagd. Aanvullend: hostinghandlers 8/8, source-tokenbroker 6/6 en workflowcontract 3/3; beide hostingruntimes en de source-tokenruntime typechecken.

Exacte files van deze productie-koppelingssnede:

- `.github/workflows/build-website-project-preview.yml`
- `.gitignore`
- `scripts/website-project-preview-workflow.test.mjs`
- `cloudflare/website-project-preview-host/.dev.vars.example`
- `cloudflare/website-project-preview-host/functions/[[path]].ts`
- `cloudflare/website-project-preview-host/functions/preview-host.test.ts`
- `cloudflare/website-project-preview-host/public/_routes.json`
- `cloudflare/website-project-preview-host/wrangler.example.jsonc`
- `cloudflare/website-project-preview-host/wrangler.jsonc`
- `supabase/config.toml`
- `supabase/functions/.env.example`
- `supabase/functions/_shared/website-project-preview-local-hosting-gateway.ts`
- `supabase/functions/website-project-preview-source-token/handler.ts`
- `supabase/functions/website-project-preview-source-token/handler.test.ts`
- `supabase/functions/website-project-preview-source-token/index.ts`
- `supabase/functions/website-project-preview-source-token/service.ts`
- `supabase/functions/website-project-preview-host.env.example`
- `supabase/functions/website-project-preview-host/handler.ts`
- `supabase/functions/website-project-preview-host/handler.test.ts`
- `supabase/functions/website-project-preview-host/hosting.integration.test.ts`
- `supabase/functions/website-project-preview-host/index.ts`
- `supabase/migrations/20260923120000_add_website_project_preview_handoff_rotation_v1.sql`
- `docs/superpowers/checkpoints/2026-09-23-git001c-astro-preview-build-local-verification.md`
- `docs/superpowers/plans/2026-09-23-git001c-live-coupling.md`
- `.superpowers/sdd/009-git001c-astro-preview-build-plan/progress.md`

Configuratie-inventaris zonder waarden:

- Supabase server-only: `SUPABASE_URL`, service-keybinding, GitHub App ID/installatie-ID/private key, `LWS_PREVIEW_OIDC_AUDIENCE`, `LWS_PREVIEW_WORKFLOW_REPOSITORY`, `LWS_PREVIEW_WORKFLOW_REPOSITORY_ID`, `LWS_PREVIEW_WORKFLOW_REF`, `LWS_PREVIEW_WORKFLOW_REF_NAME`, `LWS_PREVIEW_HOST_URL` en `LWS_PREVIEW_ORIGIN_TOKEN`.
- GitHub Actions vars: `LWS_PREVIEW_SOURCE_TOKEN_ENDPOINT`, `LWS_PREVIEW_ARTIFACT_ENDPOINT` en `LWS_PREVIEW_OIDC_AUDIENCE`.
- Cloudflare: vaste `LWS_PREVIEW_ORIGIN_URL` en encrypted secret `LWS_PREVIEW_ORIGIN_TOKEN`; nooit een Supabase service role.

Officiële Cloudflare-voorwaarden opnieuw gecontroleerd vóór activatie op 2026-09-23: de goedgekeurde basis is ongewijzigd en er is geen materieel verschil. Workers Paid kost minimaal `$5 USD/account/maand`, bevat maandelijks 10 miljoen requests en 30 miljoen CPU-ms, en rekent daarna `$0.30/miljoen requests` en `$0.02/miljoen CPU-ms`. Pages Functions worden als Workers gefactureerd; Worker-egress/bandwidth heeft geen aanvullende prijs. Er is niets gekocht of geactiveerd.

Exacte volgende productieactie na afzonderlijke toestemming: maak eerst een recoverycheckpoint en pas de additieve migraties in volgorde toe; deploy daarna artifact-, source-token- en preview-originfuncties terwijl de workflow ongedispatched blijft. Configureer vervolgens het overeenkomende encrypted origin-token, deploy Pages zonder DNS en voer negatieve authprobes uit. Pas daarna: custom subdomain associëren, precies één OVH CNAME toevoegen, TLS/path/cookie/no-cache controleren, `LWS_PREVIEW_HOST_URL` instellen en uiteindelijk één gecontroleerde 0006-dispatch autoriseren.

Rollback: schakel dispatch/source-token uit, revoke previewsessies en ruim incomplete uploadobjecten via de bestaande abort/cleanupautoriteit op; verwijder bij hostingfalen uitsluitend de Pages custom-domainassociatie en OVH-CNAME. Apex, `www`, MX/TXT, Supabase Auth, klantrepository, commit en afgeronde builddata blijven onaangeraakt.

## Open grenzen

- GitHub-hosted live OIDC-uitgifte en een live JWKS-uitwisseling zijn niet uitgevoerd; de cryptografische proef gebruikt een lokaal ondertekende token en gecontroleerde JWKS-provider.
- `website-project-preview-artifact`, `website-project-preview-source-token` en `website-project-preview-host` zijn geïmplementeerd maar niet gedeployed.
- De exacte Git-bron is echt gelezen; repository-id/authoritybinding gebruikt een unieke lokale fixture en de OIDC-provider is lokaal gesimuleerd. Dit is geen live GitHub Actions-providerbewijs.
- De uploadjob is executable bedraad aan raw-file/session/finalize en de fetchjob aan de GitHub App OIDC-installatietokenbroker; beide wachten op gecontroleerde deployment en live providerbewijs.
- De hostingroute en lokale productiecode zijn gereed maar niet geactiveerd: Cloudflare-account/Pages-project/Workers Paid, toegewezen `pages.dev`-hostname, functiondeployments, één OVH CNAME, CAA/TLS-probe, retention scheduler en productie-observability blijven open.
- `.github/workflows/build-website-project-preview.yml` blijft `workflow_dispatch` en is niet live uitgevoerd.
- Brede typechecked run zonder `--no-check`: 1366/1369 geslaagd. De acht door GIT-001C veroorzaakte fixturetypefouten zijn gecorrigeerd; de enige drie Windows-fouten zijn symlinkfixturecreaties met OS-fout 1314. De volledige manifestfile draaide in Linux 10/10 groen, inclusief alle drie symlinkgevallen.
- De workflow is statisch bedraad met verplichte servergeautoriseerde `build_id`-input en genereert geen eigen UUID meer. De fetch-tokenbroker is lokaal gebouwd; de dispatchgrens en live GitHub OIDC/tokenexchange blijven onuitgevoerd.

## Herstelpunt en read-only productiepreflight 2026-09-23

### Lokale herstelidentiteit

- Worktree: `C:\Users\info\Project-Worktrees\lorenzo-web-studio-git001c-astro-preview-build-20260922`.
- Branch: `git001c-astro-preview-build-20260922`.
- Basis vóór het herstelcommit: `ededdd6043c3ad749a1faf9a3993221c24fc3971`.
- Lokaal recoverycommit: `35fbb65730966430d16432f8dea8ded8f655f474` (`checkpoint GIT-001C preview production preflight`), tree `fda203f289304e81417165164e6cb7b715e6626f`; niet gepusht.
- Het herstelcommit omvat de volledige lokale GIT-001C-slice: operatorbesturing, async buildautoriteit, artifactontvangst en uploadsession, exacte-sourcebuild, workflow, source-tokenbroker, Supabase preview-origin, Cloudflare front door, zeven additieve migraties, tests, fixtures en bewijsdocumenten. `supabase/.temp`, echte `.env`/`.dev.vars`, credentials en providerwaarden zijn uitgesloten.
- De eerder gebruikte lokale C3-fixture-ID `8541939033` was niet de immutable ID van de benoemde repository. GitHub rapporteert voor `lorenzo-web-solutions/lws-web-a88b1e8792714ad199ccb385b7982a8b` exact ID `1378797607` en node `R_kgDOUi7IJw`; commit `1f19bf01c61c6da79fa4c7374333a91b70f9bf48` bestaat en is GitHub-verified. De C3- en brokerfixtures zijn daarop gecorrigeerd en beide gerichte suites slagen 6/6.

Exacte `git show --name-status --no-renames 35fbb65730966430d16432f8dea8ded8f655f474`-set:

```text
A .github/workflows/build-website-project-preview.yml
M .gitignore
A .superpowers/sdd/009-git001c-astro-preview-build-plan/progress.md
M assets/js/operator-website-execution-child.mjs
A assets/js/operator-website-preview-build.mjs
A assets/js/operator-website-preview-build.test.mjs
A cloudflare/website-project-preview-host/.dev.vars.example
A cloudflare/website-project-preview-host/functions/[[path]].ts
A cloudflare/website-project-preview-host/functions/preview-host.test.ts
A cloudflare/website-project-preview-host/public/_routes.json
A cloudflare/website-project-preview-host/wrangler.example.jsonc
A cloudflare/website-project-preview-host/wrangler.jsonc
M deno.lock
A docs/superpowers/checkpoints/2026-09-23-git001c-astro-preview-build-local-verification.md
A docs/superpowers/plans/2026-09-23-git001c-live-coupling.md
A scripts/fixtures/website-preview-astro/astro.config.mjs
A scripts/fixtures/website-preview-astro/package-lock.json
A scripts/fixtures/website-preview-astro/package.json
A scripts/fixtures/website-preview-astro/public/favicon.svg
A scripts/fixtures/website-preview-astro/public/hero.png
A scripts/fixtures/website-preview-astro/public/hero.png.base64
A scripts/fixtures/website-preview-astro/src/pages/index.astro
A scripts/fixtures/website-preview-astro/src/pages/over.astro
A scripts/fixtures/website-preview-astro/src/styles/global.css
A scripts/git001c-local-c3-demo.mjs
A scripts/git001c-local-c3-demo.test.mjs
M scripts/operator-website-execution.test.mjs
A scripts/preview-build-proxy/filter.allow
A scripts/preview-build-proxy/tinyproxy.conf
A scripts/website-preview-artifact-receipt-concurrency.integration.cjs
A scripts/website-preview-upload-session.integration.cjs
A scripts/website-project-preview-upload.ts
A scripts/website-project-preview-workflow.test.mjs
M supabase/config.toml
M supabase/functions/.env.example
A supabase/functions/_shared/website-project-preview-artifact-manifest.test.ts
A supabase/functions/_shared/website-project-preview-artifact-manifest.ts
A supabase/functions/_shared/website-project-preview-artifact-receipt.test.ts
A supabase/functions/_shared/website-project-preview-artifact-receipt.ts
A supabase/functions/_shared/website-project-preview-async-build.test.ts
A supabase/functions/_shared/website-project-preview-async-build.ts
M supabase/functions/_shared/website-project-preview-builder.ts
A supabase/functions/_shared/website-project-preview-e2e-real-build.integration.test.ts
A supabase/functions/_shared/website-project-preview-hosting-gateway.ts
A supabase/functions/_shared/website-project-preview-local-hosting-gateway.test.ts
A supabase/functions/_shared/website-project-preview-local-hosting-gateway.ts
A supabase/functions/_shared/website-project-preview-oidc-broker.test.ts
A supabase/functions/_shared/website-project-preview-oidc-broker.ts
A supabase/functions/_shared/website-project-preview-sanitizer.ts
A supabase/functions/_shared/website-project-preview-single-use-token.test.ts
A supabase/functions/_shared/website-project-preview-single-use-token.ts
M supabase/functions/commercial-operator-command/caller-jwt-read-path.test.ts
M supabase/functions/commercial-operator-command/dossier-substance-request-contract.test.ts
M supabase/functions/commercial-operator-command/handler.test.ts
M supabase/functions/commercial-operator-command/handler.ts
M supabase/functions/commercial-operator-command/index.ts
A supabase/functions/website-project-preview-artifact/handler.test.ts
A supabase/functions/website-project-preview-artifact/handler.ts
A supabase/functions/website-project-preview-artifact/index.ts
A supabase/functions/website-project-preview-host.env.example
A supabase/functions/website-project-preview-host/handler.test.ts
A supabase/functions/website-project-preview-host/handler.ts
A supabase/functions/website-project-preview-host/hosting.integration.test.ts
A supabase/functions/website-project-preview-host/index.ts
A supabase/functions/website-project-preview-source-token/handler.test.ts
A supabase/functions/website-project-preview-source-token/handler.ts
A supabase/functions/website-project-preview-source-token/index.ts
A supabase/functions/website-project-preview-source-token/service.ts
A supabase/migrations/20260922180000_extend_website_project_preview_build_async_contract_v1.sql
A supabase/migrations/20260923060000_add_website_project_preview_build_finalize_and_session_v1.sql
A supabase/migrations/20260923070000_add_website_project_preview_artifact_receipt_v1.sql
A supabase/migrations/20260923080000_add_website_project_preview_artifact_authority_v1.sql
A supabase/migrations/20260923100000_add_website_project_preview_upload_session_v1.sql
A supabase/migrations/20260923110000_authorize_website_project_preview_build_id_v1.sql
A supabase/migrations/20260923120000_add_website_project_preview_handoff_rotation_v1.sql
```

### Provideraccessmatrix

| Provider | Read-only resultaat | Productieblokker |
| --- | --- | --- |
| Supabase `xcsptvntvrizwhskaphr` | Toegang beschikbaar; project `ACTIVE_HEALTHY`, PostgreSQL 17.6. Remote ledger eindigt op `20260920231950`. De backup van 2026-09-23 05:25 UTC is `COMPLETED`; PITR is uit. Private bucket `website-project-previews` bestaat. Er zijn 19 actieve Edge Functions en geen `website-project-preview-*`-functie. Een officiële read-only Management API-query bevestigt exact één production workspacebinding: repository ID `1378797607`, node `R_kgDOUi7IJw`, commit `1f19bf01c61c6da79fa4c7374333a91b70f9bf48`, `REPOSITORY_READY`, binding revision 1. De eigenaar bevestigt dashboard-side: **Pro Plan actief**, spend cap ingeschakeld, current costs `$25.00` en projected costs `$34.33`; er zijn geen billinginstellingen gewijzigd. | De bestaande App-secretnamen zijn aanwezig; `LWS_PREVIEW_OIDC_AUDIENCE`, `LWS_PREVIEW_WORKFLOW_REPOSITORY`, `LWS_PREVIEW_WORKFLOW_REPOSITORY_ID`, `LWS_PREVIEW_WORKFLOW_REF`, `LWS_PREVIEW_WORKFLOW_REF_NAME`, `LWS_PREVIEW_HOST_URL` en `LWS_PREVIEW_ORIGIN_TOKEN` ontbreken werkelijk en moeten pas in de goedgekeurde configuratiestap worden gezet. |
| GitHub | Platformrepository `lorenzobombello-max/lorenzo-web-studio`, immutable ID `1320223175`, node `R_kgDOTrEBxw`, default branch `main`, klantrepositorynaam/ID/node en exact verified klantcommit zijn via REST bevestigd. De eigenaar heeft installatie `161436785` read-only in het dashboard gecontroleerd zonder op te slaan: **Only select repositories** is actief en zowel `lorenzo-web-solutions/lws-website-starter` als klantrepository `lorenzo-web-solutions/lws-web-a88b1e8792714ad199ccb385b7982a8b` (ID `1378797607`) zijn geselecteerd. De installatie toont metadata read en administration/code read-write. | De klantrepositoryselectie is bevestigd correct. De brede Provisioner-App-installatierechten worden niet verlaagd: zij kunnen repositorycreatie en bestaande functies bedienen. Voor de previewbroker is afzonderlijk lokaal bevestigd dat een tokenrequest uitsluitend de server-resolved klantrepository-ID bevat en `contents:read` vraagt. De drie vereiste repositoryvariables `LWS_PREVIEW_SOURCE_TOKEN_ENDPOINT`, `LWS_PREVIEW_ARTIFACT_ENDPOINT` en `LWS_PREVIEW_OIDC_AUDIENCE` ontbreken; de previewworkflow staat nog niet op `main` (`404`). Geen dispatch. |
| Cloudflare | De verkeerde Wrangler-sessie is afgemeld. Een nieuwe officiële Wrangler 4.137.0 localhost-callbackautorisatie is geslaagd en versleuteld opgeslagen via Windows Credential Manager. `wrangler whoami` en `/accounts` bevestigen uitsluitend `Bombello.lorenzo1972@gmail.com's Account`, account-ID `acbc1b86d8c3f0ce809dc4600783a48b`. Read-only inventaris bevestigt één bestaande Worker, `lorenzobombello-api-proxy`, accountsubdomain `bombello-lorenzo1972`, nul routes en `usage_model=standard`. Het lege Pages-project `lws-website-project-preview-host` is via de officiële project-API aangemaakt met production branch `main`; project-ID `56ba0651-2499-4b40-b3f7-ad2b690dfa3c` en toegewezen hostname `lws-website-project-preview-host.pages.dev`. Providerverificatie toont `source=null`, `canonical_deployment=null`, `latest_deployment=null` en exact `0` deployments. De eigenaar bevestigt dashboard-side dat Workers Paid voor dit account actief is. | De subscriptions-endpoint is met deze OAuth-token niet leesbaar (`403/10000 Authentication error`), zodat Paid niet aanvullend via API is bevestigd en niets opnieuw wordt aangekocht. De API retourneert geen expliciete `workers_dev`-status voor de bestaande Worker; met nul routes wordt geen actieve Worker-hostname geconcludeerd. Het Pages-project bevat nog geen deployment, origin-secret, source-koppeling of custom domain. `preview.lorenzowebsolutions.be` is niet gekoppeld en DNS is niet gewijzigd. |
| OVH/DNS | De eigenaar bevestigt dashboard-side dat de DNS-zone `lorenzowebsolutions.be` kan worden bekeken en bewerkt; uitvoerings- en rollbackbevoegdheid zijn daarmee bevestigd. Publieke DNS toont authoritative nameservers `dns106.ovh.net` en `ns106.ovh.net`, `preview.lorenzowebsolutions.be` zonder CNAME/NXDOMAIN en mail ongewijzigd op `mx1.mail.ovh.net`, `mx2.mail.ovh.net`, `mx3.mail.ovh.net`. | CAA/TLS moet bij Pages-domainassociatie opnieuw live worden geprobed. Geen DNS-wijziging uitgevoerd. |

Supabase secretnamen zijn alleen als namen geïnventariseerd; waarden zijn niet gelezen of vastgelegd. De vereiste nieuwe origin/source/workflowbindings zijn niet als volledige productiecontractset bewezen. De lokale poolerbinding bevatte geen databasewachtwoord; er is geen credential gevraagd, afgeleid of opgeslagen.

### GitHub App-installatie versus previewtoken

De rechten van installatie `161436785` vormen het maximale App-bereik en zijn breder dan het previewgebruik. Ze zijn geen bewijs dat ieder uitgegeven installation token al die rechten of beide geselecteerde repositories krijgt. Het lokale previewbrokerpad begrenst het specifieke token afzonderlijk als volgt:

- de HTTP-endpoint accepteert alleen `leaseId`, `buildId` en `workflowRunId`; caller-supplied repository- of permissionvelden worden afgewezen;
- de server resolveert de klantrepository uit de production lease/workspaceauthority en maakt exact één `repositoryIds`-entry;
- operatie `WEBSITE_PROJECT_FILES_READ` wordt door de gedeelde broker vertaald naar `metadata:read` plus `contents:read`;
- de GitHub tokenexchange verstuurt `repository_ids: [1378797607]` en exact `permissions: { metadata: "read", contents: "read" }`;
- de runtimeadapter geeft de werkelijke `permissions` uit GitHubs response door aan de bestaande generieke leasevalidator; ontbrekende metadata, ongeldige waarden, `contents:write` en extra `administration:write` worden fail-closed geweigerd met `GITHUB_TOKEN_RESPONSE_INVALID` voordat een tokenlease wordt teruggegeven.

Daarmee is het lokale uitgiftecontract smaller dan de Provisioner-installatie: uitsluitend klantrepository ID `1378797607`, Metadata read en Contents read. Gericht TDD-bewijs: de geldige response wordt aanvaard en ontbrekende, ongeldige of ruimere responsepermissions leveren geen tokenlease op (`3/3` geslaagd via de echte adapter en bestaande broker-validator). Live tokenuitgifte blijft geblokkeerd totdat de functie en vereiste productiebindings afzonderlijk zijn goedgekeurd en gedeployed; bij de eerste gecontroleerde uitgifte blijft provider-side verificatie van de effectieve scope vereist.

### Exacte productionvolgorde na afzonderlijke autorisatie

1. Behoud de bevestigde 0006 production workspacebinding als repository ID `1378797607`, node `R_kgDOUi7IJw`, naam `lorenzo-web-solutions/lws-web-a88b1e8792714ad199ccb385b7982a8b` en commit `1f19bf01c61c6da79fa4c7374333a91b70f9bf48`. Wijzig de bredere Provisioner-App-installatie `161436785` niet binnen GIT-001C. Bevestig bij een latere gecontroleerde previewrun dat het specifieke uitgegeven token uitsluitend repository ID `1378797607` en `contents:read` heeft, plus de verwachte platform Actions repository/ref/workflow-ref. Bij iedere afwijking: stop; `NO_SECOND_CREATE` blijft HARD.
2. Maak/controleer een verse productionbackup en verantwoord dat PITR uit staat. Pas daarna exact in deze volgorde toe: `20260922180000`, `20260923060000`, `20260923070000`, `20260923080000`, `20260923100000`, `20260923110000`, `20260923120000`. Markeer niets handmatig als toegepast; met name `20260923110000` niet.
3. Verifieer na iedere migratie definities, triggers en grants. Deploy vervolgens `website-project-preview-artifact`, `website-project-preview-source-token` en `website-project-preview-host`; workflow blijft ongedispatched. Zet uitsluitend reviewed server-side secrets/vars en bewijs dat direct-originverkeer zonder purpose-token vóór database/Storage faalt.
4. Gebruik het reeds lege Cloudflare Pages-project `lws-website-project-preview-host` met toegewezen hostname `lws-website-project-preview-host.pages.dev`. Deploy pas na afzonderlijke autorisatie de reviewed Pages Functions zonder DNS, configureer het overeenkomende encrypted `LWS_PREVIEW_ORIGIN_TOKEN` en voer negatieve auth/cache/originprobes uit.
5. Associeer eerst `preview.lorenzowebsolutions.be` in Pages. Voeg daarna bij OVH precies één CNAME `preview` naar die werkelijk toegewezen hostname toe. Verifieer CAA, managed TLS, redirect van de standaardhost, normale paths, host-only cookie, content types en `private, no-store`; wijzig geen nameservers, apex, `www`, MX/TXT of Supabase Auth.
6. Zet `LWS_PREVIEW_HOST_URL=https://preview.lorenzowebsolutions.be`, publiceer het reviewed workflowcommit met `workflow_dispatch` als enige trigger en voer pas na een aparte controlled-dispatchgoedkeuring één 0006-run uit.

Rollbackvolgorde: blokkeer dispatch en source-tokenuitgifte; revoke previewsessies; abort incomplete uploads en herhaal private-objectcleanup; laat afgeronde builddata staan. Verwijder bij hostingfalen uitsluitend de Pages custom-domainassociatie en de ene OVH-CNAME. Revert additieve migraties alleen dependency-safe en na expliciete databasebeslissing. Klantrepository, commit, apex/`www`, mail, Supabase Auth en bestaande klantdata worden nooit verwijderd of gemuteerd.

### Blockerclassificatie na toegangsherstelpogingen

**Bevestigd correct:** production workspacebinding en exacte klantrepository/commit; GitHub App-installatie `161436785` gebruikt **Only select repositories** en bevat de klantrepository naast de starterrepository; het lokale previewbrokercontract begrenst het specifieke token tot alleen klantrepository ID `1378797607` en `contents:read`; Supabase projectgezondheid, databaseversie, dagelijkse backup, Pro Plan, ingeschakelde spend cap en bestaande private bucket; opgeslagen Wrangler-aanmelding voor bedoeld account `acbc1b86d8c3f0ce809dc4600783a48b`; bestaande Worker `lorenzobombello-api-proxy`; leeg Pages-project `lws-website-project-preview-host`, hostname `lws-website-project-preview-host.pages.dev` en nul deployments; Workers Paid op basis van eigenaar-dashboardbewijs voor dit account; bestaande GitHub App-secretnamen; OVH DNS-zonebekijk-/bewerkbevoegdheid; publieke OVH-nameservers en ongewijzigde mailroute.

**Werkelijk ontbrekend:** zeven nieuwe Supabase previewbindings; drie GitHub Actions previewvariables; de previewworkflow op `main`; alle zeven GIT-001C-productiemigraties; de drie previewfunctiedeployments; de Pages Function-deployment en encrypted origin-secret; custom-domainassociatie, managed TLS en OVH-CNAME.

**Niet bevestigd met de beschikbare toegang:** de effectieve live scope van een daadwerkelijk door de nog niet gedeployde previewbroker uitgegeven token; Cloudflare subscriptionstatus via API; een actieve `workers.dev`-hostname voor de bestaande Worker. Accountidentiteit, Worker- en Pages-inventaris zijn voor het juiste account bevestigd. De toekomstige CNAME-target is provider-side vastgesteld als `lws-website-project-preview-host.pages.dev`, maar associatie en DNS blijven ongeactiveerd. Er zijn geen wachtwoorden, cookies of tokens gevraagd of vastgelegd.

Preflightbesluit: de eerdere GitHub App-selectieblocker is **opgeheven**, Wrangler is aan het juiste Cloudflare-account gebonden en het lege Pages-project is ingericht. Productie-uitvoering blijft **NO-GO** wegens de ontbrekende bindings, migraties en deployments; deze blijven afzonderlijk gated. Deze NO-GO wijzigt het bestaande hostingakkoord niet en autoriseert geen aankoop, deployment of DNS-wijziging.

Eerstvolgende concrete vervolgstap vereist afzonderlijke productieautorisatie: leg een verse recoverycheck vast en pas uitsluitend de zeven additieve migraties tot en met `20260923120000` toe met het guarded script. Configureer bindings en deploy functies pas in de daaropvolgende gate. Wijzig de Provisioner-App-installatie niet. Workflowpublicatie, functiondeployments, Pages, DNS en dispatch blijven afzonderlijke gates.

Het afgesproken previewadres blijft exact `https://preview.lorenzowebsolutions.be` — met de `s` in `solutions`. De latere CNAME-target is `lws-website-project-preview-host.pages.dev`; er is nog geen custom-domainassociatie of DNS-wijziging uitgevoerd.

## Releasevoorbereiding vanaf b4fc16e 2026-09-23

Zonder providerwijziging opnieuw bevestigd:

- Supabase heeft exact de zeven lokale migraties `20260922180000`, `20260923060000`, `20260923070000`, `20260923080000`, `20260923100000`, `20260923110000` en `20260923120000` pending; `supabase db push --linked --dry-run` noemt exact die zeven bestanden. Er is geen `website-project-preview-*`-functie gedeployed. De nieuwste providerbackup is ID `1759100262`, status `COMPLETED`, voltooid op `2026-09-23T05:25:23.466Z`; PITR is `OFF`.
- Alleen secretnamen zijn gelezen. Bestaand: `LWS_GITHUB_APP_ID`, `LWS_GITHUB_APP_INSTALLATION_ID`, `LWS_GITHUB_APP_PRIVATE_KEY`, `SUPABASE_URL` en de service-keybinding. Ontbrekend: de zeven `LWS_PREVIEW_*`-bindings uit het releasecontract.
- GitHub REST bevestigt platformrepository ID `1320223175`, `main`, afwezige previewworkflow en de drie ontbrekende Actions-variabelen. Klantrepository ID `1378797607` en verified commit `1f19bf01c61c6da79fa4c7374333a91b70f9bf48` zijn ongewijzigd.
- Cloudflare GET bevestigt project-ID `56ba0651-2499-4b40-b3f7-ad2b690dfa3c`, hostname `lws-website-project-preview-host.pages.dev`, branch `main`, geen source, `0` deployments, geen custom domains en uitsluitend Worker `lorenzobombello-api-proxy`.
- Publieke DNS-over-HTTPS geeft `NXDOMAIN` voor `preview.lorenzowebsolutions.be`, zonder CNAME; apex-CAA is afwezig. Er is niets aan OVH gewijzigd.

Lokale releasebestanden:

- value-free contract: `.release/git001c-preview-release.json`;
- guarded standaard read-only preflight en expliciete migratiegate: `scripts/invoke-git001c-preview-release.ps1`;
- volledig uitvoeringsrunbook: `docs/superpowers/plans/2026-09-23-git001c-production-execution.md`;
- contracttest: `scripts/git001c-release-preparation.test.mjs`.

Verse gerichte evidence: release-/workflowcontract `4/4`; Pages plus Supabase-origin beveiligingsgrenzen `8/8`; editorcontrole zonder fouten. De complete read-only scriptpreflight verifieert live de backup/PITR-status, exacte pending migraties, functies, alleen secret-aanwezigheid, Pages-identiteit/deployments/domains, Worker en NXDOMAIN vóór de dry-run. `pages.dev` retourneert lokaal bewezen een `308` naar exact `preview.lorenzowebsolutions.be` vóór origincontact en lekt geen purpose-token. Direct originverkeer zonder purpose-token is `403 PREVIEW_ORIGIN_FORBIDDEN`; de custom host zonder geldige sessie is `401 PREVIEW_SESSION_REQUIRED`. De officiële Wrangler 4.137.0 help bevestigt `pages deploy <directory> --project-name ... --branch ...` en `pages secret put <key> --project-name ...`; het afgewezen project-create-commando komt niet in het runbook voor.

Frisse release/securityreview leidde tot strengere Cloudflare-responsevalidatie en exact-één-tokenextractie in de preflight. Twee gemelde runtimeblockers zijn tegen de controlerende paden weerlegd: de async operatoractie acquiret alleen lease/build; de workflowuploadclient post `action: finalize` naar de artifact-handler, die `finalize_website_project_preview_upload_session_v1` aanroept. De afzonderlijke legacy synchrone builder blijft bewust op `finalize_website_project_preview_build_v1`. De echte lokale HTTP-integratie bewijst de async `issue -> begin -> upload -> finalize -> status`-keten. Provider- of DNS-probefalen blokkeert de gate; het wordt nooit als afwezigheid geïnterpreteerd.

Het zware exacte-source-, concurrency-, uploadsession-, Linux-manifest- en operatorbewijs is hergebruikt omdat de controlerende runtimecode niet wijzigde. Alleen releaseconfiguratie, runbook en de concrete resterende toegangspaden zijn opnieuw getest. Er is geen deployment, migratie, secret-/varwrite, DNS-wijziging, aankoop, push of merge uitgevoerd.

## Productierecoverycheck 2026-09-24

- Uitvoeringsidentiteit vóór de check: branch `git001c-astro-preview-build-20260922`, reviewed HEAD `284fc48b30660bf4aeea40e113292af2ecd1581f`, schone worktree en operator `info`.
- Supabase Management API bevestigde opnieuw project `xcsptvntvrizwhskaphr` (`Lorenzo Web Solutions`), regio `eu-west-1`, status `ACTIVE_HEALTHY`, PostgreSQL `17.6.1.155`.
- De guarded read-only preflight slaagde en noemde nog steeds exact zeven pending migraties: `20260922180000`, `20260923060000`, `20260923070000`, `20260923080000`, `20260923100000`, `20260923110000` en `20260923120000`. Er waren geen previewfuncties, Pages-deployments of Pages-domains; preview-DNS bleef `NXDOMAIN` en Worker `lorenzobombello-api-proxy` bleef behouden.
- Nieuwste recoverypoint bleef fysieke backup `1759100262`, status `COMPLETED`, voltooid op `2026-09-23T05:25:23.466Z`. Op `2026-09-24T03:45:24.5140940Z` was deze `22.334` uur oud en dus formeel binnen de scriptgrens van 24 uur, maar PITR bleef `OFF` en er was geen nieuwere backup.
- Een read-only timestampaggregatie over `public` en `lws_internal` vond geen zichtbare rijen na het backupmoment. De uitgebreidere check over `auth` en `storage` vond wel productie-mutaties na het recoverypoint: `auth.sessions` 1 rij, `auth.users` 1 rij en `auth.refresh_tokens` 3 rijen; laatste timestamps respectievelijk `2026-09-23T06:30:55.119478Z`, `2026-09-23T06:30:55.081115Z` en `2026-09-23T06:30:55.070847Z`.
- Zonder PITR zou een restore naar backup `1759100262` deze latere auth-toestand kunnen verliezen. Bovendien kan timestampaggregatie deletes of mutaties zonder bijgewerkte timestamp niet uitsluiten. Daarom is dit recoverypoint niet geschikt verklaard voor de eerste productiemutatie.
- **HARD STOP vóór mutatie:** `ApplyMigrations` is niet aangeroepen; alle zeven migraties blijven pending. Er is geen functiondeploy, secret-/varwrite, Pages-wijziging, custom domain, DNS-wijziging, workflowdispatch, push of merge uitgevoerd. `NO_SECOND_CREATE` en de bestaande Worker/klantrepository blijven intact.

Hervat Task 5 alleen na een nieuw voltooid recoverypoint of expliciet goedgekeurde gelijkwaardige herstelmogelijkheid die de post-backupwijzigingen dekt. Herhaal daarna de volledige read-only preflight en wijzigingen-sinds-backupbeoordeling; gebruik nooit automatisch backup `1759100262` omdat deze in een historisch commando staat.

### Recoveryafhandeling en migratie-uitvoering 2026-09-24

- Een eenmalige nieuwe providercheck vond geen nieuwere voltooide backup. Backup `1759100262` bleef de fysieke baseline met PITR `OFF`.
- De zeven migraties zijn object voor object beoordeeld. Ze maken vijf previewtabellen en nieuwe RPC's/indexen/triggers, vervangen previewspecifieke functies en twee constraints, wijzigen de bestaande bucketrij `website-project-previews`, vullen `authorized_build_id` op acht bestaande previewleases en voegen `handoff_consumed_at` toe. Alle acht leases waren al released, er waren nul previewbuilds, nul actieve leases en nul objecten/nul bytes in de previewbucket.
- Aanvullende supported recoverydekking is lokaal en git-ignored vastgelegd onder `.local-backups/git001c/2026-09-24-pre-migrations/`: `schema.sql` voor `auth,storage,public,lws_internal` (SHA-256 `8549e9aad7a81bb12efb920a9ec3d5a6effb79b4750583d7056a84f7e5971937`) en één intern consistente `data.sql`-snapshot voor dezelfde vier schema's (SHA-256 `99c1bee423186d4c0cb686ab8129862a3fec233470b15f1af464da9ef6f46f14`). Het recoverymanifest vereist restore naar een geïsoleerde omgeving en een gecontroleerde vergelijking/repair; nooit een blinde productie-import. De volledige actuele authscope is meegenomen zonder de wijziging in `auth.users` als login of tokenrefresh te classificeren.
- De eerdere drie documentwijzigingen zijn vóór de clean-worktree gate vastgelegd als commit `aaad95da5969b15f7bba5e3f9aee2fb1435e40db` (`docs: record GIT-001C recovery gate`). Dit was de daadwerkelijk gebruikte `ExpectedHead`; de oudere `284fc48b30660bf4aeea40e113292af2ecd1581f` is niet hergebruikt.
- Het guarded script heeft vanaf die schone HEAD exact `20260922180000`, `20260923060000`, `20260923070000`, `20260923080000`, `20260923100000`, `20260923110000` en `20260923120000` in volgorde toegepast en rapporteerde `GIT001C_MIGRATIONS_APPLIED=PASS`.
- Post-apply verificatie: alle zeven remote ledgerregels bestaan; `supabase db push --linked --dry-run` geeft `upToDate=true` en nul pending; vijf nieuwe tabellen, twee triggers en twee vervangen constraints bestaan; alle acht leases hebben een unieke niet-null `authorized_build_id`; veertien RPC-signatures bestaan; grants zijn exact drie voor `authenticated` en elf voor `service_role`; de bucket heeft de bedoelde 5 MiB-limiet/MIME-lijst en nog steeds nul objecten. De releasecontracttest is 1/1 groen.
- Geen functies, secrets, Pages, custom domain, DNS, workflowdispatch, push of merge zijn uitgevoerd. Worker, klantrepository en `NO_SECOND_CREATE` blijven ongewijzigd. Gate 1 is geaccepteerd; Gate 2 blijft de eerstvolgende afzonderlijke productiepoort en **GIT-001C blijft OPEN**.

### Gate 2 bindings en previewfuncties 2026-09-24

- Gate 2 startte vanaf schone bewijscommit `305b1a28329d0a29f994482538892325876fc0eb`. De drie functiontrees en gedeelde runtimecode verschilden niet van geaccepteerde releasecommit `284fc48b30660bf4aeea40e113292af2ecd1581f`; de laatste functioncodecommit bleef `d628276a2b39988deabc0775c09d0da1c6dcacf7`.
- Exact vijf vaste workflow/OIDC-bindings zijn gezet: `LWS_PREVIEW_OIDC_AUDIENCE`, `LWS_PREVIEW_WORKFLOW_REPOSITORY`, `LWS_PREVIEW_WORKFLOW_REPOSITORY_ID`, `LWS_PREVIEW_WORKFLOW_REF` en `LWS_PREVIEW_WORKFLOW_REF_NAME`. Daarnaast is één cryptografisch willekeurige 32-byte `LWS_PREVIEW_ORIGIN_TOKEN` gezet. Waarden zijn niet gelogd; alle zes providerdigests zijn lokaal vergeleken en gelijk bevonden. De plaintext env-file is verwijderd; alleen een git-ignored DPAPI-versleutelde kopie voor de latere Pages-secretwrite blijft lokaal. `LWS_PREVIEW_HOST_URL` blijft conform Gate 4 afwezig. Bestaande GitHub App- en Supabase-bindings zijn niet herschreven.
- Exact drie functies zijn gedeployed, elk `ACTIVE`, versie `1`, `verify_jwt=false`: `website-project-preview-artifact` (ID `4d0d5831-6881-49a3-84ee-ef1c78c304ed`, bundle SHA-256 `81961a8237d4cbd31f938b41ac320312a8f63d4dd28241c8db9e4db9aaa81ffa`), `website-project-preview-source-token` (ID `4f272390-b936-448e-bb3c-38c629f30641`, bundle SHA-256 `707bb0604eb6458e4abcaac9c4a470a7b2034901f027f264c22a71bea678f1a3`) en `website-project-preview-host` (ID `d0c46887-2fcc-4963-a1e3-b228544217bc`, bundle SHA-256 `aefa64462c3cf70474e1dd29f287526902638ab71d983052129ab2c967d3312f`).
- Gerichte lokale securitytests waren `19/19` groen. Live zonder credentials: origin `403 PREVIEW_ORIGIN_FORBIDDEN`, source-token `401 SOURCE_TOKEN_OIDC_REQUIRED`, artifact `403 ARTIFACT_AUTHORITY_INVALID`. De origincheck vindt vóór RPC/Storage plaats; dit is ook lokaal met nul dependencycalls bewezen. Deployment alleen geldt niet als functionele liveacceptatie: geen geldig OIDC-token, GitHub installation token, artifactupload, previewsession of browserpad is uitgevoerd.
- Gate 1 blijft `upToDate=true` met nul pending migraties. De bestaande dossier-0006-binding bleef exact repository ID `1378797607`, node `R_kgDOUi7IJw`, commit `1f19bf01c61c6da79fa4c7374333a91b70f9bf48`, binding revision 1, `REPOSITORY_READY/BOUND`. De remote previewworkflow blijft afwezig. Pages heeft nul deployments en DNS blijft `NXDOMAIN` zonder CNAME. Geen Pages-, DNS-, dispatch-, push-, merge- of Auth/AAL2-wijziging is uitgevoerd; `NO_SECOND_CREATE` blijft hard.
- Gate 2 is geaccepteerd. Gate 3, deployment naar het bestaande lege Pages-project zonder DNS, blijft de eerstvolgende afzonderlijk geautoriseerde productiepoort. **GIT-001C blijft OPEN**.

### Gate 3 Pages-secret en deployment zonder DNS 2026-09-24

- Gate 3 hervatte exact vanaf schone evidencecommit `9ad3134dc16b432913973dae58f64d58c9413eaa`. Read-only preflight bevestigde bestaand project `lws-website-project-preview-host`, ID `56ba0651-2499-4b40-b3f7-ad2b690dfa3c`, toegewezen hostname `lws-website-project-preview-host.pages.dev`, nul deployments, nul custom domains, geen Pages-secrets, alleen Worker `lorenzobombello-api-proxy`, DNS `NXDOMAIN` en Wrangler `4.137.0` op account `acbc1b86d8c3f0ce809dc4600783a48b`. Lokale contract/workflowtests waren 4/4 groen en origin/Pages-tests 8/8 groen.
- De bestaande git-ignored DPAPI-`CurrentUser`-kopie is uitsluitend in memory ontsleuteld en als `LWS_PREVIEW_ORIGIN_TOKEN` naar het bestaande Pages-project geschreven; de waarde is niet gelogd en er is geen plaintextbestand gemaakt. Providerreadback toont exact deze ene versleutelde secretnaam.
- De eerste secretwrite stopte vóór providerwrite omdat Wrangler Pages het documentatieveld `secrets` in beide configbestanden afwees. Een RED-contracttest reproduceerde dit; commit `b8df38f73617e47aba60ab2bbcec3c14455c17f8` (`fix: make preview Pages config deployable`) verwijderde alleen dit niet-ondersteunde veld en bewaakte dat de secret niet in plaintextconfig voorkomt.
- De eerste deployment, ID `dff59da2-f14c-4f4a-8186-0cdeedff8467` vanaf `b8df38f73617e47aba60ab2bbcec3c14455c17f8`, compileerde en deployde succesvol maar werd niet geaccepteerd: de live `308` pages.dev-redirect miste `cache-control`. Een nieuwe RED-test legde de fout vast; commit `c79a72a26c6a4d958f43bdbca56d3c4bdc869ac1` (`fix: prevent caching preview redirects`) maakt de redirect expliciet `private, no-store` zonder origincontact.
- De vervangende production deployment, ID `84b61c2c-9672-4ffc-adb7-15581a095eae`, URL `https://84b61c2c.lws-website-project-preview-host.pages.dev`, is op `2026-09-24T04:18:02.0517160Z` vanaf branch `main`, exacte commit `c79a72a26c6a4d958f43bdbca56d3c4bdc869ac1`, `commit_dirty=false` en stage `deploy/success` aangemaakt. Er staan nu twee auditable deployments; de tweede is latest en geaccepteerd.
- Live geven zowel `https://lws-website-project-preview-host.pages.dev/about/?gate=3` als de immutable deploymenthost exact `308` naar `https://preview.lorenzowebsolutions.be/about/?gate=3`, met `cache-control: private, no-store`. Direct originverkeer zonder purpose-token blijft `403 PREVIEW_ORIGIN_FORBIDDEN`, eveneens `private, no-store`. Custom domains blijven 0, preview-DNS blijft `NXDOMAIN` met nul CNAME-antwoorden en de bestaande Worker blijft ongewijzigd.
- Dossier-0006 blijft exact repository ID `1378797607`, node `R_kgDOUi7IJw`, commit `1f19bf01c61c6da79fa4c7374333a91b70f9bf48`, revision 1, `REPOSITORY_READY/BOUND`. Er is geen Pages-project aangemaakt, geen custom domain/DNS, `LWS_PREVIEW_HOST_URL`, workflowpublicatie/dispatch, push, merge of Auth/AAL2-wijziging uitgevoerd. Gate 3 is geaccepteerd; Gate 4 blijft afzonderlijk geblokkeerd op expliciete autorisatie voor custom-domainassociatie, één OVH CNAME, TLS-acceptatie en pas daarna de host-URL-binding. **GIT-001C blijft OPEN**.

## Gerichte codebeoordeling 2026-09-23

- Onafhankelijke read-only review uitgevoerd door de `Explore`-subagent; bevindingen zijn vervolgens tegen de controlerende codepaden gevalideerd.
- Gecorrigeerd: platform/klant-OIDC-identiteitsverwarring, caller-selected build-ID, onbegrensd bodybufferen, verouderde typecheckfixtures en afwijkende `/directory/`-previewrouting.
- Niet overgenomen: AAL2 opnieuw afdwingen in service-role finalize. AAL2 autoriseert acquire; de korte actor-, repository-, commit-, workflow-, run- en buildgebonden lease is de gedelegeerde workflowautoriteit.
- Niet bevestigd als defect: tokenconsumptie bij een falende sessioninsert (transactionele rollback) en upload-complete-cleanup. Cleanup en herhaling zijn nu expliciet door tests vastgezet.
- Liveplan: `docs/superpowers/plans/2026-09-23-git001c-live-coupling.md`. Er is niets gedeployed, gemigreerd in productie, gedispatched, betaald of aan DNS gewijzigd.

## Resume-identiteit

- Worktree: `C:\Users\info\Project-Worktrees\lorenzo-web-studio-git001c-astro-preview-build-20260922`
- Branch: `git001c-astro-preview-build-20260922`
- HEAD bij hervatting van deze preflight: `2e5fdb80c0a40018cd48747b5897639ad8ec7170`
- Historische autoriteit: `C:\Users\info\.copilot\session-state\ab268b4e-f133-426c-8bf5-8e96610acbe3\checkpoints\009-git001c-astro-preview-build-plan.md`
- Volgend hervatpunt: voer alleen na afzonderlijke productieautorisatie Gate 4 uit: associeer `preview.lorenzowebsolutions.be` aan het bestaande Pages-project, voeg exact één OVH CNAME toe, accepteer managed TLS en zet pas daarna `LWS_PREVIEW_HOST_URL`. Workflowpublicatie en live dispatch blijven Gate 5.

Daarom blijft **GIT-001C OPEN**.