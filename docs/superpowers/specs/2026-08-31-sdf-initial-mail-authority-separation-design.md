# SDF Initial Mail Authority Separation

## 1. Doel

Dit ontwerp scheidt uitsluitend de businessauthority voor de initiële ontvangstbevestiging van een Slimme Documentenflow-aanvraag van `public.quote_request_email_jobs`.

Na de definitieve cutover geldt voor iedere nieuwe SDF-aanvraag:

- de semantische ontvangstbevestiging ontstaat uitsluitend in SDF-specifieke businessstate;
- claim, lease, retry, terminal failure en completion worden uitsluitend door SDF-specifieke RPC's beheerd;
- geen nieuwe SDF initial-confirmationrow ontstaat in `public.quote_request_email_jobs`;
- Website-mailstate, Website-RPC's, Website-indexen, Website-constraints en Website-workersemantiek blijven ongewijzigd;
- alleen stateless providertransport en andere state-vrije technische primitives mogen generiek blijven.

De ontwerpkeuze is **B: een aparte SDF initial-request mailjobtable**.

`public.sdf_qualification_intake_email_jobs` wordt niet uitgebreid. Die tabel is eigendom van de qualification-intakelifecycle en identificeert semantische mails met `intake_id`, `invitation_generation` en `submission_sequence`. De initiële ontvangstbevestiging bestaat vóór een qualification intake en wordt semantisch geïdentificeerd door `quote_request_id`. Samenvoegen zou twee lifecycle-roots, twee autorisatiemomenten en verschillende idempotencydimensies in één businessauthority plaatsen.

Deze boundary betreft uitsluitend de klantgerichte SDF-mail met template `SDF_REQUEST_RECEIVED_NL_BE_v1`. De interne `admin_notification` die bij de gedeelde request-ingress ontstaat, blijft in deze fase in `public.quote_request_email_jobs`; dat is een afzonderlijke, later te beoordelen isolation boundary. "Geen Website-businessstate hergebruikt" betekent in dit document daarom: geen Website/shared mail-businessstate in de target call chain van de SDF initial customer confirmation.

## 2. Huidige architectuur

### 2.1 Huidige SDF call chain

1. `supabase/functions/submit-quote-request/index.ts` valideert een SDF-aanvraag en roept `public.create_quote_request_idempotent` aan.
2. `public.create_quote_request_idempotent` schrijft de gedeelde root `public.quote_requests`. Deze RPC maakt op dat moment alleen een gedeelde `admin_notification` in `public.quote_request_email_jobs`.
3. `lws_internal.enroll_application_intake_automation_v1` maakt voor de SDF-request een rij in `lws_internal.application_intake_automation_work` met fase `SDF_CONFIRMATION`, gepland op `quote_requests.created_at + 120 seconds`.
4. De gedeelde cron roept de Edge Function `application-intake-automation` aan.
5. `public.claim_application_intake_automation_work_v1` claimt de gedeelde workrij met een lease van 90 seconden.
6. De worker dispatcht `SDF_CONFIRMATION` naar `public.execute_application_intake_automation_sdf_confirmation_v1`.
7. Deze RPC maakt of herneemt in `public.quote_request_email_jobs` één job met:
   - `kind = 'customer_confirmation'`;
   - `template_key = 'SDF_REQUEST_RECEIVED_NL_BE_v1'`;
   - `template_version = 'v1'`.
8. De semantische job-idempotency berust op de gedeelde unieke non-reminderindex voor `(quote_request_id, kind)` en een aanvullende `not exists`-controle.
9. `executeSdfConfirmation` bouwt de payload via `buildSdfRequestReceivedEmail` en roept de stateful helper `deliverEmailJob` aan.
10. `deliverEmailJob` claimt via `public.claim_quote_request_email_job`, leest classificatie via `public.get_quote_request_email_classification_v1` en verstuurt via Resend met `Idempotency-Key: quote-request-email/{job_id}`.
11. `public.complete_quote_request_email_job` zet de job op `sent`, `retry_wait` of `failed`. Retryable HTTP-statussen zijn 408, 425, 429 en 5xx; netwerkfouten en time-outs zijn retryable. De backoff is exponentieel vanaf 30 seconden met een maximum van 3600 seconden.
12. Bij succesvolle completion projecteert de gedeelde RPC `confirmation_sent_at` op `public.quote_requests`.
13. `lws_internal.advance_sdf_automation_from_confirmation_job_v1` en `lws_internal.advance_sdf_automation_after_confirmation_v1` zetten de SDF-workfase op `SDF_INTAKE` en maken een reeds voorbereide qualification-uitnodiging leverbaar vanaf `sent_at + 120 seconds`.

