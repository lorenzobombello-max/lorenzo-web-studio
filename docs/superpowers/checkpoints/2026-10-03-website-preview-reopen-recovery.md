# Websitepreview duurzaam heropenen - herstelcheckpoint

Datum: 2026-10-03  
Status: **CLOSED - PRODUCTIEPUBLICATIE EN ONLINE ACCEPTATIE PASS**

## Herstelde grens

- `Preview openen` is een zelfstandige OWNER+AAL2-actie en start geen build.
- De browser stuurt alleen het geselecteerde `quote_request_id`; build-, lease-, workspace- en repositoryautoriteit zijn niet clientselecteerbaar.
- De server selecteert atomair de nieuwste passende succesvolle build, met voorkeur voor de huidige commit, binnen exact de actuele work-context, workspace, private GitHub-binding, bindingrevision en canonieke durable repository-operatie.
- Iedere opening maakt een nieuwe tijdelijke viewer-sessie. Alleen de SHA-256-hash van het random sessietoken wordt opgeslagen; de handoff-URL wordt niet gepersisteerd.
- Bij een oudere passende build toont de operator-UI zowel de buildcommit als de huidige commit.
- Een response wordt alleen geaccepteerd wanneer dossier, work-context, workspace en bindingrevision nog exact overeenkomen. Een contextwissel sluit het gereserveerde previewvenster en navigeert niet.
- Bij een geblokkeerde popup wordt geen sessie uitgegeven. Een ontbrekende build en een niet-gereed repositorydossier starten evenmin een build of herstelactie.
- `Preview bouwen / vernieuwen` bouwt uitsluitend en maakt geen viewer-sessie meer.

## Lokale verificatie

- `node --test scripts/operator-website-execution.test.mjs`: **82/82 PASS**.
- Gerichte previewselectie daarbinnen: opnieuw openen, dashboardreload, nieuwe sessie per opening, oudere commitmelding, popupblokkade, geen-build, repository-blocked, contextwissel, gescheiden buildflow en opgeslagen `index.html`: **9/9 PASS**.
- `deno test --node-modules-dir=auto --allow-env --allow-read --filter "existing project preview opening" supabase/functions/commercial-operator-command/handler.test.ts`: **2/2 PASS**.
- Gesloten request-/dispatchcontract voor alle previewcontrols: **PASS**.
- Volledige handlerfile: **173/176 PASS**. De drie bestaande baselinefouten liggen buiten deze wijziging: workspace-read verwacht RPC v6 terwijl current main v5 aanroept, plus twee quotation-business-approval authorityverwachtingen. De gewijzigde previewtests zijn groen.
- Auth-aware volledige lokale Supabase-bootstrap: migraties door en met `20261003020000_open_existing_website_project_preview_v1.sql` toegepast: **PASS**.
- `git diff --check`: **PASS**.

## Productie-evidencegrens

De bestaande dossier-`0006`-build is alleen bewijsinput en wordt niet in productiecode vastgelegd:

- preview-build: `b93a0deb-48f3-4148-b39b-a39fab94b6ea`
- historische lease: `4b6f635f-2b05-45fd-a7ed-cdab443f6bda`
- workspace: `fa057e1f-d03d-47cf-a595-317447734298`
- repositorycommit: `1f19bf01c61c6da79fa4c7374333a91b70f9bf48`
- buildstatus: `PASS_WITH_WARNINGS`

Er is voor dit herstel lokaal en tijdens de read-only diagnose geen nieuwe klantrepository, build, promotie, betaling, verzending of C3-route aangemaakt of gestart. Dossier `0007` blijft buiten herstel en repository-blocked.

## Publicatie- en acceptatiegrens

### Productiepublicatie

