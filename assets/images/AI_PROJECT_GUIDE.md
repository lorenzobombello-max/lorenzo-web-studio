\# AI Project Guide



\## Doel



Dit project bevat professionele demo-websites voor verschillende bedrijfssectoren.

Alle wijzigingen moeten de bestaande kwaliteit, structuur, herbruikbaarheid en onderhoudbaarheid behouden.



\---



\## Git



\- Maak geen wijzigingen buiten de opdracht.

\- Respecteer de bestaande Git-structuur.

\- Verwijder geen bestanden zonder toestemming.

\- Geef altijd een overzicht van alle gewijzigde bestanden.



\---



\## Projectstructuur



\- Respecteer de bestaande mappenstructuur.

\- Maak geen nieuwe mappen zonder duidelijke reden.

\- Verplaats of hernoem bestanden alleen wanneer alle verwijzingen worden bijgewerkt.

\- Wijzig alleen bestanden die noodzakelijk zijn voor de opdracht.



\---



\## Codekwaliteit



\- Houd code leesbaar, consistent en onderhoudbaar.

\- Vermijd ongebruikte HTML, CSS en JavaScript.

\- Hergebruik bestaande componenten waar mogelijk.

\- Respecteer de bestaande architectuur.

\- Breek nooit bestaande functionaliteit.



\---



\## Naamgeving



\- Gebruik Engelse bestandsnamen.

\- Gebruik kleine letters.

\- Gebruik koppeltekens (-) als scheiding.

\- Vermijd spaties.

\- Gebruik oplopende nummering (-01, -02, -03).

\- Gebruik geen haakjes, telsuffixen of kopieaanduidingen in bestandsnamen (bijvoorbeeld `bestand (2).jpg`). Gebruik in plaats daarvan de oplopende nummering hierboven.



Voorbeelden:



hero-control-cabinet-01.jpg



service-machine-wiring-01.jpg



garage-project-02.jpg



\---



\## Afbeeldingen



\- Gebruik uitsluitend afbeeldingen uit de juiste map binnen `assets/images/`.

\- Gebruik alleen afbeeldingen uit dezelfde branche.

\- Gebruik geen dubbele foto's op dezelfde pagina.

\- Hergebruik alleen wanneer een andere crop echt nodig is.

\- Controleer de licentie vóór gebruik. Bij twijfel: status "onzeker", en het bestand mag niet gebruikt worden op een live of gedeelde pagina.

\- Controleer vóór het toevoegen van een nieuw bestand de SHA256-hash tegen bestaande bestanden in dezelfde map, om te vermijden dat hetzelfde beeld onder een andere naam dubbel wordt opgeslagen.

\- Zie de sectie "Bronnen en licentiestatus" voor toegestane bronnen en verplichte statusregistratie.

\- Bewaar altijd het originele bestand.

\- Gebruik `object-fit: cover` waar nodig.

\- Houd de beeldkwaliteit consistent.



\---



\## Bronnen en licentiestatus



Toegestane bronnen:

\- Aangekochte stockbibliotheken met bewaarde licentie of factuur.

\- Eigen, door Lorenzo gemaakte foto's met expliciete toestemming voor publiek gebruik.



Verboden bronnen:

\- Foto's van marktplaatsen of veilingsites (eBay, Marktplaats, Facebook Marketplace, Vinted, en vergelijkbare platformen).

\- Foto's die herleidbaar zijn naar een bestaand, identificeerbaar bedrijf, via bestandsnaam, watermerk of andere contextuele informatie.

\- Losse resultaten uit een algemene afbeeldingenzoekopdracht (Google, Bing) zonder vastgestelde licentie.

\- Screenshots van andere websites.



Licentiestatus per bestand:

\- \*\*geverifieerd\*\*: bron en gebruiksrecht zijn aantoonbaar.

\- \*\*onzeker\*\*: bron of recht is niet vastgesteld.

\- \*\*geblokkeerd\*\*: bron is twijfelachtig of expliciet ongeschikt.



Status "onzeker" of "geblokkeerd" betekent: het bestand mag nooit gebruikt worden op een live of gedeelde pagina, ook niet tijdelijk of als placeholder.