### 2.2 Huidige Website authority

De Website-mailauthority blijft:

- `public.quote_request_email_jobs`;
- `public.claim_quote_request_email_job`;
- `public.complete_quote_request_email_job`;
- `public.requeue_quote_request_email_job`;
- `public.get_quote_request_email_classification_v1`;
- de bestaande Website-producers voor customer confirmation, intake invitation/reminders en quotation/acceptance;
- de bestaande stateful `deliverEmailJob`-helper.

`public.transition_quote_request_review` en alle Website approval-, intake-, reminder-, quotation- en acceptancecontracten blijven byte-for-byte buiten de implementatiescope van deze boundary.

### 2.3 Bestaand SDF qualification-mailpatroon

`public.sdf_qualification_intake_email_jobs` bewijst de volgende herbruikbare principes:

- producteigen businessstate met geforceerde RLS en zonder directe table privileges;
- één unieke semantische sleutel per lifecyclemail;
- een stabiele `job_id` als provider-idempotencybasis;
- expliciete `pending`, `processing`, `retry_wait`, `sent` en `failed` states;
- lease-token plus lease-expiry;
- completion alleen door de actuele leasehouder;
- maximaal vijf pogingen;
- exponentiële backoff van 30 seconden, begrensd op 3600 seconden;
- terminal failure zonder impliciete fallback;
- provideracceptatie vastgelegd met `provider_message_id`.

Niet herbruikbaar als gedeelde businessstate zijn `intake_id`, `invitation_generation`, `submission_sequence`, capabilityciphertext en qualification-event-idempotency. Die gegevens hebben geen betekenis voor de initiële request confirmation.

Ook `public.quote_request_email_status`, dat de bestaande qualification-tabel momenteel hergebruikt, wordt bewust niet overgenomen. De nieuwe initial-confirmationauthority krijgt een eigen text-checkcontract zodat een latere Website-statuswijziging haar niet kan raken.

## 3. Bewezen risico

De SDF initial confirmation gebruikt momenteel dezelfde tabel, statusenum, unieke index, claim-RPC, completion-RPC en stateful deliveryhelper als Website-mail. Daardoor kan een SDF-wijziging aan een conflict target, constraint, enum, retrycontract of trigger de Website-mailflow functioneel breken.

Het productie-incident met PostgreSQL `42P10` bewijst dat row-level productdiscriminatie geen scheiding van schema-contracten oplevert. Een gedeeltelijke unieke index is onderdeel van het callercontract. Zolang Website en SDF dezelfde businessmailtabel gebruiken, delen zij één failure domain.

## 4. Target architecture

### 4.1 Ownership

De nieuwe authority bestaat uit:

- `public.sdf_initial_confirmation_email_jobs` als enige businessstate voor nieuwe SDF initial confirmations;
- `public.prepare_sdf_initial_confirmation_v2` als idempotente producer voor een reeds geclaimde `SDF_CONFIRMATION`-workrij;
- `public.claim_sdf_initial_confirmation_email_job_v1` als delivery-lease authority;
- `public.validate_sdf_initial_confirmation_email_delivery_v1` als laatste fail-closed controle vóór provider-I/O;
- `public.complete_sdf_initial_confirmation_email_job_v1` als success-, retry- en terminal-failure authority;
- `lws_internal.advance_sdf_automation_from_initial_confirmation_v1` als SDF-specifieke projectietrigger van duurzaam `sent` naar `quote_requests.confirmation_sent_at` en de bestaande `SDF_INTAKE`-overgang.

De gedeelde SDF/Website workqueue blijft tijdelijk de dispatcher, omdat de volledige SDF-workqueuesplit expliciet buiten deze fase valt. De workqueue bezit na deze wijziging niet de SDF-mailstatus: zij plant alleen het werk. Alle maildeliverybeslissingen bevinden zich in de nieuwe SDF-authority.