- Productiemigratie `20261003020000_open_existing_website_project_preview_v1.sql`: toegepast; lokale en remote migratielijst gelijk, nul pending.
- Initiële implementatiecommit: `b7a236531da4ee0f22637e8d3d9259bff6ff9957`.
- Definitieve releasecommit met website-child cachekey: `28c629e1537329547040ba7e1f81f289ccf23492`, tree `bfadf8841af3f5cc580bc4b03b8cc75bfb29da08`.
- De eerste branch-run `37161282585` op `b7a2365` werd na deploy geannuleerd toen de ontbrekende cachekey-bump werd vastgesteld. Postdeploy en release approval bleven geannuleerd; de gecorrigeerde release volgde direct.
- Definitieve branch Pages-run `37161436857` op `28c629e`: **SUCCESS**, inclusief predeploy, build, deploy, postdeploy en release approval.
- Live `operator-module-registry.mjs` en `operator-website-execution-child.mjs` waren exact gelijk aan releasecommit `28c629e`; de registry bevatte `20261003-preview-reopen-r1` en de child de nieuwe openactie.
- Tijdelijke Pages-policy `61884570` is verwijderd. Alleen permanente policy `56274550:main:branch` bleef over.
- PR `#65` (`Fix reopening existing website previews`) is clean gemerged.
- Mergecommit: `0f88b0e4fbab00619a12b85684a31d0ba99a7020`; ouders `460d87d9ee9a6d649ac62242d2e95f74b6e999b8` en `28c629e1537329547040ba7e1f81f289ccf23492`; tree bleef `bfadf8841af3f5cc580bc4b03b8cc75bfb29da08`.
- Automatische main Pages-run `37162703906`: **SUCCESS** op de mergecommit.
- Automatische main Edge-run `37162703905`: **SUCCESS** op de mergecommit.
- Live Pages-assets waren na main-publicatie exact gelijk aan mergecommit `0f88b0e`.

### Online acceptatie dossier `0006`

- Projectbestanden bleef positief: `REPOSITORY_READY`, bindingrevision `1`, repository `lorenzo-web-solutions/lws-web-a88b1e8792714ad199ccb385b7982a8b`, commit `1f19bf01c61c6da79fa4c7374333a91b70f9bf48`; de Astro-rootinhoud werd via de bestaande OWNER+AAL2-gateway teruggegeven.
- De gedeployde frontendactie `open_existing_website_project_preview` op quote `7458c346-dfc9-40f3-ad0e-cb94a16636bf` opende zichtbaar `Baseline | A clear start for the web` op `preview.lorenzowebsolutions.be`, met stylesheet en werkende interne navigatie.
- Build `b93a0deb-48f3-4148-b39b-a39fab94b6ea` werd hergebruikt met status `PASS_WITH_WARNINGS`; buildcommit en huidige commit waren beide `1f19bf01c61c6da79fa4c7374333a91b70f9bf48`.
- Sluiten en opnieuw openen gaf exact één nieuwe openactie, geen buildactie, en opnieuw een zichtbare viewer.
- Na dashboardreload, herselectie van `0006` en AAL2-herverificatie opende de viewer opnieuw. De opeenvolgende handoff-URL's hadden verschillende SHA-256-bewijshashes; de URL's zelf zijn niet vastgelegd.
- Een exact geidentificeerde tijdelijke testviewer `f109bd06-4667-4c66-a3ba-5917881a6a4b` is na succesvolle handoff ingetrokken. Herladen gaf HTTP `401 PREVIEW_SESSION_INVALID`; een daaropvolgende nieuwe openactie gaf weer een zichtbare HTTP 200-viewer op dezelfde bestaande build.
- Na volledige renderwissel naar dossier `0007` gebruikte de openprobe quote `3cd78db7-d310-4082-b84c-8ddba3da11c8` en gaf exact HTTP `409 PROJECT_PREVIEW_REPOSITORY_NOT_READY`, zonder viewer, build of repositoryherstel.
- Omdat geen tweede geschikt live dossier zonder build beschikbaar was, blijft de geen-buildisolatie gebaseerd op de gerichte lokale browsertest; die geeft de veilige fout en bewijst nul buildrequests.

De geintegreerde acceptatiebrowser blokkeerde het normale operator-child-popupvenster. Daarom is de online vieweracceptatie uitgevoerd via dezelfde gedeployde frontendgateway vanuit de geauthenticeerde dashboardcontext; de normale knop-, popup-, contextcorrelatie- en close/reopen-flow is aanvullend door de gerichte Playwright-suite bewezen.

Er is geen nieuwe klantrepository of previewbuild gemaakt. Dossier `0007` is niet hersteld. Er is geen promotie-, betaal-, verzend- of C3-actie uitgevoerd.