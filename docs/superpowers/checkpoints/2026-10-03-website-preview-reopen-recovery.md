# Websitepreview duurzaam heropenen - herstelcheckpoint

Datum: 2026-10-03  
Status: **LOKAAL PASS - PRODUCTIEPUBLICATIE EN ONLINE ACCEPTATIE PENDING**

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

Nog niet bewezen op het moment van dit checkpoint:

- productiemigratie toegepast;
- Pages-release op de exacte release-SHA;
- PR/main-integratie en automatische Pages-/Edge-runs;
- online zichtbare opening vanuit dossier `0006`;
- sluiten en opnieuw openen;
- dashboard herladen en opnieuw openen;
- verlopen/ingetrokken sessie weigeren en daarna via een nieuwe sessie opnieuw openen;
- dossierwisselisolatie en de zichtbare geen-build/repository-blocked toestanden online.

De status mag pas naar **CLOSED** wanneer bovenstaande online acceptatie zichtbaar is uitgevoerd en de exacte release-, deployment- en bewijsidentiteiten aan dit checkpoint zijn toegevoegd.