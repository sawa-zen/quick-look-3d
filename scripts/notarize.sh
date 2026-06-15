#!/usr/bin/env bash
# 署名済み .app を .dmg にして公証(Notarization)・staple するスクリプト。
#   前提: ./scripts/build.sh を SIGN_IDENTITY="Developer ID Application" でビルド済み
#   必須 env:
#     APPLE_TEAM_ID    … Team ID（10文字）
#     NOTARY_APPLE_ID  … 公証用 Apple ID（メールアドレス）
#     NOTARY_PASSWORD  … App 用パスワード（appleid.apple.com で発行）
#   使い方: ./scripts/notarize.sh [path/to/QuickLook3D.app]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="${1:-build/Build/Products/Release/QuickLook3D.app}"
DMG="QuickLook3D.dmg"

: "${APPLE_TEAM_ID:?APPLE_TEAM_ID が未設定}"
: "${NOTARY_APPLE_ID:?NOTARY_APPLE_ID が未設定}"
: "${NOTARY_PASSWORD:?NOTARY_PASSWORD が未設定}"

if [ ! -d "$APP" ]; then
  echo "エラー: $APP が見つかりません。先に署名付きで build.sh を実行してください" >&2
  exit 1
fi

echo "==> 署名を検証"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> .dmg を作成: $DMG"
rm -f "$DMG"
hdiutil create -volname "3D Quick Look" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "==> 公証を申請（完了まで待機）"
xcrun notarytool submit "$DMG" \
  --apple-id "$NOTARY_APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$NOTARY_PASSWORD" \
  --wait

echo "==> staple して検証"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG" || true

echo "==> 完了: $ROOT/$DMG （配布可能）"
