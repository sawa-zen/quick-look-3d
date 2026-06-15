#!/usr/bin/env bash
# 3D Quick Look プラグインを一括ビルド・インストールするスクリプト。
#   前提: フル Xcode / xcodegen / node がインストール済み
#   使い方: ./scripts/build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# App Extension のビルドにはフル Xcode が必要。xcode-select が
# CommandLineTools を指していても、ここでフル Xcode を自動検出して使う。
if [ ! -d "$(xcode-select -p 2>/dev/null)/Platforms" ]; then
  if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    echo "==> フル Xcode を使用: $DEVELOPER_DIR"
  else
    echo "エラー: フル Xcode が見つかりません。App Store からインストールしてください" >&2
    exit 1
  fi
fi

echo "==> 1/5 renderer をビルド"
( cd renderer && [ -d node_modules ] || npm install; npm run build )

echo "==> 2/5 renderer を拡張機能の Resources にコピー"
DEST="QuickLook3D/Extension/Resources/renderer"
mkdir -p "$DEST"
rm -rf "${DEST:?}"/*
cp -R renderer/dist/* "$DEST/"

echo "==> 3/5 Xcode プロジェクトを生成 (xcodegen)"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "エラー: xcodegen が見つかりません。'brew install xcodegen' を実行してください" >&2
  exit 1
fi
xcodegen generate

# 署名方式は環境変数で切り替え:
#   ローカル: 未指定 → ad-hoc 署名("-")。拡張機能の登録に最低限必要。
#   配布:     SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM=XXXXXXXXXX
SIGN_ID="${SIGN_IDENTITY:--}"
TEAM="${DEVELOPMENT_TEAM:-}"
SIGN_ARGS=(CODE_SIGN_IDENTITY="$SIGN_ID" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM")
if [ "$SIGN_ID" != "-" ]; then
  # 公証には secure timestamp が必須（Hardened Runtime は project.yml で有効）
  SIGN_ARGS+=(OTHER_CODE_SIGN_FLAGS="--timestamp")
  echo "==> 4/5 アプリをビルド（署名: $SIGN_ID / team: $TEAM）"
else
  echo "==> 4/5 アプリをビルド（ad-hoc 署名）"
  # ※ 署名なし（CODE_SIGNING_ALLOWED=NO）だと拡張機能が pluginkit に登録されない。
fi
xcodebuild \
  -project QuickLook3D.xcodeproj \
  -scheme QuickLook3D \
  -configuration Release \
  -derivedDataPath build \
  "${SIGN_ARGS[@]}" \
  build

APP="build/Build/Products/Release/QuickLook3D.app"
echo "==> 5/5 ビルド完了: $APP"
echo
echo "次の手順でインストール・確認:"
echo "  1) 生成された $APP を /Applications にコピーして一度起動する"
echo "     (Quick Look 拡張機能が macOS に登録される)"
echo "  2) 拡張機能を有効化:  システム設定 > 一般 > ログイン項目と機能拡張 > Quick Look"
echo "  3) Quick Look を再読み込み:  qlmanage -r && qlmanage -r cache"
echo "  4) 動作確認:  qlmanage -p /path/to/model.vrm  (.vrma / .glb / .fbx も可)"
