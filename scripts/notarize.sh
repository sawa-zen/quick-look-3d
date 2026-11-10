#!/usr/bin/env bash
# Turn a signed .app into a .dmg, notarize it, and staple the ticket.
#   Requires: ./scripts/build.sh already run with SIGN_IDENTITY="Developer ID Application"
#   Credentials, either:
#     NOTARY_KEYCHAIN_PROFILE … profile saved with `xcrun notarytool store-credentials`
#                               (preferred locally: the password never appears in `ps`)
#   or an App Store Connect API key (no secret on the command line):
#     NOTARY_KEY_PATH   … path to the AuthKey_XXXX.p8 file
#     NOTARY_KEY_ID     … key ID
#     NOTARY_KEY_ISSUER … issuer UUID
#   or all of:
#     APPLE_TEAM_ID    … Team ID (10 chars)
#     NOTARY_APPLE_ID  … Apple ID for notarization (email)
#     NOTARY_PASSWORD  … app-specific password (created at appleid.apple.com)
#                        (passed as a notarytool argument; fine on an ephemeral CI runner)
#   Usage: ./scripts/notarize.sh [path/to/QuickLook3D.app]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="${1:-build/Build/Products/Release/QuickLook3D.app}"
DMG="QuickLook3D.dmg"

if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  AUTH_ARGS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
elif [ -n "${NOTARY_KEY_PATH:-}" ]; then
  : "${NOTARY_KEY_ID:?NOTARY_KEY_ID is not set}"
  : "${NOTARY_KEY_ISSUER:?NOTARY_KEY_ISSUER is not set}"
  AUTH_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_KEY_ISSUER")
else
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is not set}"
  : "${NOTARY_APPLE_ID:?NOTARY_APPLE_ID is not set}"
  : "${NOTARY_PASSWORD:?NOTARY_PASSWORD is not set}"
  AUTH_ARGS=(--apple-id "$NOTARY_APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$NOTARY_PASSWORD")
fi

if [ ! -d "$APP" ]; then
  echo "error: $APP not found. Run build.sh with signing first." >&2
  exit 1
fi

echo "==> Verify the signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Create the .dmg: $DMG"
rm -f "$DMG"
# Stage the app next to an "Applications" alias so the mounted dmg shows the
# familiar "drag the app into Applications" layout. ditto preserves the signature.
STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Quick Look 3D" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "==> Submit for notarization (wait until done)"
# `|| true`: on failure still print the output below (set -e would abort silently);
# the "status: Accepted" check decides success.
SUBMIT_OUT=$(xcrun notarytool submit "$DMG" "${AUTH_ARGS[@]}" --wait 2>&1) || true
echo "$SUBMIT_OUT"
SUB_ID=$(printf '%s\n' "$SUBMIT_OUT" | awk '/id:/{print $2; exit}')

if ! printf '%s\n' "$SUBMIT_OUT" | grep -q "status: Accepted"; then
  echo "==> Notarization did not pass. Fetching the detailed log (rejection reasons):"
  [ -n "$SUB_ID" ] && xcrun notarytool log "$SUB_ID" "${AUTH_ARGS[@]}" || true
  exit 1
fi

echo "==> Staple and validate"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG" || true

echo "==> Done: $ROOT/$DMG (ready to distribute)"
