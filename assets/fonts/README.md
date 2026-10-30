# Public website fonts

These are original, unmodified Latin WOFF2 faces from Google Fonts. The normal
Fraunces, Source Serif 4, and Space Grotesk files are identical to the dashboard
assets in PR #4. The public site also uses the original italic faces.

| Family | Files | License |
| --- | --- | --- |
| Fraunces | `fraunces-latin.woff2`, `fraunces-italic-latin.woff2` | [OFL](fraunces-OFL.txt) |
| Source Serif 4 | `source-serif-4-latin.woff2`, `source-serif-4-italic-latin.woff2` | [OFL](source-serif-4-OFL.txt) |
| Space Grotesk | `space-grotesk-latin.woff2` | [OFL](space-grotesk-OFL.txt) |

The italic files came from these Google Fonts resources:

- [Fraunces italic](https://fonts.gstatic.com/s/fraunces/v38/6NUs8FyLNQOQZAnv9ZwNjucMHVn85Ni7emAe9lKqZTnbB-gzTK0K1ChJdt9hFwpX9W37ll9_mv0iQublWII.woff2)
- [Source Serif 4 italic](https://fonts.gstatic.com/s/sourceserif4/v15/vEF02_tTDB4M7-auWDN0ahZJW1ge6NmXpVAHV83Bfb_US2D2QYxoUKIkn98pRl9tDMQCjDbUXg.woff2)

[fonts.css](../../fonts.css) owns the public face declarations and metric-adjusted
Georgia/Arial fallbacks. Fallback widths were measured from the original face
metrics using representative page copy; they approximate the layout, rather than
matching every string or weight. No font binaries were modified for this work.
Characters outside these faces continue through the system fallback stack.

Public pages preload the display faces used above the fold. `font-display:
optional` prevents a late switch after text is visible. On a slow first visit the
browser may keep the fallback for that navigation; a subsequent navigation can
use the cached brand face. This deliberately favors stable, readable text over a
late brand-font replacement. Keep that tradeoff when editing the preload set or
font-display policy. See [MDN's font-display reference](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@font-face/font-display).
