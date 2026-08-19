# DEMO-MOBILE-02 Cafe Date/Time Checkpoint

Status date: 2026-08-19

## Authority And Scope

- True remote main, `origin/main`, and successful Pages SHA: `0873fc5431a85e440068d2b7257262c518939e89`.
- Pages deployment: `5976456626`, state `success`.
- Branch: `fix/demo-mobile-02-cafe-datetime-20260819`.
- Branch start HEAD and merge-base: exact production authority.
- Initial staged, unstaged, untracked: `0/0/0`.
- Functional scope: Cafe Amber `input[type="date"]` and `input[type="time"]` only.

## Root Cause And Fix

Cafe date/time controls had only physical `width: 100%`. In iPhone/WebKit they remained native `display: flex` controls with `min-width` and `min-inline-size` set to `auto`, and no maximum width. Although headless outer boxes fit, the physical Safari native shadow control can extend beyond the intended inline boundary.

Inside the existing `max-width: 640px` Cafe breakpoint, only date/time controls now use `display: block`, `inline-size: 100%`, `min-inline-size: 0`, and `max-inline-size: 100%`. Native `appearance: auto`, date picker, and time picker remain intact. No other field, CTA, navigation, content, or layout rule changed.

## Validation

| Viewport | Date | Time | Native values | Other fields | Horizontal overflow | Footer/page end | Errors |
|---|---|---|---|---|---:|---|---:|
| `375x667` | contained | contained | pass | unchanged | 0 | exact | 0 |
| `390x844` | contained | contained | pass | unchanged | 0 | exact | 0 |
| `430x932` | contained | contained | pass | unchanged | 0 | exact | 0 |
| `768x1024` | contained, original flex | contained, original flex | pass | unchanged | 0 | exact | 0 |
| `1440x900` | contained, original flex | contained, original flex | pass | unchanged | 0 | exact | 0 |

- Navigation: pass at all viewports.
- Cafe CTA computed state: unchanged by the patch.
- Cafe images: `11/11` loaded.
- Normal vertical scrolling: pass.
- GLOBAL-MOBILE-01B: preserved; `assets/css/cookie-consent.css` unchanged.
- Restaurant final CSS: unchanged.
- Other demo, intake, pricing, operator, and Supabase changes: `0`.

## Release Status

- Local commit: the commit containing this checkpoint, subject `fix: contain Cafe mobile date and time fields`.
- Pushes: `0`.
- Deployments: `0`.
- Production changed: no.
