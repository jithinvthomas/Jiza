import SwiftUI
import WebKit

enum RemoteWorkspacePolicy {
    static func gateway(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              allowsNavigation(url), url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    static func allowsNavigation(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host ?? "").isEmpty
            && url.user == nil && url.password == nil
    }

    static func desktopURL(gateway: String, clientKey: String) -> URL? {
        guard let base = self.gateway(gateway),
              clientKey.range(of: "^[A-Za-z0-9_+/=-]{1,256}$", options: .regularExpression) != nil else { return nil }
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)
        parts?.fragment = "/client/\(clientKey)"
        return parts?.url
    }
}

struct RemoteWorkspaceSession: View {
    let url: URL
    let dataStore: WKWebsiteDataStore
    @State private var isLoading = true
    @State private var error: String?
    @State private var revision = UUID()

    var body: some View {
        RemoteWorkspaceWebView(url: url, dataStore: dataStore, isLoading: $isLoading, error: $error)
            .id(revision)
            .overlay {
                if let error {
                    VStack(spacing: 16) {
                        Image(systemName: "network.slash").font(.largeTitle)
                        Text("Connection unavailable").font(.headline)
                        Text(error).multilineTextAlignment(.center)
                        Text("Check that your private network and gateway are available.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Try again") { self.error = nil; isLoading = true; revision = UUID() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                    .accessibilityIdentifier("workspaceConnectionError")
                } else if isLoading {
                    ProgressView("Connecting")
                        .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
    }
}

private struct RemoteWorkspaceWebView: UIViewRepresentable {
    let url: URL
    let dataStore: WKWebsiteDataStore
    @Binding var isLoading: Bool
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator(isLoading: $isLoading, error: $error) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .black
        web.accessibilityIdentifier = "remoteWorkspaceWebView"
        guard RemoteWorkspacePolicy.allowsNavigation(url) else { return web }
        web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading()
        web.navigationDelegate = nil
        web.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding var isLoading: Bool
        @Binding var error: String?
        init(isLoading: Binding<Bool>, error: Binding<String?>) { _isLoading = isLoading; _error = error }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true; error = nil
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { isLoading = false }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        private func fail(_ failure: Error) {
            guard (failure as NSError).code != NSURLErrorCancelled else { return }
            isLoading = false; error = failure.localizedDescription
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url,
                  RemoteWorkspacePolicy.allowsNavigation(url) || (url.absoluteString == "about:blank" && action.targetFrame?.isMainFrame == false) else {
                isLoading = false; error = "Remote connections must use HTTPS without embedded passwords."
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
                isLoading = false; error = "The gateway returned HTTP \(http.statusCode). Check its address and sign-in configuration."
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, RemoteWorkspacePolicy.allowsNavigation(url), action.navigationType == .linkActivated {
                webView.load(action.request)
            }
            return nil
        }
    }
}
