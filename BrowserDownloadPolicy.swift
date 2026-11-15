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
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        pressedLink = nil
        let request = UUID()
        linkPressRequest = request
        let point = touch.location(in: web)
        let pageURL = web.url
        resolveLink(at: point) { [weak self] url in
            guard let self, self.linkPressRequest == request, self.web.url == pageURL else { return }
            self.pressedLink = url
        }
        return true
    }
    func resolveLink(at point: CGPoint, completion: @escaping (URL?) -> Void) {
        // Resolve at touch-down so non-link presses can keep native text selection.
        // Arguments are values, never executable page text. The isolated world
        // prevents a website replacing the DOM APIs used by this lookup.
        let script = """
        const viewport = window.visualViewport;
        const px = (viewport?.offsetLeft || 0) + x * (viewport?.width || innerWidth) / width;
        const py = (viewport?.offsetTop || 0) + y * (viewport?.height || innerHeight) / height;
        const link = document.elementFromPoint(px, py)?.closest('a[href]');
        return link?.href || '';
        """
        web.callAsyncJavaScript(script, arguments: ["x": point.x, "y": point.y,
            "width": max(web.bounds.width, 1), "height": max(web.bounds.height, 1)],
            in: nil, in: .defaultClient) { result in
                guard case .success(let value) = result, let text = value as? String,
                      let url = URL(string: text), BrowserModel.isWebURL(url) else { completion(nil); return }
                completion(url)
            }
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        pressedLink != nil && !web.scrollView.isDragging
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        // Give this link-only recognizer priority over native text long presses.
        // It fails for other content, allowing normal text selection to proceed.
        other is UILongPressGestureRecognizer
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // WebKit's touch delivery and scrolling recognizers must not prevent
        // lookup; competing tap and long-press actions remain exclusive.
        !(other is UITapGestureRecognizer || other is UILongPressGestureRecognizer)
    }
    @objc func handleLinkPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .cancelled || gesture.state == .failed {
            pressedLink = nil
            linkPressRequest = UUID()
            return
        }
        // Wait for lift-off: presenting during the touch allows WebKit's link
        // activation/preview gestures to race with the action sheet.
        guard gesture.state == .ended, let url = pressedLink else { return }
        pressedLink = nil
        linkPressRequest = UUID()
        DispatchQueue.main.async { [weak self] in self?.presentLinkActions(for: url) }
    }
    private func presentLinkActions(for url: URL) {
        // ASVS 2.2.1: keep the existing web-URL allowlist at the UI boundary.
        guard BrowserModel.isWebURL(url), let owner, owner.selectedID == id,
              owner.linkActionTarget == nil else { return }
        owner.linkActionTarget = BrowserLinkTarget(url: url, tab: self)
    }
    func shareLink(_ url: URL) {
        guard BrowserModel.isWebURL(url), var controller = web.window?.rootViewController else { return }
        while let presented = controller.presentedViewController { controller = presented }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = web
        sheet.popoverPresentationController?.sourceRect = CGRect(x: web.bounds.midX, y: web.bounds.midY, width: 1, height: 1)
        controller.present(sheet, animated: true)
    }
}
