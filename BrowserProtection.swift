import Foundation
import WebKit
import Combine
import CryptoKit

@MainActor
final class BrowserProtection: ObservableObject {
    @Published private(set) var adBlockEnabled: Bool
    @Published private(set) var blockPopups: Bool
    @Published private(set) var ready = false
    @Published var error: String?
    private let defaults: UserDefaults
    private var rules: WKContentRuleList?
    private var waiting: [() -> Void] = []
    private var views: [WeakBrowserView] = []
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        adBlockEnabled = defaults.bool(forKey: "jizaAdBlock")
        blockPopups = defaults.object(forKey: "jizaBlockPopups") as? Bool ?? true
        Task { [weak self] in
            guard let self else { return }
            do { self.rules = try await Self.compiledRules() }
            catch { self.error = "Ad blocker could not start: " + error.localizedDescription }
            self.ready = true
            self.apply(reload: false)
            let waiting = self.waiting; self.waiting = []; waiting.forEach { $0() }
        }
    }
    func whenReady(_ action: @escaping () -> Void) { if ready || !adBlockEnabled { action() } else { waiting.append(action) } }
    func register(_ web: WKWebView) { views.append(WeakBrowserView(web)); apply(to: web) }
    func setAdBlock(_ enabled: Bool) {
        adBlockEnabled = enabled; defaults.set(enabled, forKey: "jizaAdBlock"); apply(reload: true)
    }
    func setPopups(_ blocked: Bool) {
        blockPopups = blocked; defaults.set(blocked, forKey: "jizaBlockPopups"); apply(reload: false)
    }
    private func apply(reload: Bool) {
        views.removeAll { $0.web == nil }
        for view in views { if let web = view.web { apply(to: web); if reload { web.reload() } } }
    }
    private func apply(to web: WKWebView) {
        web.configuration.preferences.javaScriptCanOpenWindowsAutomatically = !blockPopups
        if let rules {
            web.configuration.userContentController.remove(rules)
            if adBlockEnabled { web.configuration.userContentController.add(rules) }
        }
    }
    private static var compilation: Task<WKContentRuleList, Error>?
    private static func compiledRules() async throws -> WKContentRuleList {
        if let compilation { return try await compilation.value }
        let task = Task { @MainActor () throws -> WKContentRuleList in
            let encoded = try rulesJSON()
            let fingerprint = SHA256.hash(data: Data(encoded.utf8)).map { String(format: "%02x", $0) }.joined()
            let identifier = "Jiza-EasyList-" + fingerprint
            return try await withCheckedThrowingContinuation { continuation in
                let store = WKContentRuleListStore.default()!
                store.lookUpContentRuleList(forIdentifier: identifier) { existing, _ in
                    if let existing { continuation.resume(returning: existing); return }
                    store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: encoded) { rules, error in
                        if let rules { continuation.resume(returning: rules) }
                        else { continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile)) }
                    }
                }
            }
        }
        compilation = task
        return try await task.value
    }
    nonisolated static func rulesJSON() throws -> String {
        guard let url = Bundle.main.url(forResource: "BrowserAdDomains", withExtension: "json"),
              var rules = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]] else { throw CocoaError(.fileReadNoSuchFile) }
        for path in ["ads", "adserver", "adverts"] {
            rules.append(["trigger": ["url-filter": "^https?://.*/" + path + "/", "resource-type": ["script", "image", "raw", "document"]], "action": ["type": "block"]])
        }
        rules.append(["trigger": ["url-filter": ".*"], "action": ["type": "css-display-none", "selector": "ins.adsbygoogle, .adsbygoogle, [id^='google_ads_iframe'], .advertisement, .ad-banner, .ad-container, [data-ad-slot]"]])
        return String(decoding: try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]), as: UTF8.self)
    }
}
private final class WeakBrowserView { weak var web: WKWebView?; init(_ web: WKWebView) { self.web = web } }