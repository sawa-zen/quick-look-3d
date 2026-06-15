# 開発者向けドキュメント

3D Quick Look Plugin のアーキテクチャ・ビルド・配布手順。利用者向けの概要は
[../README.md](../README.md) を参照。

技術スタック: **Swift（Quick Look App Extension）+ WKWebView + Three.js +
[@pixiv/three-vrm](https://github.com/pixiv/three-vrm)**。

---

## 仕組み

```
Finder (スペースキー)
   └─ Quick Look Extension (Swift / app-extension)
        ├─ ファイルを読み込み → Base64 化
        └─ WKWebView に renderer/index.html を表示
             └─ postMessage で Base64 を渡す
                  └─ Three.js が WebGL で描画
```

- フロント (`renderer/`) は **Vite + vite-plugin-singlefile** で JS/CSS を全部 1 枚の
  `index.html` にインライン化する。WKWebView の `loadFileURL` で別ファイルの読み込みに
  詰まらないための構成。
- ファイル読み込みは Swift 側だけが行い、中身を Base64 で JS に渡す。
  Quick Look のサンドボックス制約をこれで回避している。
- `.vrm`（独自 UTI `com.vrm.vrm`）/ `.glb`（標準 UTI `org.khronos.glb`）/
  `.fbx`（`com.autodesk.mac.fbx` ほか）/ `.vrma`（独自 UTI `com.vrm.vrma`）を
  `QLSupportedContentTypes` に登録。
  先頭バイトのマジックで FBX か否かを判定し、FBX は `FBXLoader`、それ以外は
  `GLTFLoader` で読む。GLTF 側は `userData.vrm` の有無で VRM / 素の glTF を分岐。
- メッシュを持たないもの（`.vrma` / スキン無し FBX）はボーン階層を
  `THREE.SkeletonHelper` でスティックフィギュア表示し、アニメーションを再生する
  （既定アバターの同梱は不要 = ライセンス・サイズの心配なし）。
- `.gltf`（分割型）は非対応。外部 `.bin`／テクスチャがサンドボックスで読めないため。
- FBX は埋め込みテクスチャのみ対応（外部テクスチャ参照はサンドボックスで読めない）。
- WKWebView はローカル `file://` を読むだけでも Network プロセスを起動するため、
  拡張機能に `com.apple.security.network.client` を付与している（無いと WebContent が
  クラッシュして真っ白になる）。

---

## ディレクトリ構成

```
.
├── renderer/                      # フロントエンド (Vite + Three.js + three-vrm)
│   ├── src/main.ts                # レンダラー本体
│   ├── index.html
│   └── vite.config.ts             # singlefile 設定
├── QuickLook3D/
│   ├── App/                       # ホストアプリ（最小限）
│   │   ├── QuickLook3DApp.swift
│   │   ├── Info.plist
│   │   └── QuickLook3D.entitlements
│   └── Extension/                 # Quick Look 拡張機能（本体）
│       ├── PreviewViewController.swift
│       ├── Info.plist             # UTI / 拡張子の登録
│       ├── QuickLook3DExtension.entitlements
│       └── Resources/renderer/    # ← renderer/dist がコピーされる（生成物）
├── project.yml                    # XcodeGen 設定（.xcodeproj を生成）
├── scripts/build.sh               # 一括ビルド
├── scripts/notarize.sh            # 公証 → .dmg 作成
└── .github/workflows/release.yml  # タグ push で署名・公証・リリース
```

---

## 必要なもの

| ツール | 用途 | インストール |
|---|---|---|
| **フル Xcode** | App Extension のビルド（Command Line Tools だけでは不可） | App Store |
| Node.js 18+ | renderer のビルド | `brew install node` |
| XcodeGen | `.xcodeproj` の生成 | `brew install xcodegen` |

> `.xcodeproj` は Git 管理せず `project.yml` から生成する方針。手作業で Xcode の
> GUI からプロジェクトを作りたい場合は後述の「手動セットアップ」を参照。

---

## ビルド（ローカル）

```bash
# renderer ビルド → Resources へコピー → .xcodeproj 生成 → ビルドまで一括
./scripts/build.sh
```

完了後の手順:

1. 生成された `build/Build/Products/Release/QuickLook3D.app` を `/Applications` に置く
2. **一度アプリを起動する**（これで拡張機能が macOS に登録される）
3. システム設定 → 一般 → ログイン項目と機能拡張 → **機能拡張（Quick Look）** で有効化
4. Quick Look を再読み込み: `qlmanage -r && qlmanage -r cache`
5. 動作確認: `qlmanage -p /path/to/model.vrm`（`.vrma` / `.glb` / `.fbx` も可）

> ローカルビルドは ad-hoc 署名（`-`）。署名なし（`CODE_SIGNING_ALLOWED=NO`）だと
> 拡張機能が `pluginkit` に登録されないので注意。

---

## 開発

### フロントだけブラウザで確認する

ネイティブをビルドしなくても、レンダラー部分はブラウザ単体で動作確認できる。

```bash
cd renderer
npm install
npm run dev
```

開いたページに **`.vrm` / `.vrma` / `.glb` / `.fbx` をドラッグ&ドロップ**すると表示される。
`?url=...` クエリでリモートのモデルを直接読み込むことも可能。

### ネイティブを Xcode で開いて開発する

```bash
./scripts/build.sh        # 初回: renderer ビルド → Resources へコピー → .xcodeproj 生成
open QuickLook3D.xcodeproj
```

> `xcodegen generate` 時点で `QuickLook3D/Extension/Resources/renderer/` が
> 存在している必要がある（フォルダ参照のため）。`build.sh` がコピーまで済ませる。

Xcode で `QuickLook3D` スキームを Run すると、ビルド時に renderer が自動で
作り直されて拡張機能に同梱される（`project.yml` の preBuildScript）。

---

## トラブルシュート

- **プレビューが真っ白 / 何も出ない**
  - まずログを見る（拡張機能の console は os_log に転送している）:
    ```bash
    log stream --predicate 'subsystem == "com.sawazen.QuickLook3D"'
    ```
    別ターミナルで `qlmanage -p /path/to/x.vrm` を実行。
    `prepare` → `didFinish` → `... loaded & added to scene` まで出れば描画成功。
  - `didFinish` が出ず WebContent が crash する場合は、拡張機能の entitlements に
    `com.apple.security.network.client` があるか確認（WKWebView の必須権限）。
  - renderer が同梱されているか確認:
    `build/.../QuickLook3DExtension.appex/Contents/Resources/renderer/index.html`
- **拡張機能が一覧に出ない**
  - アプリを一度起動したか / `/Applications` に置いたか確認
  - `qlmanage -r && qlmanage -r cache` でキャッシュをクリア
  - `pluginkit -m | grep -i quicklook3d` で登録状況を確認
- **モデルが横倒し・裏向き**
  - VRM 0.x の座標系。`VRMUtils.rotateVRM0()` を呼んでいる（対応済み）

---

## 実装メモ

- **サンドボックス**: 拡張機能はサンドボックス下で動く。ファイルアクセスは
  `preparePreviewOfFile(at:)` に渡された URL のみ許可される。本実装は Swift 側で
  読み込んで Base64 で JS に渡すことで回避。
- **VRM バージョン**: `@pixiv/three-vrm` は VRM 0.x / 1.0 両対応。0.x は
  `VRMUtils.rotateVRM0()` で座標系を補正する。
- **署名**: 自分の Mac で使うだけなら ad-hoc 署名（`CODE_SIGN_IDENTITY="-"`）で十分。
  他人に配布する場合は下記の「配布」を参照。

---

## 配布（署名・公証）

他人の Mac で素直に動かすには **Apple Developer Program**（年 ¥12,980 / US$99）に加入し、
**Developer ID 署名 + 公証（Notarization）** が必要。未署名 / ad-hoc 署名だと Gatekeeper に
弾かれ、quarantine 付きだとサンドボックスの拡張機能が読み込まれない。

### 自動（GitHub Actions）

`v*` タグを push すると `.github/workflows/release.yml` が
**署名 → 公証 → `.dmg` 作成 → Release 添付**まで自動で行う。事前にリポジトリの
Secrets を登録しておくこと:

| Secret | 内容 |
|---|---|
| `MACOS_CERTIFICATE` | Developer ID Application 証明書(.p12)を base64 化（`base64 -i cert.p12 \| pbcopy`） |
| `MACOS_CERTIFICATE_PWD` | 上記 .p12 のパスワード |
| `KEYCHAIN_PASSWORD` | 一時キーチェーン用の任意のパスワード |
| `APPLE_TEAM_ID` | Team ID（10文字） |
| `NOTARY_APPLE_ID` | 公証用 Apple ID（メールアドレス） |
| `NOTARY_PASSWORD` | App 用パスワード（appleid.apple.com で発行） |

```bash
git tag v1.0.0 && git push origin v1.0.0   # → Release に署名済み .dmg が付く
```

> `gh secret set` でリポジトリ Secret を登録する場合は、必ず `--repo sawa-zen/3d-quick-look-plugin`
> を付ける（カレントの別リポジトリに入らないように）。

### 手動

```bash
# 1) Developer ID 署名でビルド
SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/build.sh
# 2) 公証して .dmg を作成（staple まで）
APPLE_TEAM_ID=XXXXXXXXXX NOTARY_APPLE_ID=you@example.com NOTARY_PASSWORD=app-specific-pw \
  ./scripts/notarize.sh
```

> 公証認証は App 用パスワードの代わりに App Store Connect API キー
> （`--key` / `--key-id` / `--issuer`）も使える。

### ハマりどころ（解決済み）

- `xcodebuild build` は `com.apple.security.get-task-allow` を自動注入し公証で弾かれる
  → `build.sh` は署名時に `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` を付けて除去している。
- 公証には secure timestamp が必須 → 署名時に `--timestamp`、Hardened Runtime は
  `project.yml` で有効化。
- CI は XcodeGen が生成する新しい `.xcodeproj` 形式を読める Xcode が必要
  → ランナーは `macos-15` + `latest-stable` Xcode。

---

## 手動セットアップ（XcodeGen を使わない場合）

1. Xcode で **macOS App** を新規作成（Product Name: `QuickLook3D`）
2. **File > New > Target** から **Quick Look Preview Extension** を追加
3. 本リポジトリの `QuickLook3D/Extension/PreviewViewController.swift` と
   `Info.plist`（`QLSupportedContentTypes` / `UTImportedTypeDeclarations`）の内容を反映
4. `renderer/dist` を拡張機能ターゲットに **フォルダ参照（青フォルダ）** で `renderer` という名前で追加
   （グループ参照だとサブディレクトリが失われて `subdirectory: "renderer"` で見つからなくなる）

---

## 参考

- [magicien/VRMQuickLook](https://github.com/magicien/VRMQuickLook) — SceneKit 実装（VRM 0.x）
- [magicien/GLTFQuickLook](https://github.com/magicien/GLTFQuickLook) — Quick Look Extension の構成参考
- [@pixiv/three-vrm](https://github.com/pixiv/three-vrm)