`public.quote_requests` en het bestaande veld `confirmation_sent_at` blijven in deze fase de gedeelde request-root en downstream projectie. Iedere nieuwe RPC en trigger verifieert `request_kind = 'slimme_documentenflow'`; fysieke rootscheiding is een expliciete latere fase. Dit resterende rootcontract is geen mailjobauthority en rechtvaardigt geen mutatie van Website-mailobjecten.

### 4.2 Target call chain

1. Een SDF-request wordt zoals nu in `public.quote_requests` vastgelegd en als `SDF_CONFIRMATION` in de bestaande automation-workqueue opgenomen.
2. De bestaande cron en `application-intake-automation` claimen de workrij zoals nu.
3. De SDF-branch roept `public.prepare_sdf_initial_confirmation_v2(work_id, work_claim_token)` aan.
4. De producer vergrendelt de workrij en request, verifieert een geldige worklease, `request_kind = 'slimme_documentenflow'`, `record_classification = 'production'` en een nog lege `confirmation_sent_at`.
5. Voor een request zonder legacy shared confirmation maakt of herneemt de producer exact één rij in `public.sdf_initial_confirmation_email_jobs`.
6. `public.claim_sdf_initial_confirmation_email_job_v1(job_id)` claimt de due job en retourneert job-id, request-id, recipientdata, templateversie, attempt count en een nieuwe delivery lease.
7. De Edge Function controleert met `public.validate_sdf_initial_confirmation_email_delivery_v1(job_id, lease_token)` onmiddellijk vóór provider-I/O dat de lease nog geldig is.
8. `buildSdfRequestReceivedEmail` bouwt dezelfde klantinhoud als vandaag.
9. Een stateless Resend-transport verstuurt met `Idempotency-Key: sdf-initial-confirmation/{job_id}`.
10. `public.complete_sdf_initial_confirmation_email_job_v1` accepteert alleen de actuele, niet-verlopen lease en verwerkt het providerresultaat:
    - HTTP 2xx: `sent`;
    - 408, 425, 429, 5xx, timeout of netwerkfout: `retry_wait` zolang attempts resteren;
    - overige fouten of uitgeputte attempts: `failed`.
11. Een duurzame overgang naar `sent` vult `quote_requests.confirmation_sent_at` eenmalig met `coalesce(existing, sent_at)` en opent via de bestaande SDF-overgang `SDF_INTAKE` op `sent_at + 120 seconds`.
12. Een retry stelt de SDF-job en uitsluitend de SDF-workrij opnieuw beschikbaar op dezelfde `next_attempt_at`. Een terminal failure zet de SDF-workrij op `MANUAL_REVIEW`. Geen enkele failure valt terug op `public.quote_request_email_jobs`.

### 4.3 Generic shared transport

Alleen de volgende state-vrije techniek mag gedeeld blijven:

- Resend HTTP endpoint en requestmechanica;
- time-out en classificatie van HTTP/netwerkfouten;
- headernormalisatie;
- generieke payloadserialisatie;
- logging, CORS en crypto-primitives.

`supabase/functions/_shared/email-delivery.ts` is niet zo'n generieke transportlaag: deze module leest `public.quote_request_email_jobs` en roept Website/shared claim- en completion-RPC's aan. De SDF-target mag deze helper daarom niet gebruiken.

De minimale implementatie introduceert een state-vrije `sendEmailViaResend`-helper. Die helper ontvangt alleen providerconfiguratie, payload en een reeds bepaalde idempotencykey en retourneert uitsluitend een technisch resultaat. Hij leest of muteert geen database en kent geen Website- of SDF-statusmodel. Bestaande Website-callers hoeven in deze fase niet naar die helper te worden omgezet.

## 5. Data model

Conceptuele tabel: `public.sdf_initial_confirmation_email_jobs`.

