import Cocoa
import os
import Quartz
import WebKit

/// A QL extension has no visible console, so it's hard to debug. Forward the lifecycle
/// and the JS console to os_log. To inspect:
///   log stream --predicate 'subsystem == "com.sawazen.QuickLook3D"'
private let qlLog = Logger(subsystem: "com.sawazen.QuickLook3D", category: "preview")

private func debugLog(_ message: String) {
    qlLog.log("\(message, privacy: .public)")
}

/// View controller that previews 3D models in Quick Look.
///
/// Structure:
///   - displays Resources/renderer/index.html (the front end bundled into one file by Vite) in a WKWebView
///   - passes the file contents to JS as Base64 via window.postMessage
///   - the JS side (three-vrm) renders it with WebGL
final class PreviewViewController: NSViewController, QLPreviewingController {

    private var webView: WKWebView!

    /// Base64 of the model to hand to JS. Injected after the page finishes loading.
    private var pendingBase64: String?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false

        // Receiver that forwards the JS console to os_log (for debugging).
        // Inspect with `log stream --predicate 'subsystem == "com.sawazen.QuickLook3D"'`.
        config.userContentController.add(self, name: "log")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        // The background is painted by the HTML (body background), so no WKWebView setting needed.
        self.view = webView
    }

    // MARK: - QLPreviewingController

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        // Even under the sandbox, the URL passed to preparePreviewOfFile is readable.
        // Open the security scope before reading the file.
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            handler(NSError(
                domain: "QuickLook3D",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not read the file."]
            ))
            return
        }
        pendingBase64 = data.base64EncodedString()
        debugLog("prepare: read \(data.count) bytes, base64 \(pendingBase64?.count ?? 0) chars")

        // Load the bundled single HTML file.
        // allowingReadAccessTo gets the directory that HTML lives in.
        guard let htmlURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "renderer"
        ) else {
            handler(NSError(
                domain: "QuickLook3D",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "renderer/index.html not found."]
            ))
            return
        }

        debugLog("prepare: loading html \(htmlURL.path)")
        webView.loadFileURL(
            htmlURL,
            allowingReadAccessTo: htmlURL.deletingLastPathComponent()
        )

        // The page is ready to display, so tell Quick Look we're done.
        // The actual model rendering happens asynchronously once the page loads (didFinish).
        handler(nil)
    }
}

// MARK: - WKNavigationDelegate

extension PreviewViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let base64 = pendingBase64 else { return }
        pendingBase64 = nil
        debugLog("didFinish: injecting VRM (\(base64.count) base64 chars)")

        // Base64 is only [A-Za-z0-9+/=], so it embeds safely inside single quotes.
        let script = "window.postMessage({ type: 'loadVRM', base64: '\(base64)' }, '*');"
        webView.evaluateJavaScript(script) { _, error in
            if let error { debugLog("inject failed: \(error.localizedDescription)") } else { debugLog("inject ok") }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        debugLog("navigation failed: \(error.localizedDescription)")
    }
}

// MARK: - WKScriptMessageHandler (JS console → os_log)

extension PreviewViewController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "log" else { return }
        debugLog("[JS] \(String(describing: message.body))")
    }
}
