#!/usr/bin/env bash
# One-shot build script for the 3D Quick Look plugin.
#   Requires: full Xcode / xcodegen / node installed
#   Usage: ./scripts/build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Building an App Extension needs full Xcode. Even if xcode-select points at
# CommandLineTools, auto-detect and use full Xcode here.
if [ ! -d "$(xcode-select -p 2>/dev/null)/Platforms" ]; then
  if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    echo "==> Using full Xcode: $DEVELOPER_DIR"
  else
    echo "error: full Xcode not found. Install it from the App Store." >&2
    exit 1
  fi
fi

echo "==> 1/5 Build renderer"
( cd renderer && [ -d node_modules ] || npm install; npm run build )

echo "==> 2/5 Copy renderer into the extension's Resources"
DEST="QuickLook3D/Extension/Resources/renderer"
mkdir -p "$DEST"
rm -rf "${DEST:?}"/*
cp -R renderer/dist/* "$DEST/"

echo "==> 3/5 Generate the Xcode project (xcodegen)"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found. Run 'brew install xcodegen'." >&2
  exit 1
fi
xcodegen generate

# Signing mode is chosen via env vars:
#   local:        unset → ad-hoc signing ("-"). The minimum needed to register the extension.
#   distribution: SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM=XXXXXXXXXX
SIGN_ID="${SIGN_IDENTITY:--}"
TEAM="${DEVELOPMENT_TEAM:-}"
SIGN_ARGS=(CODE_SIGN_IDENTITY="$SIGN_ID" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM")
if [ "$SIGN_ID" != "-" ]; then
  # Notarization requires a secure timestamp (Hardened Runtime is enabled in project.yml).
  # Also, `xcodebuild build` auto-injects get-task-allow, which notarization rejects, so
  # CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO stops that injection (key for distribution).
  SIGN_ARGS+=(OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
  echo "==> 4/5 Build the app (signing: ${SIGN_ID} / team: ${TEAM})"
else
  echo "==> 4/5 Build the app (ad-hoc signing)"
  # NOTE: building unsigned (CODE_SIGNING_ALLOWED=NO) means the extension won't register with pluginkit.
fi
xcodebuild \
  -project QuickLook3D.xcodeproj \
  -scheme QuickLook3D \
  -configuration Release \
  -derivedDataPath build \
  "${SIGN_ARGS[@]}" \
  build

APP="build/Build/Products/Release/QuickLook3D.app"
echo "==> 5/5 Build complete: $APP"
echo
echo "Install and verify:"
echo "  1) Copy $APP to /Applications and launch it once"
echo "     (registers the Quick Look extension with macOS)"
echo "  2) Enable the extension: System Settings > General > Login Items & Extensions > Quick Look"
echo "  3) Reload Quick Look:  qlmanage -r && qlmanage -r cache"
echo "  4) Test:  qlmanage -p /path/to/model.vrm  (.vrma / .glb / .fbx also work)"
