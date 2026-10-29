# Steward dashboard UI

Use the [root guide](../AGENTS.md) for shared workflow. This guide covers this
directory and root-level `admin.html`, as routed by the root guide. When the
dashboard implementation is present, inspect the page, `admin/app.js`, and
`admin/style.css` together. If a checkout contains only this guidance, treat the
missing implementation as pending rather than claiming a runnable dashboard.
For request or session changes, also read the [API guide](../api/AGENTS.md).

## Boundaries

- Keep `/admin` as the steward surface with email sign-in codes. The HTML shell
  contains no private records; authenticated requests load them through
  `/api/admin`. UI visibility is not an authorization check.
- Keep original application answers visibly separate from a curated profile
  draft. Linking or previewing a profile does not accept an application or
  publish a member. Consult the [database guide](../supabase/AGENTS.md) before
  adding decision actions or changing these meanings.
- Keep credentials, codes, tokens, and private answers out of browser storage,
  URLs, analytics, and diagnostic output. Render submitted text as text and
  validate external link protocols before creating links.
- Clear private UI state on sign-out or loss of authorization. Ignore stale
  requests after the session or view changes, and recheck the session when
  restoring a page from browser history. Preserve the page's security headers
  and content security policy when changing asset loading.

## Verification

Follow the root checks and use the synthetic local environment described in
[development](../docs/development.md). For changed flows, inspect rendered
desktop/mobile layouts and keyboard navigation. Cover the relevant loading,
empty, error, retry, and filtered-empty states; errors must not look like an
empty queue or successful operation.

For auth changes, exercise valid and invalid codes, non-steward denial, session
expiry, and sign-out, including pending requests and browser history. Ensure
private content disappears when access ends. Fixture codes prove local UI
behavior only; report real email delivery and hosted authentication separately.