| Kolom | Contract |
|---|---|
| `job_id uuid` | Primary key, default random UUID; stabiele provider-idempotency-identiteit. |
| `quote_request_id uuid` | Not null, unique, FK naar `public.quote_requests(id)` met `on delete restrict`; dit is de semantische idempotencysleutel. |
| `template_version text` | Not null en exact `SDF_REQUEST_RECEIVED_NL_BE_v1`. |
| `status text` | Not null; uitsluitend `pending`, `processing`, `retry_wait`, `sent`, `failed`; geen hergebruik van de Website-statusenum. |
| `attempt_count integer` | Not null, default 0, bereik 0 tot en met 5. |
| `max_attempts integer` | Not null, default en exact 5 voor versie 1. |
| `next_attempt_at timestamptz` | Not null; eerste delivery direct na preparation, daarna backoff. |
| `locked_at timestamptz` | Nullable observabilityveld voor de actieve claim. |
| `delivery_lease_token uuid` | Nullable; alleen gezet in `processing`. |
| `delivery_lease_expires_at timestamptz` | Nullable; alleen gezet in `processing`. |
| `sent_at timestamptz` | Nullable; verplicht zodra status `sent` is. |
| `provider_message_id text` | Nullable; providerbewijs na geaccepteerde send. |
| `last_error_code text` | Nullable, maximaal 120 tekens; leeg na claim/succes. |
| `created_at timestamptz` | Not null, server timestamp. |
| `updated_at timestamptz` | Not null, server timestamp, bijgewerkt bij iedere state transition. |

De tabel bevat geen naam, e-mailadres, aanvraagreferentie of mailbody. Claim leest deze deliverydata op het moment van verzending uit de FK-root. Daardoor ontstaat geen tweede persoonsgegevensbron.

Integriteitsregels:

- `unique (quote_request_id)` is de enige semantische unique index;
- een SDF-specifieke insertguard verifieert `request_kind = 'slimme_documentenflow'` en `record_classification = 'production'`;
- directe privileges voor `public`, `anon`, `authenticated` en `service_role` worden ingetrokken; uitsluitend security-definer RPC's muteren de tabel;
- `processing` vereist alle leasevelden; buiten `processing` zijn alle leasevelden null;
- `sent` vereist `sent_at`; andere states hebben geen nieuw `sent_at`;
- `attempt_count <= max_attempts`;
- sent jobs zijn terminal en niet opnieuw claimbaar;
- templateversie verandert nooit na creatie.

Er komt geen apart eventsysteem en geen gekopieerde requestpayload. Voor deze enkelvoudige deliverylifecycle zijn de jobstate, timestamps, errorcode en provider-id voldoende auditbewijs.

## 6. Call-chaincontracten

### 6.1 Producer

`public.prepare_sdf_initial_confirmation_v2`:

- accepteert uitsluitend een geldige `SDF_CONFIRMATION` worklease;
- vergrendelt work en request vóór de semantic-keycontrole;
- retourneert `already_sent` zonder jobmutatie wanneer `confirmation_sent_at` al bestaat;
- retourneert tijdens de compatibiliteitsperiode `legacy` wanneer voor de request al een SDF `customer_confirmation` in `public.quote_request_email_jobs` bestaat;
- maakt anders met conflict-safe insert exact één nieuwe SDF-job;
- retourneert een getypeerde authority source (`sdf_initial` of tijdelijk `legacy`) en de bestaande job-identiteit;
- maakt nooit beide jobtypen voor één request.

### 6.2 Claim

`public.claim_sdf_initial_confirmation_email_job_v1`:

- claimt alleen `pending` of due `retry_wait`;
- recyclet een verlopen `processing`-lease alleen wanneer attempts resteren;
- maakt een verlopen, uitgeputte lease terminal `failed` met `STALE_PROCESSING_LEASE_EXHAUSTED`;
- verhoogt `attempt_count` precies eenmaal per nieuwe providerpoging;
- geeft een lease van tien minuten, gelijk aan het bewezen qualification-mailpatroon;
- retourneert niets voor sent, failed, niet-due, verkeerd product of verlopen businesseligibility;
- serialiseert concurrerende claims met row locking; slechts één caller ontvangt de lease.

### 6.3 Completion en retry/fail

`public.complete_sdf_initial_confirmation_email_job_v1` is de enige automatische requeue/fail authority. De RPC vereist job-id plus actuele lease-token.

