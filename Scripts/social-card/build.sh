#!/bin/bash
# Regenerates site/assets/og-card.jpg, the 1200x630 social preview image.
# The card is drawn in HTML (Scripts/social-card/card.html) and screenshotted, so it stays in
# step with the landing page's typography instead of drifting as a hand-made export.
#
# Requires a Chromium-family browser. Set CHROME=/path/to/binary to override.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
OUT="$ROOT/site/assets/og-card.jpg"
TMP="$(mktemp -d)"
PORT="${PORT:-8971}"

cleanup() {
  [[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

if [[ -z "${CHROME:-}" ]]; then
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "$HOME/.omp/puppeteer/chrome/mac_arm-150.0.7871.24/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
  do
    [[ -x "$candidate" ]] && CHROME="$candidate" && break
  done
fi
[[ -x "${CHROME:-}" ]] || { echo "error: no Chromium-family browser found; set CHROME=" >&2; exit 1; }

python3 -m http.server "$PORT" --directory "$ROOT" >/dev/null 2>&1 &
SERVER_PID=$!
disown "$SERVER_PID" 2>/dev/null || true
sleep 1

"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1200,630 --virtual-time-budget=5000 \
  --screenshot="$TMP/card.png" "http://127.0.0.1:$PORT/Scripts/social-card/card.html" >/dev/null 2>&1

# JPEG, not WebP: social scrapers do not reliably decode WebP for og:image.
python3 - "$TMP/card.png" "$OUT" <<'PY'
import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
if im.size != (1200, 630):
    sys.exit(f"error: expected 1200x630, got {im.size[0]}x{im.size[1]}")
im.save(dst, "JPEG", quality=94, optimize=True, progressive=True, subsampling=0)
print(f"wrote {dst} ({im.size[0]}x{im.size[1]})")
PY
