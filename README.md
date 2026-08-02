# Lorenzo Web Solutions

Professionele website voor Lorenzo Web Solutions, gebouwd met HTML5, CSS3 en JavaScript (zonder frontend framework), met een veilige offerteaanvraagflow via Supabase Edge Functions en Resend (server-side).

## Architectuuroverzicht

### Frontend
- Statische pagina's in [index.html](index.html) en [pages](pages)
- Contactformulier op home en contactpagina
- Form submit via `POST` naar Supabase Edge Function `submit-quote-request`
- Beheerreview via [pages/review-request.html](pages/review-request.html)

### Backend (lokaal voorbereid)
- Supabase structuur in [supabase](supabase)
- SQL migratie in [supabase/migrations/20260802_create_quote_requests.sql](supabase/migrations/20260802_create_quote_requests.sql)
- Edge Functions:
  - `submit-quote-request`
  - `review-quote-request`
- Gedeelde security/validation helpers in `supabase/functions/_shared`

### E-mail
- Resend wordt uitsluitend server-side aangeroepen vanuit Edge Functions.
- Nooit API keys in frontendbestanden.

## Projectstructuur

- `index.html`
- `pages/contact.html`
- `pages/review-request.html`
- `assets/css/style.css`
- `assets/js/main.js`
- `assets/js/review-request.js`
- `supabase/config.toml`
- `supabase/migrations/20260802_create_quote_requests.sql`
- `supabase/functions/_shared/*`
- `supabase/functions/submit-quote-request/index.ts`
- `supabase/functions/review-quote-request/index.ts`
- `.env.example`
- `supabase/functions/.env.example`

## Vereiste environment variables

### Frontend (publiek, geen secret)
Gebruik [.env.example](.env.example):

- `PUBLIC_SUPABASE_FUNCTIONS_BASE_URL`

Op dit moment staat in de HTML een placeholder meta-tag:

- `https://YOUR-PROJECT-REF.supabase.co/functions/v1`

### Edge Functions (server-side secrets)
Gebruik [supabase/functions/.env.example](supabase/functions/.env.example):

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `RESEND_API_KEY`
- `ADMIN_EMAIL`
- `FROM_EMAIL`
- `SITE_URL`
- `APPROVAL_TOKEN_SECRET`
- `TOKEN_TTL_MINUTES`
- `RATE_LIMIT_WINDOW_SECONDS`
- `RATE_LIMIT_MAX_REQUESTS`

## Database-installatie (nog NIET automatisch uitgevoerd)

De SQL migratie staat klaar in:

- [supabase/migrations/20260802_create_quote_requests.sql](supabase/migrations/20260802_create_quote_requests.sql)

Deze migratie voorziet:
- type `quote_request_status` (`pending`, `approved`, `rejected`)
- tabel `quote_requests`
- constraints op lengte en toegelaten statussen
- token-vereiste bij `pending`
- indexes voor status, created_at en rate-limit op ip-hash
- `updated_at` trigger
- RLS ingeschakeld

Belangrijk:
- Tijdens deze fase zijn geen databaseobjecten aangemaakt in een echt Supabase-project.

## Edge Function gedrag

### `submit-quote-request`
- accepteert alleen `POST`
- CORS allowlist:
  - `http://127.0.0.1`
  - `http://localhost`
  - `https://lorenzowebsolutions.be`
  - `https://www.lorenzowebsolutions.be`
- server-side validatie:
  - trimmen
  - max lengtes
  - e-mailformaat
  - privacy consent verplicht
- honeypot check (`website` veld)
- rate limiting op gehashte client-IP
- token generatie (cryptografisch sterk)
- alleen token-hash opslag
- insert als `pending`
- admin-notificatie via Resend

### `review-quote-request`
- `GET`: status opvragen via token (`pending`, `expired`, `invalid`, `approved`, `rejected`)
- `POST`: actie `approved` of `rejected`
- token-check + vervaldatum
- voorkomt dubbele review (alleen update vanuit `pending`)
- bij `approved`: bevestigingsmail naar aanvrager
- bij `rejected`: alleen statusupdate

## Beveiligingsaandachtspunten

- Service-role key staat nergens in frontend.
- Resend API-key staat nergens in frontend.
- Geen ruwe IP-opslag: alleen hash.
- Geen persoonsgegevens in URL.
- Alleen hash van approval-token wordt opgeslagen.
- Tokens vervallen en zijn eenmalig bruikbaar.
- Geen logging van secrets of tokens.

## Frontendformulier-flow

- Honeypotveld toegevoegd op beide formulieren.
- Dubbel verzenden wordt geblokkeerd door disabled submit tijdens request.
- Succesmelding:
  - "Bedankt. Je aanvraag is veilig ontvangen en wordt persoonlijk nagekeken."
- Foutmelding:
  - "De aanvraag kon momenteel niet worden verzonden. Probeer later opnieuw of neem rechtstreeks contact op."
- Aria-live feedback blijft actief via `#formMessage`.

## Domein en SEO

Voorbereid op:

- `https://lorenzowebsolutions.be`

Bijgewerkt in:
- canonical URLs
- Open Graph URLs
- `sitemap.xml`
- `robots.txt`

## Lokale testprocedure

1. Start een lokale static server voor de website.
2. Controleer formulieren op:
   - verplichte velden
   - ongeldig e-mailadres
   - privacy checkbox
   - honeypotveld (moet leeg blijven)
3. Configureer lokaal Supabase CLI-project en functions secrets (nog zonder deploy naar productie).
4. Test `submit-quote-request` en `review-quote-request` lokaal tegen Supabase local stack.
5. Controleer browser console op errors.

## Validatiechecklist

- Geldige aanvraag
- Ontbrekende verplichte velden
- Foutief e-mailadres
- Ontbrekende privacytoestemming
- Honeypottrigger
- Dubbele verzending
- Verlopen token
- Ongeldig token
- Reeds gebruikt token
- Goedkeuring
- Afwijzing
- Mailfout
- Databasefout
- Verkeerde origin
- Mobiele weergave
- Console errors
- Afwezigheid van secrets in frontend/repository

## Resend afzender (huidige keuze)

Voor deze website wordt voorlopig het bestaande geverifieerde Resend-domein gebruikt:
- `mail.lorenzobombello.be`

Actieve afzender voor configuratie:
- `FROM_EMAIL=offertes@mail.lorenzobombello.be`

Belangrijk:
- bestaande Resend-configuratie niet aanpassen
- testmails pas uitvoeren in een expliciet goedgekeurde latere stap

## Productieconfiguratie (later, na expliciete goedkeuring)

Nog NIET uitgevoerd in deze fase:
- Supabase projectconfiguratie
- Migratie uitvoeren op echte database
- Edge Function deploy
- Secrets instellen in Supabase
- Resend key aanmaken/instellen

## Rollback-instructies

Voor deze fase is een timestamp-back-up gemaakt:

- [backup/2026-08-02-130153-phase2-offerte-flow](backup/2026-08-02-130153-phase2-offerte-flow)

Rollback:
1. Kopieer bestanden vanuit deze backup terug naar de root.
2. Verifieer formuliertoestand en metadata.
3. Herhaal lokale checks.