- succes zet `sent`, bewaart `sent_at` en optioneel `provider_message_id`, wist lease en error;
- retryable failure met resterende attempts zet `retry_wait`, wist lease en plant exponentiële backoff;
- non-retryable failure of attempt 5 zet `failed`, wist lease en zet de SDF-workrij op `MANUAL_REVIEW`;
- ongeldige, vervangen of verlopen lease retourneert geen completionresultaat en muteert niets;
- completion van een reeds sent job muteert niets;
- er is in versie 1 geen automatische `failed -> retry_wait`-route. Herstel vereist expliciete operationele beoordeling en een latere geautoriseerde SDF-recoveryactie.

## 7. Idempotency

De businessregel luidt: voor één SDF-request bestaat exact één semantische initial confirmation.

Dit wordt op drie niveaus afgedwongen:

1. **Producer:** `unique (quote_request_id)` plus request-row locking voorkomt meerdere SDF-jobs.
2. **Delivery:** slechts één actuele leasehouder mag versturen en completeren.
3. **Provider:** iedere poging gebruikt exact `sdf-initial-confirmation/{job_id}`. De key verandert niet bij retries, stale-lease recovery of workerrestart.

Een herhaalde automationclaim herneemt dezelfde job. Zij maakt geen nieuwe job-id en geen nieuwe provider-idempotencykey.

Na bewezen succesvolle completion is de job terminal `sent`; claim en requeue falen gesloten. Als Resend de aanvraag heeft geaccepteerd maar de worker vóór databasecompletion uitvalt, gebruikt een latere poging dezelfde provider-idempotencykey. Daardoor kan de provider dezelfde verzending herkennen in plaats van een tweede semantische mail te accepteren.

De database kan provideracceptatie niet gelijkstellen aan mailbox delivery. `sent` betekent daarom uitsluitend: Resend heeft de send met HTTP 2xx geaccepteerd en de lokale completion is duurzaam opgeslagen. Bounce/deliverywebhooks vallen buiten deze fase.

## 8. Retry- en deliverycontract

- Maximum: vijf providerpogingen per job.
- Lease: tien minuten.
- Backoff na attempt 1 tot en met 4: 30, 60, 120 en 240 seconden; de algemene formule blijft begrensd op 3600 seconden.
- Retryable: HTTP 408, 425, 429, alle 5xx-responses, timeout en netwerkfout.
- Non-retryable: overige 4xx-responses, ontbrekende providerconfiguratie, ongeldige recipientdata en template-authority mismatch.
- Stale lease: herstel naar `retry_wait` als attempts resteren; anders `failed`.
- Terminal: `failed` plus `MANUAL_REVIEW` voor de SDF-workrij.
- Provider accepted: status `sent`, `sent_at` en waar beschikbaar `provider_message_id`.
- Mailbox delivered: niet beweerd en niet door deze authority gemodelleerd.

De SDF-job bepaalt de mailretry. De nog gedeelde automation-workrij mag alleen de volgende dispatch plannen en wordt voor SDF door completion op dezelfde `next_attempt_at` vrijgegeven. Website-workrijen en Website-failurecodes worden niet gewijzigd.

## 9. Forward-only cutover

De cutover bestaat uit kleine, afzonderlijk bewijsbare stappen:

1. **Foundation:** voeg de nieuwe SDF-tabel, guards, producer-v2, claim-, validate-, completion- en projectietrigger toe. Verander geen Website-object.
2. **Contracttests lokaal:** bewijs SDF-state, leases, retries, idempotency, projectie en de negatieve cross-productmatrix.
3. **Production schema release:** release uitsluitend additive authority. De bestaande SDF producer-v1 en bestaande Edge-versie blijven aanvankelijk bruikbaar.
4. **Compatible Edge release:** laat de SDF-confirmationbranch producer-v2 en de nieuwe SDF delivery-RPC's begrijpen. Tijdens deze release ondersteunt hij tijdelijk een expliciete `legacy`-authority voor reeds bestaande shared SDF-jobs.
5. **Producer switch:** nieuwe requests zonder legacy confirmationrow maken alleen `sdf_initial`-state. Request locking en een fail-closed guard in de SDF producer-v1 voorkomen dat een oude in-flight worker naast een reeds gemaakte SDF-job alsnog een shared job creëert.
6. **Legacy drain:** verwerk pre-existing `pending`, `retry_wait` en herstelbare `processing` jobs met hun bestaande job-id en bestaande `quote-request-email/{job_id}` providerkey.
7. **Production proof:** bewijs dat requests die na de switch hun SDF-job krijgen geen `customer_confirmation` in `public.quote_request_email_jobs` hebben en dat Website-contracttests ongewijzigd slagen.
8. **Finalize:** verwijder in een latere forward-only migration uitsluitend de tijdelijke legacy-keuze uit de SDF producer nadat de actieve legacyset leeg is. Historische shared rows blijven staan. Er vindt geen destructieve cleanup plaats.

