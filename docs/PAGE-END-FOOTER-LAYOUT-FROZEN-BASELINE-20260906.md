# Frozen page-end/footer layout baseline

Status: **FROZEN**
Date: 2026-09-06

## Contract

- The final `body footer` is the real page end.
- Meaningless vertical space after that footer may not exceed 1 CSS pixel (rounding tolerance).
- Public pages may not produce actionable horizontal document scrolling.
- The baseline applies at 1440 px, 390 px, and 320 px with normal and reduced motion.
- New demo directories must be added to the audited route inventory.

## Covered routes

The home page, portfolio, and every source demo under `pages/demos/` are covered. Operator, Auth, SDF, recruitment, generated distributions, and Supabase are outside this baseline.

## Required gate

Run before approving any demo, portfolio, or public layout change:

```powershell
npm run test:page-end
```

The gate is implemented in `scripts/page-end-footer.test.mjs`. Do not weaken its footer tolerance, viewport matrix, motion matrix, horizontal-scroll assertion, or automatic demo inventory check without owner approval.