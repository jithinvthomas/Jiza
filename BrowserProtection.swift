import Foundation
import WebKit
import Combine

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
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "JizaAds-v2", encodedContentRuleList: Self.rulesJSON) { [weak self] list, error in
            guard let self else { return }
            self.rules = list; self.ready = true
            if error != nil { self.error = "Ad blocker could not start. Retry by reopening Jiza." }
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
    nonisolated static var rulesJSON: String {
        let domains = ["doubleclick.net", "googlesyndication.com", "googleadservices.com", "googletagservices.com", "adservice.google.com", "amazon-adsystem.com", "ads.yahoo.com", "advertising.com", "adnxs.com", "adsrvr.org", "criteo.com", "criteo.net", "taboola.com", "outbrain.com", "pubmatic.com", "rubiconproject.com", "openx.net", "casalemedia.com", "smartadserver.com", "adform.net", "media.net", "mgid.com", "revcontent.com", "propellerads.com", "popads.net", "popcash.net", "exoclick.com", "trafficjunky.net", "juicyads.com", "adsterra.com", "adroll.com", "yieldmo.com", "sharethrough.com", "indexww.com", "33across.com", "lijit.com", "sovrn.com", "sonobi.com", "inmobi.com", "unityads.unity3d.com", "applovin.com", "vungle.com", "chartboost.com", "moatads.com", "doubleverify.com", "adsafeprotected.com"]
        var rules: [[String: Any]] = domains.map { domain in
            ["trigger": ["url-filter": "^https?://([^/]+\\.)?" + domain.replacingOccurrences(of: ".", with: "\\.") + "[:/]"], "action": ["type": "block"]]
        }
        for path in ["ads", "adserver", "adverts"] {
            rules.append(["trigger": ["url-filter": "^https?://.*/" + path + "/", "resource-type": ["script", "image", "raw", "document"]], "action": ["type": "block"]])
        }
        rules.append(["trigger": ["url-filter": ".*"], "action": ["type": "css-display-none", "selector": "ins.adsbygoogle, .adsbygoogle, [id^='google_ads_iframe'], .advertisement, .ad-banner, .ad-container, [data-ad-slot]"]])
        let data = try! JSONSerialization.data(withJSONObject: rules)
        return String(decoding: data, as: UTF8.self)
    }
}
private final class WeakBrowserView { weak var web: WKWebView?; init(_ web: WKWebView) { self.web = web } }
