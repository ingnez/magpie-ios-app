import SwiftUI
import WebKit
import SafariServices

struct RemoteConsoleView: View {
    @ObservedObject var store: GatewayStore
    let destination: ConsoleDestination
    @Environment(\.dismiss) private var dismiss
    @State private var session: ConsoleSession?
    @State private var error: String?
    @State private var downloaded: ConsoleDownload?
    @State private var external: ConsoleExternalURL?
    @State private var reload = UUID()
    @State private var loading = true

    var body: some View {
        NavigationView {
            ZStack {
                if let session = session {
                    ConsoleWebView(session: session, destination: destination, reloadID: reload, loading: $loading, error: $error, downloaded: $downloaded, external: $external)
                }
                if loading { ProgressView().padding().background(MagpieTheme.surface).cornerRadius(10) }
                if let error = error {
                    VStack {
                        MagpieErrorBanner(title: "控制台暂时无法打开", message: error, retryTitle: "重新连接") {
                            Task { await connect() }
                        }.padding()
                        Spacer()
                    }
                }
            }
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("刷新") { error = nil; reload = UUID() } }
            }
        }.navigationViewStyle(.stack)
        .task { await connect() }
        .sheet(item: $downloaded) { item in ConsoleShareSheet(url: item.url) }
        .sheet(item: $external) { item in ConsoleSafariView(url: item.url) }
        .onDisappear { session = nil }
    }
    private func connect() async {
        loading = true; error = nil; session = nil
        let serverID = store.activeServerID
        do {
            let result = try await store.client.consoleSession()
            guard serverID == store.activeServerID else { return }
            session = ConsoleSession(base: result.base, cookies: result.cookies, insecureTLS: result.insecureTLS)
        } catch { self.error = error.localizedDescription; loading = false }
    }
}

private struct ConsoleSession {
    let base: URL
    let cookies: [HTTPCookie]
    let insecureTLS: Bool
}
private struct ConsoleDownload: Identifiable { let id = UUID(); let url: URL }
private struct ConsoleExternalURL: Identifiable { let id = UUID(); let url: URL }

private struct ConsoleWebView: UIViewRepresentable {
    let session: ConsoleSession
    let destination: ConsoleDestination
    let reloadID: UUID
    @Binding var loading: Bool
    @Binding var error: String?
    @Binding var downloaded: ConsoleDownload?
    @Binding var external: ConsoleExternalURL?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        context.coordinator.reloadID = reloadID
        let group = DispatchGroup()
        for cookie in session.cookies {
            group.enter()
            configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) {
            guard let url = destination.url(base: session.base) else { return }
            web.load(URLRequest(url: url))
        }
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.reloadID != reloadID {
            context.coordinator.reloadID = reloadID
            web.reload()
        }
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading(); web.navigationDelegate = nil; web.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        var parent: ConsoleWebView
        var reloadID: UUID?
        private var files: [ObjectIdentifier: URL] = [:]
        init(_ parent: ConsoleWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { parent.loading = true; parent.error = nil }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.loading = false }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        private func fail(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            parent.loading = false; parent.error = error.localizedDescription
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "blob", let origin = URL(string: String(url.absoluteString.dropFirst(5))), sameConsoleOrigin(origin, parent.session.base) {
                decisionHandler(.download)
            } else if sameConsoleOrigin(url, parent.session.base) {
                decisionHandler(action.shouldPerformDownload ? .download : .allow)
            } else if url.absoluteString == "about:blank" { decisionHandler(.allow) }
            else {
                // Only deliberate links can leave the configured origin; redirects cannot.
                if action.navigationType == .linkActivated, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    parent.external = ConsoleExternalURL(url: url)
                }
                decisionHandler(.cancel)
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let http = response.response as? HTTPURLResponse, http.statusCode == 401 {
                parent.error = "控制台会话已失效，请点重新连接。"; parent.loading = false
                decisionHandler(.cancel); return
            }
            let attachment = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased().contains("attachment") == true
            decisionHandler(attachment || !response.canShowMIMEType ? .download : .allow)
        }
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if parent.session.insecureTLS,
               challenge.protectionSpace.host.lowercased() == parent.session.base.host?.lowercased(),
               challenge.protectionSpace.port == (parent.session.base.port ?? 443),
               challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else { completionHandler(.performDefaultHandling, nil) }
        }
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = URL(fileURLWithPath: suggestedFilename).lastPathComponent
                let file = folder.appendingPathComponent(name.isEmpty ? "magpie-export" : name)
                files[ObjectIdentifier(download)] = file
                completionHandler(file)
            } catch { fail(error); completionHandler(nil) }
        }
        func downloadDidFinish(_ download: WKDownload) {
            parent.loading = false
            if let url = files.removeValue(forKey: ObjectIdentifier(download)) { parent.downloaded = ConsoleDownload(url: url) }
        }
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { fail(error) }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url {
                if sameConsoleOrigin(url, parent.session.base) { webView.load(action.request) }
                else if ["https", "http"].contains(url.scheme?.lowercased() ?? "") { parent.external = ConsoleExternalURL(url: url) }
            }
            return nil
        }
        private func presenter(_ web: WKWebView) -> UIViewController? {
            var vc = web.window?.rootViewController
            while let presented = vc?.presentedViewController { vc = presented }
            return vc
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            guard let vc = presenter(webView) else { completionHandler(); return }
            let alert = UIAlertController(title: "Magpie", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler() })
            vc.present(alert, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            guard let vc = presenter(webView) else { completionHandler(false); return }
            let alert = UIAlertController(title: "Magpie", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "确认", style: .default) { _ in completionHandler(true) })
            vc.present(alert, animated: true)
        }
    }
}
private struct ConsoleShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
private struct ConsoleSafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
