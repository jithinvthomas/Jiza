import Foundation
import WebKit
import UIKit
import Combine

struct BrowserPage: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var url: URL
    var date = Date()
}

struct BrowserSession: Codable {
    var urls: [URL]
    var selected: Int
}

@MainActor
final class BrowserModel: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var selectedID: UUID?
    @Published var bookmarks: [BrowserPage] = []
    @Published var history: [BrowserPage] = []
    @Published var error: String?
    @Published var downloadNotice = 0
    var automaticallyDownloadFiles: Bool {
        get { defaults.object(forKey: "jizaAutoDownloads") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "jizaAutoDownloads"); objectWillChange.send() }
    }
    let downloads = BrowserDownloads()
    let protection: BrowserProtection
    let defaults: UserDefaults
    private var privateStore = WKWebsiteDataStore.nonPersistent()
    var selected: BrowserTab? { tabs.first { $0.id == selectedID } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        protection = BrowserProtection(defaults: defaults)
        bookmarks = decode([BrowserPage].self, key: "jizaBookmarks") ?? []
        history = decode([BrowserPage].self, key: "jizaHistory") ?? []
        if let session = decode(BrowserSession.self, key: "jizaBrowserSession") {
            for url in session.urls.prefix(30) where Self.isWebURL(url) { _ = newTab(url: url, save: false) }
            if tabs.indices.contains(session.selected) { selectedID = tabs[session.selected].id }
        }
        if tabs.isEmpty { _ = newTab(save: false) }
    }

    nonisolated static func isWebURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") &&
        !(url.host ?? "").isEmpty && url.user == nil && url.password == nil
    }
    nonisolated static func addressURL(_ value: String) -> URL? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("://") {
            guard let url = URL(string: text), isWebURL(url) else { return nil }
            return url
        }
        if !text.contains(where: { $0.isWhitespace }), text.contains("."),
           let url = URL(string: "https://" + text), isWebURL(url) { return url }
        var query = URLComponents(string: "https://www.google.com/search")!
        query.queryItems = [URLQueryItem(name: "q", value: text)]
        return query.url
    }
    nonisolated static func isVideoWebsite(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return ["youtube.com", "youtu.be", "youtube-nocookie.com", "vimeo.com", "dailymotion.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
    @discardableResult
    func newTab(url: URL? = nil, isPrivate: Bool = false, configuration: WKWebViewConfiguration? = nil, save: Bool = true) -> BrowserTab {
        let config = configuration ?? WKWebViewConfiguration()
        config.websiteDataStore = isPrivate ? privateStore : .default()
        config.allowsInlineMediaPlayback = true
        let tab = BrowserTab(configuration: config, isPrivate: isPrivate, owner: self)
        protection.register(tab.web)
        tabs.append(tab)
        selectedID = tab.id
        if let url, Self.isWebURL(url) { tab.web.load(URLRequest(url: url)) }
        if save { persistSession() }
        return tab
    }
    func close(_ tab: BrowserTab) {
        tab.web.stopLoading()
        tab.web.loadHTMLString("", baseURL: nil)
        tabs.removeAll { $0.id == tab.id }
        if selectedID == tab.id { selectedID = tabs.last?.id }
        if !tabs.contains(where: { $0.isPrivate }) { privateStore = .nonPersistent() }
        if tabs.isEmpty { _ = newTab() }
        persistSession()
    }
    func navigate(_ text: String) {
        guard let url = Self.addressURL(text), let tab = selected else { error = "Enter a website address or search words."; return }
        tab.web.load(URLRequest(url: url))
    }
    func openWebsite(_ url: URL) { _ = newTab(url: url) }
    func visit(_ tab: BrowserTab) {
        guard let url = tab.web.url, Self.isWebURL(url) else { return }
        if !tab.isPrivate {
            history.removeAll { $0.url == url }
            history.insert(BrowserPage(title: tab.web.title ?? url.host ?? "Website", url: url), at: 0)
            history = Array(history.prefix(500))
            encode(history, key: "jizaHistory")
        }
        persistSession()
    }
    func bookmark() {
        guard let tab = selected, let url = tab.web.url, Self.isWebURL(url) else { return }
        bookmark(url, title: tab.web.title)
    }
    func bookmark(_ url: URL, title: String? = nil) {
        guard Self.isWebURL(url) else { return }
        bookmarks.removeAll { $0.url == url }
        bookmarks.insert(BrowserPage(title: title ?? url.host ?? "Website", url: url), at: 0)
        encode(bookmarks, key: "jizaBookmarks")
    }
    func deleteBookmark(_ id: UUID) { bookmarks.removeAll { $0.id == id }; encode(bookmarks, key: "jizaBookmarks") }
    func clearHistory() { history = []; encode(history, key: "jizaHistory") }
    func removeHistory(_ id: UUID) { history.removeAll { $0.id == id }; encode(history, key: "jizaHistory") }
    func persistSession() {
        let normal = tabs.filter { !$0.isPrivate }
        let urls = normal.compactMap { $0.web.url }.filter(Self.isWebURL)
        let selectedURL = selected?.isPrivate == false ? selected?.web.url : nil
        encode(BrowserSession(urls: urls, selected: urls.firstIndex(where: { $0 == selectedURL }) ?? 0), key: "jizaBrowserSession")
    }
    private func encode<T: Encodable>(_ value: T, key: String) { if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) } }
    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? { defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) } }
}

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let isPrivate: Bool
    let web: WKWebView
    weak var owner: BrowserModel?
    @Published var revision = 0
    @Published var desktop = false
    @Published var pageError: String?
    var popupParentID: UUID?
    private var committed = false
    private var observations: [NSKeyValueObservation] = []
    init(configuration: WKWebViewConfiguration, isPrivate: Bool, owner: BrowserModel) {
        self.isPrivate = isPrivate
        self.owner = owner
        web = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.allowsLinkPreview = true
        let refresh = UIRefreshControl()
        refresh.accessibilityLabel = "Refresh page"
        refresh.addTarget(self, action: #selector(refreshPage), for: .valueChanged)
        web.scrollView.refreshControl = refresh
        web.scrollView.alwaysBounceVertical = true
        func watch<T>(_ path: KeyPath<WKWebView, T>) {
            observations.append(web.observe(path, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.revision += 1
                    if !self.web.isLoading { self.web.scrollView.refreshControl?.endRefreshing() }
                    self.owner?.objectWillChange.send()
                }
            })
        }
        watch(\.url); watch(\.title); watch(\.estimatedProgress); watch(\.isLoading); watch(\.canGoBack); watch(\.canGoForward)
    }
    func setDesktop(_ enabled: Bool) {
        desktop = enabled
        web.customUserAgent = enabled ? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15" : nil
        web.reload()
    }
    @objc func refreshPage() {
        pageError = nil
        if web.reload() == nil { web.scrollView.refreshControl?.endRefreshing() }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { pageError = nil }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { committed = true; owner?.visit(self) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }
    private func report(_ error: Error) { if (error as NSError).code != NSURLErrorCancelled { pageError = error.localizedDescription } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        web.scrollView.refreshControl?.endRefreshing()
        pageError = "This page stopped responding. Reload to continue."
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        // Only web navigation; never execute pasted script/file/custom-scheme URLs.
        guard BrowserModel.isWebURL(url) || ["about", "blob"].contains(url.scheme ?? "") else {
            pageError = "This link requires another app or uses an unsupported address."
            decisionHandler(.cancel); return
        }
        let file = owner?.automaticallyDownloadFiles == true && action.targetFrame?.isMainFrame != false && BrowserDownloadPolicy.isFileLink(url)
        if action.shouldPerformDownload || file {
            if action.targetFrame == nil {
                owner?.downloads.start(action.request, web: webView, isPrivate: isPrivate)
                decisionHandler(.cancel)
            } else { decisionHandler(.download) }
        } else if let protection = owner?.protection {
            protection.whenReady { decisionHandler(.allow) }
        } else { decisionHandler(.allow) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let attachment = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased().contains("attachment") == true
        let media = BrowserDownloadPolicy.shouldDownload(mime: response.response.mimeType, disposition: nil, mainFrame: response.isForMainFrame, enabled: owner?.automaticallyDownloadFiles == true)
        decisionHandler(attachment || media || !response.canShowMIMEType ? .download : .allow)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { acceptDownload(download, web: webView) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { acceptDownload(download, web: webView) }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard action.targetFrame == nil, let url = action.request.url, BrowserModel.isWebURL(url) else { return nil }
        if owner?.automaticallyDownloadFiles == true && BrowserDownloadPolicy.isFileLink(url) {
            owner?.downloads.start(action.request, web: webView, isPrivate: isPrivate)
            return nil
        }
        if owner?.protection.blockPopups == true && action.navigationType != .linkActivated {
            pageError = "Pop-up blocked. You can allow pop-ups in Browser protection."
            return nil
        }
        let tab = owner?.newTab(isPrivate: isPrivate, configuration: configuration)
        tab?.popupParentID = id
        return tab?.web
    }
    private func acceptDownload(_ download: WKDownload, web: WKWebView) {
        owner?.downloads.accept(download, web: web, isPrivate: isPrivate)
        owner?.downloadNotice += 1
        if !committed, let parent = popupParentID, let owner {
            owner.tabs.removeAll { $0.id == id }
            owner.selectedID = owner.tabs.first(where: { $0.id == parent })?.id ?? owner.tabs.first?.id
            owner.persistSession()
        }
    }
    func webViewDidClose(_ webView: WKWebView) { owner?.close(self) }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        dialog(message, host: frame.request.url?.host, completion: { _ in completionHandler() })
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        dialog(message, host: frame.request.url?.host, cancel: true, completion: { completionHandler($0 != nil) })
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        dialog(prompt, host: frame.request.url?.host, cancel: true, input: defaultText ?? "", completion: completionHandler)
    }
    private func dialog(_ message: String, host: String?, cancel: Bool = false, input: String? = nil, completion: @escaping (String?) -> Void) {
        guard var controller = web.window?.rootViewController else { completion(nil); return }
        while let presented = controller.presentedViewController { controller = presented }
        guard !(controller is UIAlertController) else { completion(nil); return }
        let alert = UIAlertController(title: host ?? "Website", message: message, preferredStyle: .alert)
        if let input { alert.addTextField { $0.text = input } }
        if cancel { alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(nil) }) }
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion(alert.textFields?.first?.text ?? "") })
        controller.present(alert, animated: true)
    }
}
