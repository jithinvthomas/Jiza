import Foundation
import WebKit
import UIKit

/// Navigation downloads only: embedded players remain usable inside webpages.
enum BrowserDownloadPolicy {
    static let extensions: Set<String> = ["mp4", "m4v", "mov", "mkv", "webm", "avi", "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "zip", "rar", "7z", "gz", "tar", "pdf", "epub", "dmg", "exe", "msi", "apk", "ipa", "iso", "torrent", "doc", "docx", "xls", "xlsx", "ppt", "pptx"]
    static func isFileLink(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }
    static func shouldDownload(mime: String?, disposition: String?, mainFrame: Bool, enabled: Bool) -> Bool {
        if disposition?.lowercased().contains("attachment") == true { return true }
        guard enabled, mainFrame else { return false }
        let value = mime?.lowercased() ?? ""
        return value.hasPrefix("video/") || value.hasPrefix("audio/") || ["application/octet-stream", "application/x-bittorrent", "application/zip", "application/x-rar-compressed", "application/pdf"].contains(value)
    }
}

struct BrowserMediaLink: Identifiable {
    let url: URL
    let label: String
    var id: String { url.absoluteString }
}

@MainActor
extension BrowserTab {
    func downloadLink(_ url: URL) {
        guard BrowserModel.isWebURL(url) || url.scheme == "blob" else { pageError = "Only direct web files can be downloaded here."; return }
        owner?.downloads.start(URLRequest(url: url), web: web, isPrivate: isPrivate)
    }
    func findMedia() async -> [BrowserMediaLink] {
        // Constant extraction code; page data is never interpolated into executable JS.
        let script = #"Array.from(document.querySelectorAll('video,audio,video source,audio source,a[download]')).slice(0,200).map(e=>({url:e.currentSrc||e.src||e.href||'',label:e.getAttribute('download')||e.getAttribute('title')||e.tagName.toLowerCase()}))"#
        guard let rows = try? await web.evaluateJavaScript(script) as? [[String: String]] else { return [] }
        var seen = Set<URL>()
        return rows.compactMap { row in
            guard let text = row["url"], let url = URL(string: text), BrowserModel.isWebURL(url), seen.insert(url).inserted else { return nil }
            return BrowserMediaLink(url: url, label: row["label"] ?? url.lastPathComponent)
        }
    }
    func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo, completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        guard let url = elementInfo.linkURL, BrowserModel.isWebURL(url) else { completionHandler(nil); return }
        // An explicit empty configuration prevents WebKit's default link-preview
        // fallback. Returning nil can put that preview above the action sheet.
        completionHandler(UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in UIMenu(children: []) })
        DispatchQueue.main.async { [weak self] in self?.presentLinkActions(for: url) }
    }
    private func presentLinkActions(for url: URL) {
        // ASVS 2.2.1: keep the existing web-URL allowlist at the UI boundary.
        guard BrowserModel.isWebURL(url), var presenter = web.window?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !(presenter is UIAlertController), !presenter.isBeingDismissed else { return }
        let sheet = UIAlertController(title: "Link actions", message: url.host, preferredStyle: .actionSheet)
        func add(_ title: String, action: @escaping () -> Void) {
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak sheet] _ in
                // Finish dismissal before replacing the web view or sharing.
                if let sheet, sheet.presentingViewController?.presentedViewController === sheet {
                    sheet.dismiss(animated: true, completion: action)
                } else { action() }
            })
        }
        add("Open in new tab") { [weak self] in
            guard let self else { return }
            self.owner?.newTab(url: url, isPrivate: self.isPrivate)
        }
        add("Open in private tab") { [weak self] in self?.owner?.newTab(url: url, isPrivate: true) }
        add("Download link") { [weak self] in self?.downloadLink(url) }
        add("Save bookmark") { [weak self] in self?.owner?.bookmark(url) }
        add("Copy link") { UIPasteboard.general.url = url }
        add("Share link") { [weak self] in self?.shareLink(url) }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = web
        sheet.popoverPresentationController?.sourceRect = CGRect(x: web.bounds.midX, y: web.bounds.midY, width: 1, height: 1)
        presenter.present(sheet, animated: true)
    }
    private func shareLink(_ url: URL) {
        guard var controller = web.window?.rootViewController else { return }
        while let presented = controller.presentedViewController { controller = presented }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = web
        sheet.popoverPresentationController?.sourceRect = CGRect(x: web.bounds.midX, y: web.bounds.midY, width: 1, height: 1)
        controller.present(sheet, animated: true)
    }
}
