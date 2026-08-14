# Final Production Checkpoint 2026-08-14

## Document authority

Dit document is vanaf 14 augustus 2026 de primaire hervattingsbron voor Lorenzo Web Solutions / `lorenzo-web-studio`.

- Repository: `lorenzobombello-max/lorenzo-web-studio`
- Production branch: `origin/main`
- Finale productiecommit: `17669ab1e649f5cbfaeee6349ba8dccdc91a76ff`
- Commit: `Fix homepage hero descender clipping`
- Website status: **KLAAR / PRODUCTION READY voor de huidige goedgekeurde scope**
- Live URL: `https://lorenzowebsolutions.be/`
- Statusdatum: 2026-08-14

De code, migrations en runtimeconfiguratie blijven de technische bron van waarheid. Dit checkpoint vervangt geen historische evidence; het bepaalt welke Git- en projectstatus bij hervatting actueel is. Neem nooit secrets, raw tokens, private capabilities, service-role credentials of private environmentwaarden op in repositorydocumentatie.

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
