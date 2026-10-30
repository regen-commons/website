# Public website polish verification

The public font and Join/navigation changes run independently of the steward
dashboard on `codex/public-fonts-join-navigation`, initially based on main `ebd8aab` and integrated with `a1908e6` after dashboard PR #4 merged.
The target is 100 for performance, accessibility, best practices, and SEO on
Home, Learn, Map, Seeds, and Join, on both mobile and desktop. Admin remains
private and intentionally excluded from the SEO target.

## Changed behavior

- Public pages load licensed fonts from this repository. Critical display faces
  are preloaded; optional font display prevents a late swap. Slow first visits
  may keep a metric-adjusted fallback for that navigation. See the
  [font provenance and policy](../assets/fonts/README.md).
- Join validates required fields, email, and optional supplied web addresses
  before advancing. Errors include text and accessible descriptions. Focus moves
  to the first invalid control, each new step heading, and the confirmation.
  Enter advances the current step; Back retains answers. The viewport follows
  the form step rather than returning to the long introduction.
- Navigation links have accessible names and clean URLs. Closed mobile navigation
  is inert; opening it focuses a link, Escape restores the toggle, and tabbing
  into page content closes it. The fixed header has a solid background.
- Learn progress controls are named buttons with larger targets. Previous/Next
  also work on mobile; inactive panels are inert. Arrow keys preserve text
  editing. Seed previews support keyboard focus and tapping.
- Public pages include skip links, main landmarks, descriptions, a favicon, and
  improved muted-text contrast. Above-the-fold text no longer waits for entrance
  fades. The home scroll prompt is visible immediately and pulses only on hover or
  keyboard focus, respecting reduced motion. Local serving preserves font bytes
  and supports gzip text delivery.

## Automated verification

`npm run check`, all 30 `npm test` cases, and `npm run smoke` pass. Checks cover
clean routes/public allowlisting, exact binary font serving, gzip negotiation,
and the existing seed, map, application, and steward fixture contracts. Smoke
covers six pages and actual handlers with synthetic provider transport.

## Rendered local verification

Checked with the in-app browser at 390 × 844 and 1365 × 900:

| Flow | Result |
| --- | --- |
| Join Continue with blank required fields | Stays on step one; text errors appear and the first invalid field receives focus |
| Invalid email / supplied invalid URL | Rejected before advancing; useful correction text appears |
| Join Enter and Back | Advances one step; Back preserves the previous answers |
| Join all six steps on mobile | New heading and fields remain in view, instead of returning to the introduction |
| Required radio group and alternate option | Missing choice is rejected; a valid alternate choice advances |
| Synthetic Join submission | Confirmation is shown and focused |
| Local 503 followed by Join retry | Responses and retry remain available; retry reaches confirmation |
| Mobile menu | Named links, expanded state, initial focus, Escape close and restored toggle focus verified |
| Learn direct `/learn#plant` | Opens the offering panel |
| Learn textarea Left/Right on mobile and desktop | Text editing stays on panel seven; the panel does not change |
| Learn progress and arrows | Active panel and disabled boundaries update; offscreen panels leave the accessibility tree |
| Learn seed preview | Keyboard focus/click exposes the vision without relying on hover; mobile light-theme preview also checked |

All submissions used synthetic local data. No live applications were sent.

## Lighthouse method and results

| Page | Device | Performance | Accessibility | Best practices | SEO | LCP | CLS |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Home | mobile | 100 | 100 | 100 | 100 | 1.39 s | 0 |
| Learn | mobile | 100 | 100 | 100 | 100 | 1.33 s | 0 |
| Map | mobile | 100 | 100 | 100 | 100 | 1.17 s | 0 |
| Seeds | mobile | 100 | 100 | 100 | 100 | 1.26 s | 0 |
| Join | mobile | 100 | 100 | 100 | 100 | 1.21 s | 0 |
| Home | desktop | 100 | 100 | 100 | 100 | 0.34 s | 0 |
| Learn | desktop | 100 | 100 | 100 | 100 | 0.33 s | 0 |
| Map | desktop | 100 | 100 | 100 | 100 | 0.33 s | 0 |
| Seeds | desktop | 100 | 100 | 100 | 100 | 0.34 s | 0 |
| Join | desktop | 100 | 100 | 100 | 100 | 0.37 s | 0 |

