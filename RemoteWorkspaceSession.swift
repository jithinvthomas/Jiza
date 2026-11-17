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

    static func terminalURL(_ text: String) -> URL? {
        if let gateway = gateway(text) { return gateway }
        guard var parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let fragment = parts.fragment, fragment.hasPrefix("/client/"), parts.query == nil else { return nil }
        let key = String(fragment.dropFirst("/client/".count))
        parts.fragment = nil
        guard let base = parts.url else { return nil }
        return desktopURL(gateway: base.absoluteString, clientKey: key)
    }
}

struct RemoteWorkspaceSession: View {
    let url: URL
    let dataStore: WKWebsiteDataStore
    var showsInputControls = false
    @State private var isLoading = true
    @State private var error: String?
    @State private var revision = UUID()
    @State private var inputRequest: RemoteWorkspaceInput.Request?
    @State private var inputMessage: String?

    var body: some View {
        RemoteWorkspaceWebView(url: url, dataStore: dataStore, isLoading: $isLoading, error: $error,
                               inputRequest: inputRequest, inputMessage: $inputMessage)
            .id(revision)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsInputControls {
                    HStack {
                        Button { inputRequest = .init(inputID: "keyboard") } label: {
                            Label("Keyboard", systemImage: "keyboard")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityIdentifier("desktopKeyboard")
                        Menu {
                            Button("Touchpad cursor") { inputRequest = .init(inputID: "relative") }
                            Button("Direct touch") { inputRequest = .init(inputID: "absolute") }
                        } label: {
                            Label("Pointer", systemImage: "cursorarrow.motionlines")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityIdentifier("desktopPointer")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .background(.bar)
                    .disabled(isLoading || error != nil)
                }
            }
            .alert("Remote controls", isPresented: Binding(get: { inputMessage != nil }, set: { if !$0 { inputMessage = nil } })) {
                Button("OK") { inputMessage = nil }
            } message: { Text(inputMessage ?? "") }
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

/// Uses Guacamole 1.6's own input controls rather than synthesizing remote keystrokes.
enum RemoteWorkspaceInput {
    struct Request {
        let id = UUID()
        let inputID: String
    }

    static let script = """
    if (!['keyboard', 'relative', 'absolute'].includes(inputID)) return false;
    if (!location.hash.startsWith('#/client/') || !document.querySelector('.client-view')) return false;
    const injector = window.angular?.element(document.body).injector();
    if (!injector) return false;
    const root = injector.get('$rootScope');
    root.$evalAsync(() => root.$broadcast('guacShowMenu'));
    for (let attempt = 0; attempt < 20; attempt++) {
        await new Promise(resolve => setTimeout(resolve, 50));
        const id = inputID === 'keyboard'
            ? (document.getElementById('ime-osk')?.checked ? 'ime-none' : 'ime-osk') : inputID;
        const input = document.getElementById(id);
        if (!input) continue;
        if (input.checked) root.$evalAsync(() => root.$broadcast('guacHideMenu'));
        else input.click();
        return true;
    }
    return false;
    """
}

private struct RemoteWorkspaceWebView: UIViewRepresentable {
    let url: URL
    let dataStore: WKWebsiteDataStore
    @Binding var isLoading: Bool
    @Binding var error: String?
    var inputRequest: RemoteWorkspaceInput.Request?
    @Binding var inputMessage: String?

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

    func updateUIView(_ web: WKWebView, context: Context) {
        guard let request = inputRequest, context.coordinator.lastInputRequest != request.id else { return }
        context.coordinator.lastInputRequest = request.id
        // Restrict page-world interaction to the configured gateway origin after redirects.
        guard web.url?.scheme == url.scheme, web.url?.host == url.host, web.url?.port == url.port else {
            inputMessage = "Return to your Guacamole desktop after signing in, then try again."
            return
        }
        web.callAsyncJavaScript(RemoteWorkspaceInput.script, arguments: ["inputID": request.inputID], in: nil, in: .page) { result in
            if case .success(let value) = result, value as? Bool == true { return }
            inputMessage = "Open a Guacamole desktop first. If your gateway uses different controls, swipe right from its left edge and select the on-screen keyboard or touchpad mouse mode."
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading()
        web.navigationDelegate = nil
        web.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var lastInputRequest: UUID?
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