Het serialisatiecontract tijdens stap 5 is verplicht: zowel producer-v1 als producer-v2 vergrendelen dezelfde `quote_requests`-rij en producer-v1 weigert een shared SDF-job te creëren als de nieuwe SDF-job al bestaat. Bij twijfel retourneert de oude route geen deliveryauthority; zij creëert nooit een tweede job.

## 10. Existing-data policy

Voor bestaande SDF `customer_confirmation`-rows in `public.quote_request_email_jobs` geldt:

| Bestaande status | Beleid |
|---|---|
| `sent` | Historisch bewijs blijft ongewijzigd. Niet kopiëren en nooit opnieuw verzenden. `quote_requests.confirmation_sent_at` moet reeds gevuld zijn; inconsistentie veroorzaakt een release-hard-stop en afzonderlijke datacorrectie. |
| `pending` | Blijft legacy en wordt met dezelfde job-id en providerkey via de bestaande deliveryauthority afgehandeld. Geen nieuwe SDF-job voor dezelfde request. |
| `retry_wait` | Zelfde beleid als pending; bestaande attempt count, due time en providerkey blijven leidend. |
| `processing` | De bestaande stale-recoverysemantiek voltooit of herneemt de job met dezelfde providerkey. Geen parallelle SDF-job. |
| `failed` | Blijft terminal historisch bewijs. Geen automatische migratie of resend. De request gaat naar manual review; expliciet providerbewijs is vereist vóór een afzonderlijke forward recovery. |

Er worden geen bestaande rows verplaatst, verwijderd of inhoudelijk herschreven. De aanwezigheid van een legacy SDF confirmationrow is tijdens de drain de exclusieve routekeuze. Daardoor kan een request nooit gelijktijdig een legacy en een nieuwe confirmationjob bezitten.

Voor productieactivatie worden read-only preflighttellingen per status vastgelegd. Finalization is alleen toegestaan wanneer er geen SDF legacy rows in `pending`, `retry_wait` of `processing` meer bestaan en geen pre-cutover `SDF_CONFIRMATION`-workrij zonder bijbehorende authority resteert.

Legacy `failed` rows blokkeren automatische heropening: hun bijbehorende workrij moet aantoonbaar terminal `MANUAL_REVIEW` blijven. Finalization mag deze rows historisch laten staan, maar iedere toekomstige recovery moet een expliciete SDF-specifieke operationele handeling zijn die eerst providerbewijs beoordeelt; een generieke workqueue-retry mag niet stilzwijgend een nieuwe job naast zo'n failed legacy row maken.

## 11. Failure en recovery

- Een fout in de nieuwe SDF-authority raakt uitsluitend de SDF-job en de SDF-workrij.
- Er bestaat geen runtimefallback die een nieuwe row in `public.quote_request_email_jobs` maakt.
- Een niet-classificeerbaar authorityresultaat, ongeldige templateversie, verlopen lease of ongeldige requestkind faalt gesloten vóór provider-I/O.
- Retryable providerfouten blijven in de nieuwe SDF-tabel.
- Terminal failures gaan naar manual review; zij schakelen niet terug naar Website-businessstate.
- Schema rollback is niet voorzien. Herstel gebeurt met een nieuwe forward-only migration of door de nieuwe SDF producer tijdelijk fail-closed te zetten.
- Website blijft tijdens SDF-recovery operationeel op haar bestaande authority.

## 12. Testontwerp

### 12.1 Positieve contracttests

A. **Website customer confirmation preservation**
De bestaande approvalflow maakt exact één `customer_confirmation` in `public.quote_request_email_jobs`; bestaande template-, retry- en completionsemantiek blijven gelijk.

