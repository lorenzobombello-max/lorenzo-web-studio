# Lorenzo Web Solutions — Homepage Hero Redesign

**Datum:** 5 augustus 2026  
**Status:** Ontwerp goedgekeurd door Lorenzo  
**Scope:** Homepage hero en de visuele overgang naar de interactieve demo-showcase

## 1. Doel

De homepage moet Lorenzo Web Solutions positioneren als een ontwerpstudio die geen vaste templates verkoopt, maar unieke digitale ontwerpwerelden bouwt voor zelfstandigen en kleine ondernemingen.

De eerste schermhoogte moet binnen enkele seconden duidelijk maken:

- dat elke branche een eigen visuele identiteit krijgt;
- dat ontwerp en techniek samen worden ontwikkeld;
- dat rechtstreeks persoonlijk contact centraal staat;
- dat bezoekers verschillende demo-werelden kunnen ontdekken.

## 2. Kernboodschap

### Hoofdtitel

**Websites die jouw onderneming laten opvallen.**

### Ondersteunende boodschap

**Geen vast template. Een digitale identiteit op maat van jouw onderneming.**

### Primaire actie

**Bekijk ontwerpwerelden**

Deze knop scrolt naar de interactieve demo-showcase.

### Secundaire actie

**Start jouw project**

Deze knop scrolt naar het contact- of projectstartformulier.

## 3. Visuele richting

De hero krijgt een premium, moderne studiostijl met:

- een donkere, gelaagde achtergrond;
- subtiele navy-, blauw- en violetgradients;
- zachte lichtvlekken en technische gridlijnen;
- transparante glaspanelen;
- zwevende apparaatmock-ups;
- ruime typografie en veel visuele rust;
- zachte dieptewerking zonder overdadige 3D-effecten.

De stijl moet professioneel, technisch en persoonlijk blijven. Het ontwerp mag niet aanvoelen als een game-interface of futuristische gimmick.

## 4. Hero-compositie

### Linkerzone

Bevat:

- kleine studio-eyebrow: `THE LIVING WEB STUDIO`;
- hoofdtitel;
- korte waardepropositie;
- primaire en secundaire CTA;
- drie vertrouwenspunten:
  - vrijblijvende kennismaking;
  - transparante prijsrichting;
  - rechtstreeks contact met Lorenzo.

### Rechterzone

Bevat een visuele compositie van:

- één centrale laptop;
- één smartphone;
- één secundair scherm of browservenster;
- zwevende miniaturen van meerdere demo-werelden;
- subtiele labels voor restaurant, garage, café en portfolio.

De centrale mock-up toont standaard Lorenzo Web Solutions. Bij interactie kan de inhoud wisselen naar de actieve ontwerpwereld.

## 5. Ontwerpwerelden

De hero en showcase ondersteunen minstens deze identiteiten:

| Ontwerpwereld | Sfeer | Accent |
|---|---|---|
| Restaurant | verfijnd, warm, culinair | bordeaux en goud |
| Café | gezellig, ambachtelijk, toegankelijk | amber en houttinten |
| Garage | krachtig, technisch, performant | elektrisch blauw en staal |
| Personal Portfolio | premium, helder, professioneel | navy, wit en koelblauw |
| Elektricien | slim, innovatief, betrouwbaar | cyaan en donkerblauw |
| Kapsalon | stijlvol, elegant, persoonlijk | champagne en zacht goud |
| Loodgieter | modern, degelijk, verzorgd | turquoise en leisteen |

De actieve wereld verandert gecontroleerd:

- achtergrondaccent;
- gloedkleur;
- actieve chip;
- mock-upinhoud;
- korte begeleidende tekst;
- CTA-accent.

## 6. Interactie en animatie

### Intro-animatie

Duur: ongeveer 1,8 tot 2,4 seconden.

Volgorde:

1. achtergrond en grid verschijnen;
2. eyebrow en titel komen zacht omhoog;
3. CTA's verschijnen;
4. centrale laptop schuift subtiel binnen;
5. smartphone en zwevende kaarten volgen;
6. ontwerpwereld-selector wordt actief.

### Hover en pointer

- mock-ups bewegen maximaal enkele pixels;
- kaarten krijgen lichte schaalvergroting;
- knoppen krijgen een subtiele lichtreflectie;
- geen agressieve rotatie of grote cursorvolgers.

### Wisselen van ontwerpwereld

- crossfade van afbeelding;
- zachte gradientovergang;
- tekst schuift maximaal 12–20 px;
- totale overgang ongeveer 500–700 ms;
- geen volledige pagina-herlading.

### Scrollovergang

Onderaan de hero staat een duidelijke scroll-indicatie. De hero vloeit visueel over in de interactieve showcase, zodat beide onderdelen als één ervaring aanvoelen.

## 7. Toegankelijkheid en performance

- volledige bediening via toetsenbord;
- zichtbare focusstatussen;
- correcte heading-structuur;
- voldoende kleurcontrast;
- alternatieve tekst voor betekenisvolle beelden;
- ondersteuning voor `prefers-reduced-motion`;
- geen automatische video met geluid;
- afbeeldingen in WebP of AVIF met fallback;
- lazy loading voor niet-kritieke showcasebeelden;
- hero-LCP-afbeelding vooraf laden;
- animaties hoofdzakelijk via `transform` en `opacity`.

## 8. Responsive gedrag

### Desktop

Twee kolommen: tekst links, apparatencompositie rechts.

### Tablet

Tekst blijft links of bovenaan; mock-ups worden compacter en overlappen minder.

### Mobiel

- één kolom;
- titel en CTA's eerst;
- één primaire apparaatmock-up;
- secundaire zwevende elementen worden verminderd of verborgen;
- ontwerpwereld-selector horizontaal scrollbaar;
- geen horizontale pagina-overflow.

## 9. Componentstructuur

Voorgestelde onderdelen:

- `HeroSection`
- `HeroCopy`
- `HeroActions`
- `TrustHighlights`
- `DeviceStage`
- `DesignWorldSelector`
- `WorldThemeController`
- `ScrollCue`

In een klassieke HTML/CSS/JavaScript-codebase mogen dit semantisch gescheiden secties en modules zijn in plaats van frameworkcomponenten.

## 10. Buiten scope voor deze eerste implementatie

- achtergrondvideo;
- WebGL of zware 3D-engine;
- geluidseffecten;
- volledige redesign van alle onderliggende homepage-secties;
- CMS-koppeling;
- nieuwe contactbackend.

Deze onderdelen kunnen later worden toegevoegd nadat hero en showcase stabiel, responsief en performant zijn.

## 11. Acceptatiecriteria

Het ontwerp is geslaagd wanneer:

- de waardepropositie binnen vijf seconden begrijpelijk is;
- de hero duidelijk premium en onderscheidend oogt;
- de verschillende ontwerpwerelden visueel herkenbaar zijn;
- CTA's logisch en direct bruikbaar zijn;
- desktop, tablet en mobiel geen overflow of layoutbreuken vertonen;
- reduced-motion correct werkt;
- de site snel en vloeiend blijft;
- de nieuwe hero naadloos aansluit op de bestaande interactieve demo-showcase.

## 12. Implementatievolgorde

1. bestaande hero inventariseren;
2. semantische HTML-structuur aanpassen;
3. design tokens en themavariabelen toevoegen;
4. desktoplay-out bouwen;
5. responsive gedrag uitwerken;
6. ontwerpwereld-selector koppelen;
7. animaties toevoegen;
8. reduced-motion en toetsenbordbediening toevoegen;
9. performance en visuele regressie controleren;
10. inhoud en beeldselectie definitief afstemmen.
