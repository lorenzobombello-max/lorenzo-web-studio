# Lorenzo Web Solutions

Lorenzo Web Solutions is a static website studio focused on professional business websites and sector-specific demo experiences. The public frontend is supported by a secure Supabase workflow for quote requests, review, email delivery, and customer intake.

## Project structure
- `index.html`: public homepage
- `pages/`: public content, quote, review, intake, and demo pages
- `assets/`: shared and demo-specific CSS, JavaScript, icons, and images
- `scripts/`: GitHub Pages artifact preparation and verification
- `supabase/functions/`: Edge Functions and shared backend modules
- `supabase/migrations/`: PostgreSQL schema, constraints, and security changes

## Technology
- Frontend: static HTML, CSS, and JavaScript
- Hosting: GitHub Pages
- Backend: Supabase Edge Functions and PostgreSQL

## Public architecture
The main site and supporting pages share common assets. Sector demos live under `pages/demos/` and use dedicated styles and media while remaining part of the same static deployment.

At a high level, the quote workflow accepts a validated request, sends an admin notification, supports approval or rejection, and sends a customer confirmation after approval. An approved request can receive a personal intake invitation. The intake supports server-side draft save and restore, final submission, and a read-only submitted state.

## Local development
Serve the repository root with a static HTTP server and open `index.html`. For example:

```powershell
python -m http.server 4173
```

Backend-dependent flows require the configured Supabase project and are not emulated by the static server.

## Deployment
Pushes to `main` trigger `.github/workflows/deploy-pages.yml`. The workflow creates an allowlisted artifact with `scripts/prepare-pages-dist.ps1`, verifies its contents and local links with `scripts/verify-pages-dist.ps1`, and deploys the result to GitHub Pages.

## Technical baseline
The current production architecture, database constraints, function versions, security model, and validation status are documented in [docs/PRODUCTION-BASELINE.md](docs/PRODUCTION-BASELINE.md).

Production status on 2026-08-09: the business-customer flow, local Belgian enterprise-number validation, server-side VIES validation, review/intake propagation, and conditional briefing/PDF output are live at commit `21d65e6dad1d64bdbc9cdd43706585d579a5da14`. The privacy flow and published legal pages remain intact.

## Security documentation policy
Never place secrets, raw tokens, private capabilities, service-role credentials, or private environment values in repository documentation. Internal governance and operational secrets remain outside this public repository.
