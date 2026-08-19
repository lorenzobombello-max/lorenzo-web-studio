# DEMO-MOBILE-01 Restaurant Checkpoint

Status date: 2026-08-19

## Production Authority

- True remote `main`: `1bc8a72c48871e402613da748be36341399a26fb`.
- Fetched `origin/main`: `1bc8a72c48871e402613da748be36341399a26fb`.
- GitHub Pages SHA: `1bc8a72c48871e402613da748be36341399a26fb`.
- Pages deployment: `5975972911`, state `success`.
- Branch: `fix/demo-mobile-01-restaurant-20260819`.
- Branch start HEAD and merge-base: exact production authority `1bc8a72c...`.
- Initial staged, unstaged, and untracked counts: `0/0/0`.
- Source: new isolated worktree from current remote main; no old branch, worktree, backup, or historical Restaurant version was used.

## Root Causes And Fixes

### Reservation Layout

The desktop rule `.restaurant-demo #reservatie .restaurant-reservation-grid` used an ID and therefore outranked the lower-specificity mobile rule. At `375x667`, the section remained `146.6px + 179.2px`; at `390x844`, `152.8px + 186.8px`; at `430x932`, `169.4px + 207px`. Text and form were forced into desktop columns.

The existing `max-width: 1020px` mobile stack now includes the same `#reservatie` specificity. The section becomes one full-width column without changing desktop.

### Form Control Overflow

Native controls, especially date/time, retained an intrinsic width of approximately `171px`. In the compressed card they extended `14px` beyond the card at `375px` and `6px` at `390px`.

Below `820px`, the reservation form, fields, inputs, selects, textareas, and button now use `min-width: 0` and `max-width: 100%`. All controls remain inside the card in Chromium and WebKit.

### Fixed CTA Overlap

The duplicate `.restaurant-mobile-action` occupied nearly the full viewport width at the bottom. Controlled scroll tests proved intersections with time, email, textarea, or submit controls at every required mobile viewport.

Below `820px`, this duplicate fixed CTA is hidden. Existing hero, navigation, and in-page reservation links remain available. No HTML or JavaScript behavior changed. The existing back-to-top control and mobile navigation remain functional and did not overlap reservation controls in centered-control tests.

### Portrait Cropping

The second story image is a `1122x1402` portrait (`4:5`) but inherited the shared `4:3` landscape box with centered `object-fit: cover`, exposing only about 60% of its vertical source and risking head cropping.

Below `820px`, only `.restaurant-story-media img:nth-child(2)` uses `height: auto`, source-matching `aspect-ratio: 4 / 5`, and `object-position: center top`. No image was replaced and desktop cropping remains unchanged.

## Changed Files

- `assets/css/demos/restaurant.css` - Restaurant-only responsive fixes.
- `.release/scopes/DEMO-MOBILE-01-RESTAURANT.json` - explicit release scope.
- `docs/DEMO-MOBILE-01-RESTAURANT-CHECKPOINT-20260819.md` - this checkpoint.

No shared CSS/JS, Restaurant HTML/JS, other demo, intake, pricing, operator, documentenflow, or Supabase path changed.

## Mobile Test Matrix

Chromium and WebKit local isolated-worktree results:

| Viewport | Reservation | Controls | Fixed reservation CTA | Portrait | Horizontal overflow | Footer/page end | Console/page errors |
|---|---|---|---|---|---:|---|---:|
| `375x667` | one column, 345px | contained | hidden; overlap 0 | `4:5`, top focus | 0 | exact | 0 |
| `390x844` | one column, 359px | contained | hidden; overlap 0 | `4:5`, top focus | 0 | exact | 0 |
| `430x932` | one column, 396px | contained | hidden; overlap 0 | `4:5`, top focus | 0 | exact | 0 |

All three retain normal vertical document scroll. WebKit native date/time controls remain within the form container.

## Tablet And Desktop Regression

| Viewport | Reservation | Form | Portrait behavior | Horizontal overflow | Footer/page end | Console/page errors |
|---|---|---|---:|---:|---|---:|
| Tablet `768x1024` | intended one column | intended one column; contained | mobile `4:5` treatment | 0 | exact | 0 |
| Desktop `1440x900` | original two columns (`519px / 635px`) | original two columns (`280px / 280px`) | original desktop crop | 0 | exact | 0 |

The top-to-bottom walkthrough covered header/navigation, hero, menu cards, reservation copy/form, story imagery, gallery, reviews, hours, contact form, final CTA, and footer. All nine Restaurant content images loaded. No element crossed the viewport and heading glyphs remained visible; minor line-box overhang is intentional typography with `overflow: visible`, not clipping.

## GLOBAL-MOBILE-01B Regression

- `assets/css/cookie-consent.css` diff against production: `0`.
- Local and production blob: `722f3889a127249d5f14bfdba5fe2e19886b4499`.
- `overscroll-behavior-y: none` remains present.
- Restaurant normal vertical scroll: pass.
- Footer bottom equals document height at all five tested viewports.
- Horizontal overflow: `0`.
- The physically accepted global fix was not edited, overwritten, or reverted.

## Git And Release Status

- Corrected pre-stage RELEASE-01 contract check with explicit array coercion: `PASS`, all violation counts `0`; the unmodified guard's singleton string concatenation produced one false unexpected path before staging.
- Unmodified RELEASE-01 guard after staging: `PASS`, unexpected files `0`, protected unexpected changes `0`, generated violations `0`, untracked files `0`, and `git diff --check` passed.
- Local commit: the commit containing this checkpoint, subject `fix: remediate Restaurant demo mobile layout`.
- Pushes: `0`.
- Deployments: `0`.
- Production changed by this task: no.

## Deferred Work

Explicitly not performed:

- Cafe Amber mobile remediation;
- other demo mobile/cropping audit;
- intake restructuring or pricing audit;
- operator or documentenflow work.
