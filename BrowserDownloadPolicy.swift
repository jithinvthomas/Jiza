import Foundation
import WebKit

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
        completionHandler(UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] suggested in
            let download = UIAction(title: "Download link", image: UIImage(systemName: "arrow.down.circle")) { [weak self] _ in self?.downloadLink(url) }
            return UIMenu(children: [download] + suggested)
        })
    }
}
