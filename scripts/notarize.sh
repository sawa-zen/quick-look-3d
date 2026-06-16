#!/usr/bin/env bash
# Turn a signed .app into a .dmg, notarize it, and staple the ticket.
#   Requires: ./scripts/build.sh already run with SIGN_IDENTITY="Developer ID Application"
#   Required env:
#     APPLE_TEAM_ID    … Team ID (10 chars)
#     NOTARY_APPLE_ID  … Apple ID for notarization (email)
#     NOTARY_PASSWORD  … app-specific password (created at appleid.apple.com)
#   Usage: ./scripts/notarize.sh [path/to/QuickLook3D.app]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="${1:-build/Build/Products/Release/QuickLook3D.app}"
DMG="QuickLook3D.dmg"

: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is not set}"
: "${NOTARY_APPLE_ID:?NOTARY_APPLE_ID is not set}"
: "${NOTARY_PASSWORD:?NOTARY_PASSWORD is not set}"

if [ ! -d "$APP" ]; then
  echo "error: $APP not found. Run build.sh with signing first." >&2
  exit 1
fi

echo "==> Verify the signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Create the .dmg: $DMG"
rm -f "$DMG"
hdiutil create -volname "3D Quick Look" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "==> Submit for notarization (wait until done)"
SUBMIT_OUT=$(xcrun notarytool submit "$DMG" \
  --apple-id "$NOTARY_APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$NOTARY_PASSWORD" \
  --wait 2>&1)
echo "$SUBMIT_OUT"
SUB_ID=$(printf '%s\n' "$SUBMIT_OUT" | awk '/id:/{print $2; exit}')

if ! printf '%s\n' "$SUBMIT_OUT" | grep -q "status: Accepted"; then
  echo "==> Notarization did not pass. Fetching the detailed log (rejection reasons):"
  xcrun notarytool log "$SUB_ID" \
    --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$NOTARY_PASSWORD" || true
  exit 1
fi

echo "==> Staple and validate"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG" || true

echo "==> Done: $ROOT/$DMG (ready to distribute)"
