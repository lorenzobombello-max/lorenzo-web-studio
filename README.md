# Lorenzo Web Solutions

## Documentnaam
README.md

## Versie
2026-08-06

## Laatst bijgewerkt
2026-08-06

## Projectstatus
Dit document is een feitelijke statussnapshot van de huidige repository- en live-toestand.

Statuslegende die in dit document wordt gebruikt:
- lokaal gewijzigd: alleen lokaal aanwezig, nog niet gecommit
- gecommit: aanwezig in Git-historiek
- gepusht: aanwezig op origin/main
- live gedeployed: publiek zichtbaar via GitHub Pages
- nog te controleren: nog geen sluitend bewijs in deze controle
- toekomstig plan: expliciet nog niet uitgevoerd

## Bewezen feiten

### Git en branchstatus
- HEAD tijdens deze documentatiecontrole: 238c347480950e1be301ff708e5569fe2276f59f
- origin/main tijdens deze documentatiecontrole: 238c347480950e1be301ff708e5569fe2276f59f
- conclusie: HEAD en origin/main zijn gelijk (gepushed en gesynchroniseerd)

### GitHub Pages, deployment en security
- Actieve workflow: Deploy Static Site to GitHub Pages in [.github/workflows/deploy-pages.yml](.github/workflows/deploy-pages.yml)
- Build publiceert alleen dist-artifact via allowlist- en verifystappen:
  - [scripts/prepare-pages-dist.ps1](scripts/prepare-pages-dist.ps1)
  - [scripts/verify-pages-dist.ps1](scripts/verify-pages-dist.ps1)
