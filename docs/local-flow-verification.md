# Seed and map verification

Verified on 29 October 2026 using Node 22.22.1, the credential-free local server,
and the Codex in-app browser. All submitted text was invented. No live provider
writes, notifications, deployment, or account changes were part of these checks.

## Repeat the browser checks

Start `npm run dev` and open the [local scenario controls](http://127.0.0.1:3501/__dev/scenarios).
Keep the target page in another tab and confirm its **Local demo** banner. The
[development guide](development.md) explains each scenario and reset behavior.

| Case | Action | Observed result |
|---|---|---|
| Invalid seed | Enter one character on `/seeds.html` | Length feedback; textarea receives focus; no confirmation |
| Delayed seed | Choose `slow`, submit a valid seed | “Saving…” and disabled submit until acknowledgement; confirmation follows |
| Service failure | Choose `error-once`, submit | Text retained with failure feedback and Try again; retry succeeds |
| Rate limit | Choose `rate-limit-once`, submit | Text retained and a request to wait before retrying; no false success |
| Connection failure | Choose `offline`, submit | Unconfirmed-save message, text retained even after reload; reset to normal and retry succeeds |
| Learn handoff | Choose `error-once`, submit from `/learn.html#plant`, retry | Failure stays on Learn; success reaches the seed ceremony; API readback shows one copy before and after reloading the confirmation page |
| Empty map | Choose `empty`, reload `/map.html` | Separate no-members and no-contributions messages; empty graph canvas is hidden |
| Failed map | Choose `error-once`, reload | Both sections report failure; keyboard activation of each retry recovers that section independently |
| Delayed map | Choose `slow`, reload | Both loading messages precede the populated graph/library |
| Empty filter | Use normal data, select Infrastructure | No-matching-contributions message; the data source remains in its loaded state |

Seed failures and map states were inspected at 390 × 844; seed validation/save
states were also checked at 1280 × 720. Retained text, status messages, retries,
and confirmation focus were checked through the accessibility tree. This is
targeted browser evidence, not a full screen-reader or accessibility audit.
Reduced-motion ceremony timing is handled in code; OS-level reduced-motion
emulation and the existing canvas animations remain part of work-plan item 5.

Screenshots are local, ignored artifacts in `artifacts/`:
`seed-save-error-mobile.png` and `map-empty-mobile.png`.

## Automated coverage and limits

`npm run check`, `npm test` (14 tests), and `npm run smoke` pass. Behavior tests
exercise seed length boundaries, duplicate clicks while pending/after success,
429/5xx/network/malformed responses, timeout, retry, independent list states,
and overlapping read prevention. HTTP tests exercise the actual handlers against
the synthetic adapter and the local scenario controls. Smoke checks all five
pages/assets, reads, seed write/readback, and pending-application exclusion.

The browser steps above were performed interactively; they are not yet automated
in CI. Provider schema, delivery, Vercel routing/cache behavior, uncertain-write
idempotency, and cross-repo Dev Workbench readiness remain outside this proof.
The [work plan](work-plan.md) tracks these separately.
