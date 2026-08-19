# GLOBAL-MOBILE-01B iPhone Safari Checkpoint

Status date: 2026-08-19

## Production Authority

- True remote `main`: `5592804b7c3c6b5e347ec0946bcf3ef552e92c2c`.
- GitHub Pages production SHA: `5592804b7c3c6b5e347ec0946bcf3ef552e92c2c`.
- Pages deployment: `5959625202`, state `success`.
- Forward-only branch: `fix/global-mobile-page-end-20260819`.
- Branch start HEAD: RELEASE-01 governance commit `b9aec033daaff2631e43cdcad20a8ef08c13b60b`.
- Merge-base with `origin/main`: exact production authority `5592804b...`.
- Original dirty main worktree was not used or changed.

## Proven Root Cause

The physical iPhone behavior is authoritative: iOS Safari permits elastic root overscroll beyond the bottom scroll boundary. The site had no `overscroll-behavior` boundary on either possible root scroll container. During that compositor-level rubber-band movement, Safari exposes the light page/root canvas after the visually completed footer. This is category B with a visible category-C consequence: iOS overscroll/rubber-band canvas plus the page background visible outside normal document flow.

It is not extra DOM height. On every representative production route:

- `documentElement.scrollHeight == body.scrollHeight`;
- the real footer ends at `documentElement.scrollHeight`;
- no normal-flow direct body child ends below the footer;
- elements after the footer are only shared cookie UI: a fixed consent banner and a fixed hidden modal;
- there is no shared viewport-height JavaScript, spacer, sentinel, absolute element, transform, pseudo-element, or min-height extending the page end;
- root overscroll remained at its default `auto`/`visible` behavior.

## Why Headless WebKit Was False-Negative

Headless automation measures layout scroll range but does not simulate physical iOS rubber-band/compositor movement beyond that range. Therefore `footerBottom == scrollHeight` is expected both before and after this fix and does not contradict the device evidence.

The installed Playwright Windows-WebKit 26.5 port also reports `CSS.supports("overscroll-behavior-y", "none") == false`, while current MDN compatibility data records Safari and iOS Safari support for `none` from Safari 16. This makes the Windows port suitable for layout regression, but not for validating this iOS-specific interaction. A supporting Chromium engine was used to prove media-query activation and computed values. A physical iPhone remains the final interaction authority.

## Direct Body-Child Trace

Representative route structure at `390x844`:

| Route | In-flow end | Children after footer | Position / contribution |
|---|---|---|---|
| Homepage | `.preview-footer` | cookie banner, cookie modal | fixed; modal hidden; 0 layout height contribution |
| Luna | `.luna-footer` | cookie banner, cookie modal | fixed; modal hidden; 0 layout height contribution |
| Cafe Amber | `.cafe-footer` | back-to-top, booking UI, cookie UI | fixed/hidden; 0 layout height contribution |
| Restaurant | `.site-footer` | mobile CTA, back-to-top, booking UI, cookie UI | fixed/hidden; 0 layout height contribution |
| Aurelis | `.aurelis-footer` | cookie banner, cookie modal | fixed; modal hidden; 0 layout height contribution |

Headers are fixed or sticky according to each design. Main and footer remain the final normal-flow contributors. No traced child provides a shared extra bottom extent.

## Minimal Fix

`assets/css/cookie-consent.css` is the existing stylesheet loaded by the homepage and all representative demos. In coarse-pointer/no-hover contexts it now sets:

```css
html,
body {
  overscroll-behavior-y: none;
}
```

Both elements are covered because some routes use the root as scroller while routes with `overflow-x: hidden` expose body as the effective scroll container. The rule does not set `overflow: hidden`, does not alter height, does not clip content, and does not disable normal vertical scrolling. Desktop remains outside the media query.

## Before Measurements

Production WebKit, iPhone-style context, `390x844`:

| Route | innerHeight | document/body height | maximum scrollY | footer bottom | layout tail | horizontal overflow |
|---|---:|---:|---:|---:|---:|---:|
| Homepage | 844 | 12868 | 12024 | 12868 | 0 | 0 |
| Luna | 844 | 14659 | 13815 | 14659 | 0 | 0 |
| Cafe Amber | 844 | 12943 | 12099 | 12943 | 0 | 0 |
| Restaurant | 844 | 10405 | 9561 | 10405 | 0 | 0 |
| Aurelis | 844 | 6186 | 5104 | 6186 | 0 | 0 |

These zero layout tails isolate the device-only movement outside the layout scroll range.

## After Test Matrix

Local isolated worktree, iPhone-style WebKit contexts:

| Viewport | Routes | Footer equals document end | Horizontal overflow | Console/page errors |
|---|---:|---:|---:|---:|
| `390x844` | 5 | 5/5 | 0 on 5/5 | 0 |
| `375x667` | 5 | 5/5 | 0 on 5/5 | 0 |
| `430x932` | 5 | 5/5 | 0 on 5/5 | 0 |

Across all 15 cases, `innerHeight == visualViewport.height == clientHeight`, `documentElement.scrollHeight == body.scrollHeight`, and layout tail remained 0. Normal page height and footer reachability were preserved.

Supporting Chromium activation test at `390x844`:

- coarse-pointer media query: matched;
- `CSS.supports`: true;
- computed `html` and `body` `overscroll-behavior-y`: `none`;
- footer/document tail: 0;
- horizontal overflow: 0.

Desktop homepage at `1440x900`:

- coarse-pointer media query: not matched;
- computed `html` and `body` overscroll behavior: `auto`;
- document and body height: `10629`;
- footer bottom: `10629`;
- horizontal overflow: 0;
- console/page errors: 0.

Production artifact check:

- `assets/css/cookie-consent.css` is explicitly present in the existing `prepare-pages-dist.ps1` required-file allowlist;
- the locally copied dist stylesheet contains `overscroll-behavior-y: none`;
- full `verify-pages-dist.ps1` execution was blocked because the production builder requires `LWS_SUPABASE_PUBLISHABLE_KEY` for its unrelated operator-auth config step;
- no key was requested, exposed, substituted, or changed, and no operator file was modified.

## Changed Files And Release Status

- `assets/css/cookie-consent.css`: shared mobile root overscroll boundary.
- `.release/scopes/GLOBAL-MOBILE-01B.json`: explicit release scope.
- `docs/GLOBAL-MOBILE-01B-IPHONE-SAFARI-CHECKPOINT-20260819.md`: this checkpoint.
- Local commit: the commit containing this checkpoint, subject `fix: prevent iPhone page-end overscroll`.
- Pushes: 0.
- Deployments: 0.
- Production changed: no.

## Remaining Uncertainty And Exact Next Step

The headless matrix proves no layout regression and a standards-supporting engine proves rule activation. It cannot physically reproduce iOS rubber-band. Before any production push, publish only through a separately approved review path or controlled deployment and verify on the same physical iPhone/Safari that previously showed the bug. Confirm normal scroll, footer reachability, no white tail, navigation/CTA operation, and both portrait and orientation-change behavior. Safari/iOS versions older than 16 do not support this standards-based fix and require an explicit compatibility decision rather than an overflow lock.

Explicitly out of scope and not addressed:

- Restaurant Demo mobile text/layout;
- Restaurant reservation form overflow;
- Cafe Amber form/CTA overlap;
- demo image cropping;
- intake page 9 date-field overflow;
- intake page length/restructuring;
- pricing, operator flow, documentenflow, and demo redesign work.