The final integrated matrix reaches 100 in every category on all ten page/device
combinations. All ten measured zero CLS and zero TBT. After making the home
scroll prompt immediately visible, three consecutive desktop Home audits scored
100. Seven 36px seed-preview buttons were also verified without overlapping at
390px and after resizing to desktop.

Earlier repeated desktop Home and Map runs scored 99 performance; those reports
remain in the artifacts. Keep that variation visible rather than treating a
100 as a guarantee for every run, device, or dataset.

Separate actual-throttling diagnostics for Home, captured before integrating
dashboard PR #4's token extraction, measured:

| Font scenario | Performance | Accessibility / best practices / SEO | LCP | CLS | TBT |
| --- | ---: | --- | ---: | ---: | ---: |
| Fonts available, DevTools throttling | 98 | 100 / 100 / 100 | 1.75 s | 0 | 0 ms |
| Font requests blocked, DevTools throttling | 99 | 100 / 100 / 100 | 1.53 s | 0 | 0 ms |

These use real network/CPU throttling rather than the standard simulated score
model, so compare them as separate diagnostics. The available-font trace painted
at 1.75 s; its display font responses finished at 1.79–1.98 s. The browser kept
the fallback for that slow first navigation, as intended by optional display.
Filmstrip frames at 2.37 s and 9.47 s retained the same title/body line breaks;
there was no late text rewrap. Blocking all font URLs still produced readable
text and zero layout shift. This proves stable fallback behavior, not that the
brand face always appears on a slow cold visit.

The raw HTML/JSON reports, font traces, filmstrips, source SHA-256 fingerprints,
and test output are in local ignored `artifacts/public-polish/`. `index.html`
there links the reports. Earlier passes are retained under `initial/`,
`compressed-pass/`, `prior-refinement/`, and `pre-main-integration/` rather
than discarded.

Lighthouse 13.6.0, Chromium 156, Node 22.22.1. Mobile uses Lighthouse's default
simulated mobile throttling; desktop uses `--preset=desktop`. Audits run serially
with fresh Chrome storage against the local fixture server on port 3505. All four
standard categories are enabled. The synthetic-data banner remains visible and
no score filters or audit exclusions are used.

The fixture server originally transferred CSS without compression. This produced
mobile performance 97–98 after the UI fixes. It now negotiates gzip for static
text, matching the deployed site's observed `Content-Encoding: gzip` response
for `https://regencommons.com/style.css` on 2026-10-30 UTC. Fonts remain unchanged
compressed binary files. This improves local measurement fidelity; it is not
additional evidence of production improvement.

To repeat one audit after starting `PORT=3505 npm run dev` and installing Chrome:

```sh
mkdir -p artifacts/public-polish
npx --yes lighthouse@13.6.0 http://127.0.0.1:3505/ \
  --chrome-flags='--headless=new' \
  --only-categories=performance,accessibility,best-practices,seo \
  --output=json --output=html \
  --output-path=artifacts/public-polish/home-mobile
```

Repeat for `/learn`, `/map`, `/seeds`, and `/join`; add `--preset=desktop` for the
five desktop reports. Set `CHROME_PATH` if Chrome is outside a standard location.
Keep reports in ignored `artifacts/`. To inspect real throttled font loading, use
`--throttling-method=devtools --save-assets`; to check fallback loading, also use
`--blocked-url-patterns='*/assets/fonts/*'` in a separate run.

## Limits and follow-up

Scores describe local synthetic data, the default theme, and each page's initial
state. They do not prove every interaction accessible or performance with the
complete live map dataset. Continue canvas text/keyboard alternatives, animation
lifecycle and broader reduced-motion work under work-plan item 5. No 100 score
is guaranteed across devices, future content, or deployments.

The prior live audit found older frontend code and failing Notion public reads.
This PR does not migrate or repair those providers. Rerun the same ten audits and
key journeys against a deployed preview and `https://regencommons.com` after the
Vercel deployment restriction is resolved and this branch is deployed.

Dashboard PR #4 merged independently during verification. This branch integrates
its admin assets, shared-token extraction, logo still mode, and SMTP/Auth work
from main. Shared normal font binaries are identical. The local asset allowlist
and MIME map now retain both sets of additions, binary reads, and this branch's
gzip/route handling. The PR diff against main contains only the public polish
work; it does not redeploy or change the dashboard.