- Dist denyregels blokkeren onder meer .md, .toml, package.json, supabase/, docs/, backup/, .github/, .git/, node_modules/
- Recente workflowruns: completed/success (run 1 t/m 7)
- Custom domain in repo: [CNAME](CNAME) met lorenzowebsolutions.be
- HTTPS actief op live site (https://lorenzowebsolutions.be/ geeft 200)
- Publieke securitychecks tijdens deze controle:
  - https://lorenzowebsolutions.be/README.md -> 404
  - https://lorenzowebsolutions.be/package.json -> 404
  - https://lorenzowebsolutions.be/scripts/prepare-pages-dist.ps1 -> 404
  - https://lorenzowebsolutions.be/supabase/config.toml -> 404

### AURELIS
- Demo aanwezig in [pages/demos/aurelis-architecture/index.html](pages/demos/aurelis-architecture/index.html)
- CSS aanwezig in [assets/css/demos/aurelis-architecture.css](assets/css/demos/aurelis-architecture.css)
- JS aanwezig in [assets/js/demos/aurelis-architecture.js](assets/js/demos/aurelis-architecture.js)
- Beeldmap aanwezig in [assets/images/demos/aurelis-architecture](assets/images/demos/aurelis-architecture)
- Gecommit bewijs (selectie):
  - 4a94273: initiële AURELIS demo-structuur
  - a68bb4f: placeholders vervangen door finale beelden
  - 73524b8: placeholderoverlay opgelost
  - b2cc59f: brede premium editorial hero
  - a927306: licht hero-paneel verbreed, afgerond en subtiele schaduw
- Homepage bevat Architectuur & Interieur-kaart en gebruikt echte AURELIS-previewfoto (commit 238c347)
- Bestand [assets/images/demos/aurelis-architecture/project-minimal-kitchen.jpg](assets/images/demos/aurelis-architecture/project-minimal-kitchen.jpg):
  - aanwezig
  - geen actieve codeverwijzing gevonden met git grep
  - status: lokaal bestand aanwezig, momenteel ongebruikt in tracked code

### Luna Hair Studio
- Gecommit bewijs (selectie):
  - 6f5099b: before/after slider-interactie hersteld
  - 7a8c263 en 21e3508: draggedrag en native overlay-problemen aangepakt
  - eab62a6: externe Instagram-links verwijderd
  - 70ebe57: Instagram overlay-iconen verwijderd
- Conclusie: deze wijzigingen zijn gecommit en gepusht; live validatie van elk detail valt buiten deze specifieke documentatiesessie.

### Homepage
- Interactieve demo-preview vergroot (84d7239)
- Cafe callbuttoncontrast hersteld (bb2bc10)
- AURELIS-stijlkaart toegevoegd op homepage (e92bb16)
- AURELIS-kaart gebruikt echte previewafbeelding (238c347)

### SEO
- Sitemap/canonical alignment (967c802)
- JSON-LD toegevoegd en gevalideerd (80e11be)
- Favicon/manifest toegevoegd (7291c6f)
- Metadata/social tags gesynchroniseerd (881944c)
- Semantiek/alt/link hygiene opgeschoond (8df2254)
- Noindex/noindex-follow aangetroffen in actuele code:
  - [pages/review-request.html](pages/review-request.html) -> noindex, nofollow
  - [pages/demos/luna-hair-studio/index.html](pages/demos/luna-hair-studio/index.html) -> noindex, nofollow
  - [pages/404.html](pages/404.html) -> noindex, follow
- Lighthouse-scorebeleid:
  - geen historische score als actuele score presenteren zonder nieuwe meting

### Afbeeldingsstructuur en reservekopieën
- Bestaande code-structuur:
  - [assets/css/demos](assets/css/demos)
  - [assets/js/demos](assets/js/demos)
- Voorbereide beeldstructuur:
  - [assets/images/demos](assets/images/demos)
- Reserve-/kopiemappen lokaal aanwezig (momenteel ongetrackt):
  - cafe
  - electrician
  - frituur
  - garage
  - industrial
  - luna-hair-studio
  - mediterranean-brasserie
  - personal
  - plumber
  - restaurant
- Besluit:
  - personal blijft exact personal
  - geen hernoemingen zonder aparte migratiefase
  - bestaande werkende paden blijven actief tot bewezen nul-referenties op oude paden

### Back-upbeleid
- Back-ups horen buiten deze repository.
- Centrale back-uplocatie: J:/Backup Lorenzo-web-solution
- In deze repository moet geen nieuwe backup-map worden aangemaakt.

## Huidige implementatie
- Frontend: statische HTML/CSS/JS site met demo-pagina's onder [pages/demos](pages/demos)
- Supabase-map aanwezig in [supabase](supabase) voor backendgerelateerde componenten
- GitHub Pages publiceert uitsluitend het door scripts gefilterde dist-artifact

## Openstaande werkzaamheden
- Nog te controleren: volledige, vernieuwde Lighthouse/performance meting (geen actuele score vastgelegd in deze docsessie)
- Toekomstig plan: gecontroleerde migratiefase voor reserve-afbeeldingsmappen pas na bewezen nul actieve verwijzingen
- Toekomstig plan: verdere documentatiesplitsing (projectstatus/security/qa) indien meerdere Markdownbestanden gewenst zijn

## Bekende risico's
- Ongetrackte reservebeeldmappen kunnen per ongeluk meegestaged worden zonder strikte git add-discipline
- Onjuiste statuslabels in documentatie kunnen regressie geven (bijvoorbeeld live claimen zonder deploybewijs)
- Verouderde lokale browsercache kan visuele mismatch geven terwijl code en live bron correct zijn

## Beslissingen die niet opnieuw gewijzigd mogen worden
- Geen repository-root deployment als actieve publicatiemethode beschrijven
- Dist-only allowlist/deploypad blijft de norm
- Interne bestanden (docs, supabase, scripts, md, toml, package.json) mogen niet publiek uitlekbaar zijn
- Geen secrets, tokens of privégegevens in documentatie opnemen

## Volgende veilige stap
1. Herbevestig opnieuw bij volgende wijzigingsronde: git status, HEAD/origin-main, workflowstatus en 404-securitychecks.
2. Voer documentatie-updates uit in Markdown-only commits, zonder codebestanden.
