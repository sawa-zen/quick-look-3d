# 3D Quick Look Plugin

macOS の Quick Look で **`.vrm` / `.vrma` / `.glb` / `.fbx`** を 3D プレビューするプラグイン。

Finder でファイルを選んでスペースキーを押すと、モデルをぐりぐり回して確認できる。
アニメーションが含まれていれば自動再生する。

---

## インストール

1. [Releases](https://github.com/sawa-zen/3d-quick-look-plugin/releases/latest) から
   `QuickLook3D.dmg` をダウンロードして開く
2. **QuickLook3D.app** を「アプリケーション」フォルダにドラッグ
3. **一度アプリを起動する**（これで Quick Look 拡張機能が macOS に登録される。
   ウィンドウは閉じてよい）
4. **システム設定 → 一般 → ログイン項目と機能拡張 → 機能拡張（Quick Look）** を開き、
   **3D Quick Look** をオンにする

> 配布物は Apple の公証（Notarization）済みなので、Gatekeeper の警告は出ません。

---

## 使い方

Finder で対応ファイルを選んで **スペースキー**（または右クリック → クイックルック）。

| 形式 | 内容 |
|---|---|
| `.vrm` | VRM アバター（0.x / 1.0 両対応） |
| `.vrma` | VRM アニメーション。メッシュが無いのでボーンをスケルトン表示して再生 |
| `.glb` | glTF バイナリ。アニメーションがあれば自動再生 |
| `.fbx` | FBX モデル。アニメーションがあれば自動再生 |

- マウスドラッグで回転、スクロールでズーム
- スキン（メッシュ）を持たない `.fbx` や `.vrma` は、骨格（スケルトン）として表示される

---

## うまく表示されないとき

- インストール手順 3〜4（**一度起動** と **機能拡張をオン**）が済んでいるか確認
- それでもダメなら Quick Look のキャッシュを更新:
  ```bash
  qlmanage -r && qlmanage -r cache
  ```
- `.gltf`（分割型 = `.bin` やテクスチャが別ファイル）は非対応。単一ファイルの `.glb` を使う

---

## ライセンス

本体コードは [MIT License](./LICENSE)。同梱するサードパーティ（three.js / @pixiv/three-vrm /
fflate）も MIT で、詳細は [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md)。
アバター等のモデルデータは同梱していない。

---

## 開発者向け

ビルド方法・アーキテクチャ・配布（署名/公証）手順は
**[docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md)** を参照。
