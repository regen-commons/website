#!/bin/sh
# Renders the link-preview images (1200x630) and the PNG icons.
#
# Run on a Mac from the repository root after changing template.html,
# favicon.svg or a page headline:   sh scripts/share-images/render.sh
#
# Needs a Chromium-based browser for the share images (set BROWSER to its
# binary; Chrome and Brave are detected) and rsvg-convert for the icons
# (brew install librsvg). The browser runs headless with a throwaway profile.
set -eu

root="$(cd "$(dirname "$0")/../.." && pwd)"
template="$root/scripts/share-images/template.html"
out="$root/assets/share"

if [ -z "${BROWSER:-}" ]; then
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
    if [ -x "$candidate" ]; then BROWSER="$candidate"; break; fi
  done
fi
if [ -z "${BROWSER:-}" ]; then
  echo "No Chromium-based browser found; set BROWSER to its binary." >&2
  exit 1
fi

profile="$(mktemp -d)"
trap 'rm -rf "$profile"' EXIT
mkdir -p "$out"

for page in home learn map join seeds about constitution; do
  "$BROWSER" --headless=new --disable-gpu --hide-scrollbars --no-first-run \
    --no-default-browser-check --user-data-dir="$profile" \
    --allow-file-access-from-files --force-device-scale-factor=1 \
    --window-size=1200,630 --virtual-time-budget=5000 \
    --screenshot="$out/$page.png" "file://$template?page=$page" >/dev/null 2>&1
  echo "rendered assets/share/$page.png"
done

# Icons: the mark on a full-bleed square, which platforms round themselves.
icon="$(mktemp)"
trap 'rm -rf "$profile" "$icon"' EXIT
cat > "$icon" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><rect width="48" height="48" fill="#0d100a"/><g transform="translate(6 6) scale(0.75)"><g fill="none" stroke="#a6b878" stroke-width="2" stroke-linecap="round"><path d="M24 24 12 11m12 13L37 11M24 24l-1 17m1-17L7 27m17-3 17 6M17 17l1-9m13 9 9 1M23 33l-8 5"/></g><circle cx="24" cy="24" r="4" fill="#c9956b"/></g></svg>
SVG
rsvg-convert -w 180 -h 180 "$icon" -o "$root/apple-touch-icon.png"
rsvg-convert -w 32 -h 32 "$root/favicon.svg" -o "$root/favicon-32.png"
echo "rendered apple-touch-icon.png and favicon-32.png"