B. **SDF authority location**
Een due SDF confirmation maakt exact één rij in `public.sdf_initial_confirmation_email_jobs` met de canonieke templateversie.

C. **Geen shared SDF job**
Voor dezelfde nieuwe SDF-request blijft het aantal `customer_confirmation`-rows in `public.quote_request_email_jobs` nul.

D. **SDF retry-idempotency**
Herhaalde preparation, concurrerende claims, retryable completion en stale-lease recovery behouden dezelfde job-id, semantic key en provider-idempotencykey.

E. **Website retry-isolatie**
Website claim/retry/completion muteert geen rij in `public.sdf_initial_confirmation_email_jobs`.

F. **SDF schema-isolatie van Website**
Een wijziging of negatieve fixture tegen een SDF-only check/index kan de bestaande Website job creation en `transition_quote_request_review` niet raken, omdat geen Website-callsite de SDF-tabel adresseert.

G. **Website schema-isolatie van SDF**
Een Website-only index/constraintfixture op `public.quote_request_email_jobs` verandert de uitkomst van SDF preparation, claim en completion niet.

H. **Stateless transport**
De transportunit test gebruikt een fake endpoint en bewijst dat transport geen databaseclient accepteert, geen RPC aanroept en alleen technisch providerresultaat retourneert.

Aanvullende tests bewijzen:

- alleen production SDF-requests zijn geldig;
- de unieke requestkey houdt stand onder concurrency;
- één van twee gelijktijdige claims wint;
- een fout lease-token en een verlopen lease kunnen niet completeren;
- attempt 5 wordt terminal;
- success projecteert `confirmation_sent_at` exact eenmaal;
- de bestaande qualification-uitnodiging wordt exact op `sent_at + 120 seconds` vrijgegeven;
- provider HTTP 2xx betekent accepted, niet mailbox delivered;
- template mismatch veroorzaakt nul providercalls.

### 12.2 Verplichte negatieve cross-producttests

1. **SDF mutation -> Website unchanged**
Snapshot alle Website-rows in `public.quote_request_email_jobs`; prepare, claim, retry en complete een SDF initial confirmation; vergelijk de Website-snapshot byte-equivalent en bewijs nul nieuwe shared SDF confirmationrows.

2. **Website mutation -> SDF unchanged**
Snapshot `public.sdf_initial_confirmation_email_jobs`; voer Website review, confirmationclaim en completion uit; bewijs dat count en rowinhoud identiek blijven.

3. **SDF failure/retry -> Website queue unchanged**
Forceer een retryable en daarna terminal SDF-fout; bewijs dat geen status, attempt count, due time, lock of errorveld in Website-jobs verandert.

4. **Website failure/retry -> SDF authority unchanged**
Forceer Website requeue/completion; bewijs dat de SDF-jobstatus, attempts, lease en timestamps niet veranderen.

5. **Cross-product identifier rejection**
Roep iedere SDF RPC aan met een Website request/job en iedere bestaande Website RPC met een SDF new-authority job-id. Beide richtingen retourneren geen authority en muteren niets.

6. **Independent conflict targets**
Inspecteer de catalogus en bewijs dat de SDF semantic unique index uitsluitend op de SDF-tabel staat en geen Website UPSERT deze index als conflict target gebruikt; bewijs ook het omgekeerde.

7. **Concurrency isolation**
Laat parallel een Website confirmation en SDF confirmation ontstaan en completeren. Beide krijgen hun eigen job-id, tabel, lease en providerkey zonder lock- of unique-indexinteractie.

## 13. Voorgestelde minimale filescope

Geen van deze files wordt in de designfase gewijzigd.

