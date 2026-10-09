import SwiftUI
import WebKit

enum TradingNavigationPolicy {
    static let dashboardURL = URL(string: "https://trade.jiza.app")!

    static func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        return true
    }
}

struct TradingDashboardView: View {
    @State private var reloadID = UUID()
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        TradingDashboardWebView(isLoading: $isLoading, loadError: $loadError)
            .id(reloadID)
            .background(Color(uiColor: .systemBackground))
            .overlay {
                if let loadError {
                    VStack(spacing: 14) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("Trading could not connect")
                            .font(.headline)
                        Text(loadError)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try again") { reload() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                    .accessibilityIdentifier("tradingConnectionError")
                } else if isLoading {
                    ProgressView("Loading Trading")
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: reload) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh Trading")
                }
            }
    }

    private func reload() {
        loadError = nil
        isLoading = true
        reloadID = UUID()
    }
}

private struct TradingDashboardWebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, loadError: $loadError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.accessibilityIdentifier = "tradingDashboardWebView"
        webView.load(URLRequest(url: TradingNavigationPolicy.dashboardURL, timeoutInterval: 30))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding private var isLoading: Bool
        @Binding private var loadError: String?

        init(isLoading: Binding<Bool>, loadError: Binding<String?>) {
            _isLoading = isLoading
            _loadError = loadError
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
            loadError = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, TradingNavigationPolicy.allows(url) else {
                decisionHandler(.cancel)
                loadError = "Trading links must use a secure HTTPS connection."
                isLoading = false
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let url = navigationAction.request.url, TradingNavigationPolicy.allows(url) else { return nil }
            webView.load(navigationAction.request)
            return nil
        }

        private func fail(_ error: Error) {
            isLoading = false
            loadError = error.localizedDescription
        }
    }
}
