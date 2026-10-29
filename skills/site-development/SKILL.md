---
name: site-development
description: Implement and verify Regen Commons website pages and API handlers using the local fixture environment. Use for this repository's development and debugging, not live Notion administration or deployment.
---

# Site development

Read [development](../../docs/development.md) for executable commands. Keep
[AGENTS.md](../../AGENTS.md) as the authority for repository boundaries.

## Choose the owning surface

- UI interactions often span the page's inline script and root `script.js`;
  inspect both before editing. Map graph and library logic currently live in
  `map.html`. Shared animation code lives in `canvas.js` and `logo-canvas.js`.
- For API work, inspect the caller and
  [integration contracts](../../docs/integrations.md). The fixture server runs
  the real handlers and replaces Notion transport before importing them. A new
  provider operation needs a corresponding fixture implementation and meaningful
  behavior checks; never make local fixtures fall through to a live service.
- Browser scripts are classic scripts, including inline blocks. `check` parses
  them without running them. It is not a browser, CSS, or accessibility audit.

## Obtain useful proof

Start the local server once, reuse it, and check the visible synthetic-data
banner before submitting test forms. Reload after page changes; restart after
handler changes. Local rate limits behave like the handlers and reset on restart.

Run the repository checks. For UI work, use the browser to complete the changed
flow, including rejection/retry behavior where relevant. Label proof as rendered
local fixtures and name the browser. HTTP smoke alone cannot show whether a
canvas, form step, modal, or responsive layout works.

Fixtures do not emulate Notion schema validation, Resend, Telegram delivery,
Vercel routing/cache behavior, or distributed rate limits. Record any required
live verification as pending, with the exact missing prerequisite. The
[work plan](../../docs/work-plan.md) owns follow-up priorities.
