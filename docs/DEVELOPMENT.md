# Development

**English** | [日本語](./DEVELOPMENT.ja.md)

Architecture, build, and distribution notes for Quick Look 3D Plugin. For the user-facing
overview see [../README.md](../README.md).

Stack: **Swift (Quick Look App Extension) + WKWebView + Three.js +
[@pixiv/three-vrm](https://github.com/pixiv/three-vrm)**.

---

## How it works

```
Finder (Space key)
   └─ Quick Look Extension (Swift / app-extension)
        ├─ reads the file → Base64
        └─ loads renderer/index.html into a WKWebView
             └─ passes the Base64 via postMessage
                  └─ Three.js renders it with WebGL
```

- The front end (`renderer/`) is built with **Vite + vite-plugin-singlefile**, inlining all
  JS/CSS into a single `index.html`. This avoids WKWebView's `loadFileURL` headaches with
  loading separate asset files.
- Only the Swift side reads files; it hands the contents to JS as Base64. This works around
  the Quick Look sandbox restrictions.
- `.vrm` (custom UTI `com.vrm.vrm`) / `.glb` (standard UTI `org.khronos.glb`) /
  `.fbx` (`com.autodesk.mac.fbx` and friends) / `.vrma` (custom UTI `com.vrm.vrma`)
  are registered in `QLSupportedContentTypes`.
  The leading magic bytes decide FBX vs. glTF: FBX goes through `FBXLoader`, everything else
  through `GLTFLoader`. On the glTF side, the presence of `userData.vrm` splits VRM from
  plain glTF.
- Draco-compressed glTF (`KHR_draco_mesh_compression`) is decoded with three.js's
  `DRACOLoader`. Its WASM decoder is inlined into `index.html` by `renderer/src/draco.ts`
  (instead of being fetched from a `decoderPath`), so no extra asset files are needed.
- Files with no mesh (`.vrma`, skin-less FBX) are visualized as a stick figure via
  `THREE.SkeletonHelper`, and the animation plays. No default avatar is bundled — so there
  are no licensing or bundle-size concerns.
- `.gltf` (multi-file) is unsupported: the external `.bin` / textures can't be read inside
  the sandbox.
- FBX supports embedded textures only (external texture references can't be read in the sandbox).
- WKWebView spins up a Network process even just to read a local `file://`, so the extension
  is granted `com.apple.security.network.client` (without it the WebContent process crashes
  and the preview stays blank).

---

## Layout

```
.
├── renderer/                      # front end (Vite + Three.js + three-vrm)
│   ├── src/main.ts                # the renderer
│   ├── index.html
│   └── vite.config.ts             # singlefile config
├── QuickLook3D/
│   ├── App/                       # host app (minimal)
│   │   ├── QuickLook3DApp.swift
│   │   ├── Info.plist
│   │   └── QuickLook3D.entitlements
│   └── Extension/                 # the Quick Look extension itself
│       ├── PreviewViewController.swift
│       ├── Info.plist             # UTI / file-extension registration
│       ├── QuickLook3DExtension.entitlements
│       └── Resources/renderer/    # ← renderer/dist is copied here (generated)
├── project.yml                    # XcodeGen config (generates the .xcodeproj)
├── scripts/build.sh               # one-shot build
├── scripts/notarize.sh            # notarize → build the .dmg
└── .github/workflows/release.yml  # tag push → sign, notarize, release
```

---

## Requirements

| Tool | Used for | Install |
|---|---|---|
| **Full Xcode** | Building the App Extension (Command Line Tools alone won't do) | App Store |
| Node.js 18+ | Building the renderer | `brew install node` |
| XcodeGen | Generating the `.xcodeproj` | `brew install xcodegen` |

> The `.xcodeproj` is not tracked in Git; it is generated from `project.yml`. To build the
> project by hand from the Xcode GUI instead, see "Manual setup" below.

---

## Build (local)

```bash
# build renderer → copy to Resources → generate .xcodeproj → build, all in one
./scripts/build.sh
```

Then:

1. Move the produced `build/Build/Products/Release/QuickLook3D.app` to `/Applications`
2. **Launch the app once** (registers the extension with macOS)
3. System Settings → General → Login Items & Extensions → **Extensions (Quick Look)** → enable
4. Reload Quick Look: `qlmanage -r && qlmanage -r cache`
5. Test: `qlmanage -p /path/to/model.vrm` (`.vrma` / `.glb` / `.fbx` work too)

> Local builds use ad-hoc signing (`-`). Building unsigned (`CODE_SIGNING_ALLOWED=NO`) means
> the extension won't be registered by `pluginkit`.

---

## Development

### Render in the browser (front end only)

You can iterate on the renderer without building the native side:

```bash
cd renderer
npm install
npm run dev
```

**Drag and drop a `.vrm` / `.vrma` / `.glb` / `.fbx`** onto the page to view it.
A `?url=...` query also loads a remote model directly.

### Develop the native side in Xcode

```bash
./scripts/build.sh        # first run: build renderer → copy to Resources → generate .xcodeproj
open QuickLook3D.xcodeproj
```

> `QuickLook3D/Extension/Resources/renderer/` must exist at `xcodegen generate` time (it's a
> folder reference). `build.sh` does the copy for you.

Running the `QuickLook3D` scheme in Xcode rebuilds the renderer and bundles it into the
extension automatically (via the `project.yml` preBuildScript).

---

## Troubleshooting

- **Preview is blank / nothing shows**
  - Check the logs first (the extension forwards its console to os_log):
    ```bash
    log stream --predicate 'subsystem == "com.sawazen.QuickLook3D"'
    ```
    In another terminal run `qlmanage -p /path/to/x.vrm`.
    Seeing `prepare` → `didFinish` → `... loaded & added to scene` means rendering succeeded.
  - If `didFinish` never appears and the WebContent process crashes, confirm the extension
    entitlements include `com.apple.security.network.client` (required by WKWebView).
  - Confirm the renderer is bundled:
    `build/.../QuickLook3DExtension.appex/Contents/Resources/renderer/index.html`
- **Extension doesn't appear in the list**
  - Did you launch the app once / put it in `/Applications`?
  - Clear the cache: `qlmanage -r && qlmanage -r cache`
  - Check registration: `pluginkit -m | grep -i quicklook3d`
- **Model is sideways / facing away**
  - VRM 0.x coordinate system. `VRMUtils.rotateVRM0()` handles it (already applied).

---

## Implementation notes

- **Sandbox**: the extension runs sandboxed; file access is granted only for the URL passed to
  `preparePreviewOfFile(at:)`. This implementation reads the file on the Swift side and passes
  it to JS as Base64 to work around that.
- **VRM versions**: `@pixiv/three-vrm` supports both VRM 0.x and 1.0. 0.x is corrected with
  `VRMUtils.rotateVRM0()`.
- **Signing**: ad-hoc signing (`CODE_SIGN_IDENTITY="-"`) is enough for your own Mac. For
  distribution to others, see below.

---

## Distribution (signing & notarization)

To run cleanly on other people's Macs you need an **Apple Developer Program** membership
(US$99 / ¥12,980 a year) plus **Developer ID signing + notarization**. Unsigned / ad-hoc
builds are blocked by Gatekeeper, and a quarantined build won't load the sandboxed extension.

### Automated (GitHub Actions)

Pushing a `v*` tag runs `.github/workflows/release.yml`, which **signs → notarizes → builds
the `.dmg` → attaches it to the Release**. Register these repository Secrets first:

| Secret | Contents |
|---|---|
| `MACOS_CERTIFICATE` | Developer ID Application cert (.p12), base64-encoded (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERTIFICATE_PWD` | password for that .p12 |
| `KEYCHAIN_PASSWORD` | any password for the temporary keychain |
| `APPLE_TEAM_ID` | Team ID (10 chars) |
| `NOTARY_APPLE_ID` | Apple ID (email) used for notarization |
| `NOTARY_PASSWORD` | app-specific password (created at appleid.apple.com) |

```bash
git tag v1.0.0 && git push origin v1.0.0   # → a signed .dmg is attached to the Release
```

> When setting these with `gh secret set`, always pass `--repo sawa-zen/quick-look-3d`
> so they don't land on whatever repo is in the current directory.

### Manual

```bash
# 1) build with Developer ID signing
SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/build.sh
# 2) notarize and build the .dmg (through staple)
APPLE_TEAM_ID=XXXXXXXXXX NOTARY_APPLE_ID=you@example.com NOTARY_PASSWORD=app-specific-pw \
  ./scripts/notarize.sh
```

> Instead of an app-specific password you can authenticate notarization with an App Store
> Connect API key (`--key` / `--key-id` / `--issuer`).

### Gotchas (already solved)

- `xcodebuild build` auto-injects `com.apple.security.get-task-allow`, which notarization
  rejects → `build.sh` passes `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` when signing to strip it.
- Notarization requires a secure timestamp → `--timestamp` at signing; Hardened Runtime is
  enabled in `project.yml`.
- CI needs an Xcode new enough to read the `.xcodeproj` format XcodeGen emits → the runner is
  `macos-15` with `latest-stable` Xcode.

---

## Manual setup (without XcodeGen)

1. Create a new **macOS App** in Xcode (Product Name: `QuickLook3D`)
2. Add a **Quick Look Preview Extension** target via **File > New > Target**
3. Reflect the contents of this repo's `QuickLook3D/Extension/PreviewViewController.swift` and
   `Info.plist` (`QLSupportedContentTypes` / `UTImportedTypeDeclarations`)
4. Add `renderer/dist` to the extension target as a **folder reference (blue folder)** named
   `renderer` (a group reference loses the subdirectory, so `subdirectory: "renderer"` fails)

---

## References

- [magicien/VRMQuickLook](https://github.com/magicien/VRMQuickLook) — SceneKit implementation (VRM 0.x)
- [magicien/GLTFQuickLook](https://github.com/magicien/GLTFQuickLook) — reference for the Quick Look extension structure
- [@pixiv/three-vrm](https://github.com/pixiv/three-vrm)
