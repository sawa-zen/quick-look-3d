import SwiftUI

/// The host app.
/// It exists only because a Quick Look extension must be shipped inside an app;
/// the app itself does the bare minimum (just shows an explanation).
@main
struct QuickLook3DApp: App {
    var body: some Scene {
        WindowGroup("Quick Look 3D") {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Quick Look 3D")
                .font(.title.bold())

            Text("Setup complete — you can close this window.\nThe Quick Look extension stays registered, even after a restart.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Select a .vrm / .vrma / .glb / .fbx in Finder\nand press Space to preview it in 3D.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(40)
        .frame(width: 460)
    }
}