| Classificatie | Bestand | Latere verantwoordelijkheid |
|---|---|---|
| NEW | `supabase/migrations/20260901040000_add_sdf_initial_confirmation_email_authority_v1.sql` | Additive SDF-tabel, guards, producer-v2, claim/validate/complete, sent-projectie en tijdelijke legacy-safe producer-v1 guard. |
| NEW | `supabase/migrations/20260901050000_finalize_sdf_initial_confirmation_email_cutover_v1.sql` | Pas na production drain: verwijdert de tijdelijke legacy-keuze uit de SDF-producer; geen row cleanup. Niet tegelijk met foundation releasen. |
| MODIFY | `supabase/functions/application-intake-automation/index.ts` | SDF confirmation gebruikt SDF RPC's en stateless transport; Website branch blijft inhoudelijk ongewijzigd. |
| NEW | `supabase/functions/_shared/resend-transport.ts` | Stateless provider-I/O zonder database- of productstate. |
| TEST | `supabase/functions/_shared/resend-transport.test.ts` | Providerresponse-, retryclassificatie-, timeout- en idempotencyheadercontract. |
| TEST | `supabase/functions/application-intake-automation/handler.test.ts` | SDF authority dispatch en fail-closed resultaten; bestaande Website assertions blijven behouden. |
| TEST | `supabase/tests/sdf_initial_confirmation_email_authority_v1.sql` | Data model, RPC, idempotency, lease, retry, projection en cross-product preservation. |
| TEST | `supabase/tests/sdf_qualification_automation_bridge_v1.sql` | Bestaande assertions die de oude shared SDF confirmation expliciet voorschrijven vervangen door de nieuwe authority; qualificationgedrag blijft gelijk. |
| TEST | `scripts/sdf-initial-confirmation-email-concurrency.integration.cjs` | Parallelle prepare/claim/completion en duplicate-prevention. |

De finalizationmigration wordt pas geschreven en gereleased nadat production evidence aan haar precondities voldoet. Zij behoort tot dezelfde architectuurlijke cutover, maar niet tot de eerste additive release.

## 14. Acceptance criteria

De implementation phase is pas gereed wanneer alle volgende punten waar zijn:

1. Nieuwe SDF initial confirmations hebben exact één row in `public.sdf_initial_confirmation_email_jobs`.
2. Voor die requests bestaat geen SDF `customer_confirmation` in `public.quote_request_email_jobs`.
3. Website maakt, claimt, retriet en completeert mails exact zoals vóór de wijziging.
4. SDF preparation en retries kunnen geen Website-mailrow muteren.
5. Website-mailmutaties kunnen geen SDF initial-confirmationrow muteren.
6. De SDF semantic key is `quote_request_id` en is database-unique.
7. Iedere providerretry gebruikt dezelfde `sdf-initial-confirmation/{job_id}` key.
8. Alleen een actuele SDF deliverylease kan versturen en completeren.
9. Vijf mislukte pogingen eindigen fail-closed in `failed` en `MANUAL_REVIEW`.
10. Succes projecteert `confirmation_sent_at` en opent de bestaande qualification-uitnodiging zonder duplicate overgang.
11. Legacy active jobs draineren met hun oorspronkelijke job-id/providerkey en krijgen nooit een parallelle nieuwe job.
12. Historische sent/failed shared rows blijven behouden.
13. Geen Website-tabel, Website-index, Website-constraint of Website-RPC is voor de target herschreven.
14. Alle positieve, negatieve cross-product- en concurrencytests slagen.
15. Read-only productiecontrole bewijst na switch nul nieuwe shared SDF confirmationrows.

## 15. Expliciete non-goals

Deze boundary ontwerpt of implementeert niet:

- een volledige SDF-workqueuesplit;
- een aparte SDF-cron;
- een aparte SDF automation Edge Function;
- een operator-gatewaysplit;
- een customer-request-coresplit;
- een fysieke splitsing van `public.quote_requests`;
- wijzigingen aan Website review, approval, intake, reminders, quotation of acceptance;
- mailbox-delivery/bouncewebhooks;
- Offerte voorbereiden;
- Budget Guard;
- EMAIL-2B;
- destructieve cleanup van legacy mailrows.

## Self-review

- Geen open placeholders aanwezig.
- De tablekeuze en lifecycle-owner zijn eenduidig.
- Website-businessstate wordt niet hergebruikt voor nieuwe SDF initial confirmations.
- De tijdelijke legacyroute is alleen voor bestaande rows en creëert geen nieuwe cross-product fallback.
- De nieuwe SDF-tabel mengt geen qualification-intakebusinessstate.
- De cutover is additive, forward-only en gefaseerd.
- Duplicate ownership wordt door één requestkey en een exclusieve legacy/new route voorkomen.
- De eerste release vereist geen destructieve cleanup.
- De scope blijft beperkt tot de initial SDF confirmation mailauthority.