# 3D Quick Look Plugin

macOS の Quick Look で `.vrm` / `.vrma` / `.glb` / `.fbx` ファイルを 3D プレビューするプラグイン。
**WKWebView + Three.js + [@pixiv/three-vrm](https://github.com/pixiv/three-vrm)** で描画する。

Finder で `.vrm` / `.vrma` / `.glb` / `.fbx` を選択してスペースキーを押すと、モデルをぐりぐり回して確認できる。
GLB / FBX にアニメーションが含まれていれば自動再生する。
`.vrma`（VRM アニメーション）やスキン無し FBX はメッシュを持たないため、ボーンをスケルトン表示してアニメーションを再生する。

---

## 仕組み

```
Finder (スペースキー)
   └─ Quick Look Extension (Swift / app-extension)
        ├─ .vrm を読み込み → Base64 化
        └─ WKWebView に renderer/index.html を表示
             └─ postMessage で Base64 を渡す
                  └─ Three.js + three-vrm が WebGL で描画
```

- フロント (`renderer/`) は **Vite + vite-plugin-singlefile** で JS/CSS を全部 1 枚の
  `index.html` にインライン化する。WKWebView の `loadFileURL` で別ファイルの読み込みに
  詰まらないための構成。
- ファイル読み込みは Swift 側だけが行い、中身を Base64 で JS に渡す。
  Quick Look のサンドボックス制約をこれで回避している。
- `.vrm`（独自 UTI `com.vrm.vrm`）/ `.glb`（標準 UTI `org.khronos.glb`）/
  `.fbx`（`com.autodesk.mac.fbx` ほか）を `QLSupportedContentTypes` に登録。
  先頭バイトのマジックで FBX か否かを判定し、FBX は `FBXLoader`、それ以外は
  `GLTFLoader` で読む。GLTF 側は `userData.vrm` の有無で VRM / 素の glTF を分岐。
  - 注: FBX は埋め込みテクスチャのみ対応（外部テクスチャ参照はサンドボックスで読めない）。
- `.vrma`（独自 UTI `com.vrm.vrma`）やスキン無し FBX はメッシュを持たない。これらは
  ボーン階層を `THREE.SkeletonHelper` でスティックフィギュア表示し、アニメーションを
  再生する（既定アバターの同梱は不要 = ライセンス・サイズの心配なし）。
- `.gltf`（分割型）は非対応。外部 `.bin`／テクスチャがサンドボックスで読めないため。
  単一ファイルが必要なら `.glb` を使う。
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
└── scripts/build.sh               # 一括ビルド・インストール手順
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

## クイックスタート

```bash
# フロント・プロジェクト生成・ビルドまで一括
./scripts/build.sh
```

完了後の手順:

1. 生成された `build/Build/Products/Release/QuickLook3D.app` を `/Applications` に置く
2. **一度アプリを起動する**（これで拡張機能が macOS に登録される）
3. システム設定 > 一般 > ログイン項目と機能拡張 > **機能拡張 > Quick Look** で有効化
4. Quick Look を再読み込み:
   ```bash
   qlmanage -r && qlmanage -r cache
   ```
5. 動作確認:
   ```bash
   qlmanage -p /path/to/avatar.vrm
   ```
   または Finder で `.vrm` を選択してスペースキー。

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
    `prepare` → `didFinish` → `VRM/glTF loaded & added to scene` まで出れば描画成功。
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

## 注意点

### サンドボックス
拡張機能はサンドボックス下で動く。ファイルアクセスは `preparePreviewOfFile(at:)` に
渡された URL のみ許可される。本実装は Swift 側で読み込んで Base64 で JS に渡すことで回避。

### 署名
自分の Mac で使うだけなら署名不要（`CODE_SIGN_IDENTITY="-"` で Sign to Run Locally）。
他人に配布する場合は Apple Developer Program 加入と公証（Notarization）が必要 → 下記。

### VRM バージョン
`@pixiv/three-vrm` は VRM 0.x / 1.0 両対応。0.x は `VRMUtils.rotateVRM0()` で座標系を補正する。

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

## ライセンス

本プロジェクトのコードは [MIT License](./LICENSE)（Copyright © 2026 sawa-zen）。

配布物に同梱するサードパーティ（three.js / @pixiv/three-vrm / fflate）も
すべて MIT License。詳細は [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md) を参照。
アバター等のモデルデータは同梱していない（VRMA・スキン無し FBX はスケルトン表示）ため、
モデルのライセンスを気にせず配布できる。
