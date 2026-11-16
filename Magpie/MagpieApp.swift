import SwiftUI
import WebKit

@main
struct MagpieApp: App {
    init() {
        MagpieLocalGateway.shared.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            MagpieRootView()
                .preferredColorScheme(.dark)
        }
    }
}

struct MagpieRootView: View {
    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.059, blue: 0.098)
                .ignoresSafeArea()
            MagpieWebView()
                .ignoresSafeArea()
        }
    }
}

struct MagpieWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        let bg = UIColor(red: 0.043, green: 0.059, blue: 0.098, alpha: 1.0)
        webView.backgroundColor = bg
        webView.scrollView.backgroundColor = bg
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "www") {
            webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        } else {
            let fallbackHTML = """
            <!doctype html><html><body style="background:#0b0f19;color:#f1f5f9;font-family:-apple-system;padding:32px;">
            <h2>Magpie Gateway</h2><p>Local gateway active on http://127.0.0.1:3425</p></body></html>
            """
            webView.loadHTMLString(fallbackHTML, baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