Elke Image Library bevat een manifestbestand (bijvoorbeeld `manifest.csv`) met minstens deze kolommen: bestandsnaam, categorie, oriëntatie, bron/licentie, licentiestatus, gebruiksstatus, aanbevolen sectie.



Een stockfoto die is aangekocht of vrijgegeven voor één specifiek project dekt niet automatisch het gebruik in andere demo's of branches. Controleer de licentievoorwaarden expliciet bij hergebruik over meerdere demo's heen.



\---



\## HTML



\- Gebruik semantische HTML.

\- Houd de structuur overzichtelijk.

\- Vermijd dubbele code.

\- Behoud bestaande accessibility.



\---



\## CSS



\- Gebruik bestaande variabelen.

\- Gebruik bestaande design tokens.

\- Respecteer responsive breakpoints.

\- Vermijd inline CSS.



\---



\## JavaScript



\- Gebruik bestaande componenten.

\- Voeg geen onnodige libraries toe.

\- Breid bestaande functionaliteit uit zonder ze te breken.



\---



\## SEO



\- Respecteer bestaande SEO.

\- Verwijder geen metadata.

\- Houd alt-teksten correct.

\- Wijzig URL-structuren alleen na goedkeuring.



\---



\## Veiligheid



\- Verwijder nooit bestanden zonder toestemming.

\- Pas beveiliging alleen aan na expliciete opdracht.

\- Wijzig geen configuratiebestanden buiten de opdracht.



\---



\## Image Libraries



Elke branche bevat een eigen \*\*Image Library\*\*.



Voorbeelden:



assets/images/cafe/



assets/images/restaurant/



assets/images/industrial/



assets/images/garage/



Werkwijze:



\- Lees altijd eerst de juiste Image Library.

\- Gebruik uitsluitend afbeeldingen uit die branche.

\- Respecteer de richtlijnen uit dat document.

\- Elke Image Library-map bevat een bijhorend manifestbestand zoals beschreven in "Bronnen en licentiestatus".



\---



\## Werkwijze



1\. Analyseer eerst de bestaande code.

2\. Lees dit document volledig.

3\. Lees daarna de juiste Image Library, inclusief het manifestbestand.

4\. Stel een plan op en leg dit voor ter goedkeuring.

5\. Wacht op expliciete goedkeuring voor je begint met wijzigen.

6\. Voer kleine en gecontroleerde wijzigingen uit.

7\. Test desktop, tablet en mobiel.

8\. Controleer HTML, CSS en JavaScript.

9\. Controleer bestaande functionaliteit.

10\. Geef een overzicht van alle wijzigingen.



\---



\## Verboden



\- Geen bestanden verwijderen zonder toestemming.

\- Geen grote refactors zonder goedkeuring.

\- Geen willekeurige afbeeldingen gebruiken.

\- Geen componenten dupliceren als hergebruik mogelijk is.

\- Geen aannames maken over ontbrekende bestanden.

\- Geen bestanden gebruiken met licentiestatus "onzeker" of "geblokkeerd".



\---



\## AI Gedrag



\- Vraag verduidelijking wanneer informatie ontbreekt.

\- Meld onzekerheden expliciet.

\- Respecteer bestaande architectuur en stijl.

\- Geef geen fictieve bestanden, code of oplossingen.

\- Werk stap voor stap.

\- Wijzig nooit meer dan nodig is.

\- Beschrijf wijzigingen aan afbeeldingen altijd met exacte bestandsnamen, nooit met vage omschrijvingen zoals "andere visuele behandeling".



\---



\## Oplevering



Bij afronding altijd:



\- Som alle gewijzigde bestanden op.

\- Beschrijf kort wat gewijzigd is, met exacte bestandsnamen bij beeldwijzigingen.

\- Lever voor- en na-screenshots aan bij zichtbare layout- of beeldwijzigingen.

\- Vermeld eventuele aandachtspunten.

\- Vermeld eventuele resterende risico's of beperkingen.



\---



\## Kwaliteitsdoel



Elke demo-website moet eruitzien alsof ze ontwikkeld is door één professioneel webdesignbureau:



\- consistente structuur;

\- consistente componenten;

\- consistente UX;

\- consistente kleurbehandeling over alle gebruikte foto's, ongeacht bron;

\- professionele prestaties;

\- onderhoudbare code;

\- hoogwaardige visuele kwaliteit.

