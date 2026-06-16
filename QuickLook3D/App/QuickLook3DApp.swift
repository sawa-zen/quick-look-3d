import SwiftUI

/// The host app.
/// It exists only because a Quick Look extension must be shipped inside an app;
/// the app itself does the bare minimum (just shows an explanation).
@main
struct QuickLook3DApp: App {
    var body: some Scene {
        WindowGroup("3D Quick Look") {
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

            Text("3D Quick Look")
                .font(.title.bold())

            Text("Launch this app once, then select a\n.vrm / .vrma / .glb / .fbx in Finder and press Space\nto preview it in 3D.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(40)
        .frame(width: 460)
    }
}
