import XCTest
import WebKit
@testable import InteraMusic

@MainActor
final class BrowserModelTests: XCTestCase {
    private func model() -> BrowserModel { BrowserModel(defaults: UserDefaults(suiteName: UUID().uuidString)!) }
    func testAddressAndVideoWebsiteRouting() {
        XCTAssertEqual(BrowserModel.addressURL("jiza.app")?.absoluteString, "https://jiza.app")
        XCTAssertEqual(URLComponents(url: BrowserModel.addressURL("music & video")!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "music & video")
        XCTAssertNil(BrowserModel.addressURL("file:///etc/passwd"))
        XCTAssertNil(BrowserModel.addressURL("https://user:secret@example.com"))
        XCTAssertTrue(BrowserModel.isVideoWebsite(URL(string: "https://m.youtube.com/watch?v=123")!))
        XCTAssertTrue(BrowserModel.isVideoWebsite(URL(string: "https://youtu.be/123")!))
        XCTAssertFalse(BrowserModel.isVideoWebsite(URL(string: "https://youtube.com.evil.test/video")!))
    }
    func testPrivateTabsUseEphemeralStoreAndCloseSafely() {
        let browser = model()
        let normal = browser.selected!
        XCTAssertTrue(normal.web.configuration.websiteDataStore.isPersistent)
        let first = browser.newTab(isPrivate: true)
        let second = browser.newTab(isPrivate: true)
        XCTAssertFalse(first.web.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(first.web.configuration.websiteDataStore === second.web.configuration.websiteDataStore)
        let previousStore = first.web.configuration.websiteDataStore
        browser.close(first); browser.close(second)
        XCTAssertEqual(browser.selectedID, normal.id)
        let fresh = browser.newTab(isPrivate: true)
        XCTAssertFalse(fresh.web.configuration.websiteDataStore === previousStore)
        browser.close(fresh); browser.close(normal)
        XCTAssertEqual(browser.tabs.count, 1)
    }
    func testPrivateVisitsNeverPersistHistoryOrSession() async throws {
        let browser = model()
        let tab = browser.newTab(isPrivate: true)
        tab.web.loadHTMLString("<title>Private page</title>", baseURL: URL(string: "https://private.example")!)
        for _ in 0..<100 {
            if tab.web.url != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        browser.visit(tab)
        XCTAssertTrue(browser.history.isEmpty)
        let data = try XCTUnwrap(browser.defaults.data(forKey: "jizaBrowserSession"))
        let session = try JSONDecoder().decode(BrowserSession.self, from: data)
        XCTAssertTrue(session.urls.isEmpty)
    }
    func testDownloadNamesCannotEscapeFolderOrOverwriteFiles() throws {
        XCTAssertEqual(BrowserDownloads.safeFilename("../../movie.mp4"), "movie.mp4")
        XCTAssertEqual(BrowserDownloads.safeFilename("..\\..\\movie.mp4"), "movie.mp4")
        XCTAssertEqual(BrowserDownloads.safeFilename(".."), "download")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("movie.mp4")
        try Data([1, 2, 3]).write(to: existing)
        let proposed = BrowserDownloads.unusedURL(in: root, name: "../movie.mp4")
        XCTAssertEqual(proposed.deletingLastPathComponent().standardizedFileURL.path, root.standardizedFileURL.path)
        XCTAssertNotEqual(proposed, existing)
        XCTAssertEqual(try Data(contentsOf: existing), Data([1, 2, 3]))
    }

    func testDownloadFailurePreservesDestinationError() {
        let owner = BrowserDownloads()
        let item = BrowserDownload(saved: SavedDownload(name: "file.txt", date: Date()),
                                   url: BrowserDownloads.directory.appendingPathComponent("file.txt"), owner: owner)
        item.localURL = nil
        item.status = "Server returned HTTP 403. Sign in or refresh the download link, then retry."
        let message = item.status
        item.recordFailure(URLError(.cancelled), resumeData: nil)
        XCTAssertEqual(item.status, message)
        XCTAssertFalse(item.active)

        item.active = true
        item.recordFailure(URLError(.networkConnectionLost), resumeData: Data([1]))
        XCTAssertTrue(item.status.hasPrefix("Failed: "))
        XCTAssertTrue(item.canResume)
    }

    func testPauseDoesNotExposeActionsBeforeCancellationCompletes() {
        let owner = BrowserDownloads()
        let item = BrowserDownload(saved: SavedDownload(name: "file.txt", date: Date()),
                                   url: BrowserDownloads.directory.appendingPathComponent("file.txt"), owner: owner)
        item.active = true
        item.canRetry = true
        item.canResume = true
        item.beginCancellation()
        XCTAssertFalse(item.active)
        XCTAssertFalse(item.canRetry)
        XCTAssertFalse(item.canResume)
        item.recordFailure(URLError(.cancelled), resumeData: Data([9]))
        XCTAssertFalse(item.canResume)
        item.finishCancellation(Data([1]))
        XCTAssertTrue(item.canResume)
        XCTAssertFalse(item.canRetry)
        item.finishCancellation(nil) // A duplicate or late callback cannot erase resume data.
        XCTAssertTrue(item.canResume)
    }
}

extension BrowserModelTests {
    func testHTTPFailureMessageSurvivesWebKitCancellationAndRetry() async throws {
        let browser = model()
        let tab = try XCTUnwrap(browser.selected)
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow })
        tab.web.frame = window.bounds
        window.addSubview(tab.web)
        defer { tab.web.removeFromSuperview() }
        let previousIDs = Set(browser.downloads.items.map(\.id))
        browser.downloads.start(URLRequest(url: URL(string: "http://127.0.0.1:8765/forbidden")!), web: tab.web, isPrivate: false)
        for _ in 0..<300 {
            if let item = browser.downloads.items.first, !previousIDs.contains(item.id), !item.active { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let item = try XCTUnwrap(browser.downloads.items.first { !previousIDs.contains($0.id) })
        defer { browser.downloads.remove(item) }
        // Allow the cancellation delegate callback after rejecting the destination.
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(item.status.contains("HTTP 403"), item.status)
        XCTAssertTrue(item.canRetry)
        XCTAssertNil(item.localURL)
        item.retry()
        XCTAssertTrue(item.active)
        for _ in 0..<300 {
            if !item.active { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertFalse(item.active)
        XCTAssertTrue(item.status.contains("HTTP 403"), item.status)
        XCTAssertTrue(item.canRetry)
    }

    func testWebNavigationHistoryCookiesAndDownloadToChosenFolder() async throws {
        let payload = Data("Jiza downloaded file fixture".utf8)
        let base = URL(string: "http://127.0.0.1:8765")!
        let browser = BrowserModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let tab = browser.selected!
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow })
        tab.web.frame = window.bounds
        window.addSubview(tab.web)
        defer { tab.web.removeFromSuperview() }
        tab.web.load(URLRequest(url: base.appendingPathComponent("page")))
        for _ in 0..<300 {
            if tab.web.title == "Jiza test page" && !browser.history.isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(tab.web.title, "Jiza test page", tab.pageError ?? "Page did not load")
        XCTAssertEqual(browser.history.first?.url.path, "/page")
        browser.bookmark()
        let restored = BrowserModel(defaults: browser.defaults)
        XCTAssertEqual(restored.bookmarks.first?.url.path, "/page")
        XCTAssertEqual(restored.history.first?.url.path, "/page")
        let cookies = await tab.web.configuration.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertTrue(cookies.contains { $0.name == "jiza_test" })
        let privateTab = browser.newTab(isPrivate: true)
        let privateCookies = await privateTab.web.configuration.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertFalse(privateCookies.contains { $0.name == "jiza_test" })
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { browser.downloads.useDefaultFolder(); try? FileManager.default.removeItem(at: folder) }
        browser.downloads.chooseFolder(folder)
        tab.web.startDownload(using: URLRequest(url: base.appendingPathComponent("file"))) { download in
            browser.downloads.accept(download, web: tab.web, isPrivate: false)
        }
        for _ in 0..<300 {
            if let item = browser.downloads.items.first, !item.active { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let item = try XCTUnwrap(browser.downloads.items.first)
        XCTAssertFalse(item.active, item.status)
        let local = try XCTUnwrap(item.localURL, item.status)
        defer { try? FileManager.default.removeItem(at: local); browser.downloads.remove(item) }
        XCTAssertEqual(try Data(contentsOf: local), payload)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(local.lastPathComponent)), payload)
        XCTAssertEqual(item.status, "Saved to chosen folder and Jiza")
        browser.clearHistory()
        XCTAssertTrue(BrowserModel(defaults: browser.defaults).history.isEmpty)
    }
}

extension BrowserModelTests {
    func testLinkBookmarkUsesTargetAndRefreshHandlesEmptyPage() throws {
        let browser = BrowserModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let tab = try XCTUnwrap(browser.selected)
        let target = URL(string: "https://example.com/saved")!
        browser.bookmark(target)
        XCTAssertEqual(browser.bookmarks.first?.url, target)
        browser.bookmark(URL(string: "javascript:alert(1)")!)
        XCTAssertEqual(browser.bookmarks.count, 1)
        let refresh = try XCTUnwrap(tab.web.scrollView.refreshControl)
        refresh.beginRefreshing()
        refresh.sendActions(for: .valueChanged)
        XCTAssertFalse(refresh.isRefreshing)
        XCTAssertTrue(tab.web.scrollView.alwaysBounceVertical)
    }

    func testMediaResponsesDownloadOnlyForTopLevelNavigation() {
        XCTAssertTrue(BrowserDownloadPolicy.shouldDownload(mime: "video/mp4", disposition: nil, mainFrame: true, enabled: true))
        XCTAssertTrue(BrowserDownloadPolicy.shouldDownload(mime: "audio/mpeg", disposition: nil, mainFrame: true, enabled: true))
        XCTAssertFalse(BrowserDownloadPolicy.shouldDownload(mime: "video/mp4", disposition: nil, mainFrame: false, enabled: true))
        XCTAssertFalse(BrowserDownloadPolicy.shouldDownload(mime: "video/mp4", disposition: nil, mainFrame: true, enabled: false))
        XCTAssertFalse(BrowserDownloadPolicy.shouldDownload(mime: "text/html", disposition: nil, mainFrame: true, enabled: true))
        XCTAssertTrue(BrowserDownloadPolicy.isFileLink(URL(string: "https://example.com/file.torrent?token=123")!))
    }
    func testClickedNewTabMediaRedirectAndTorrentBecomeFiles() async throws {
        let browser = BrowserModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        browser.downloads.useDefaultFolder()
        let tab = browser.selected!
        let base = URL(string: "http://127.0.0.1:8765")!
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow })
        tab.web.frame = window.bounds; window.addSubview(tab.web)
        defer { tab.web.removeFromSuperview() }
        for _ in 0..<1200 {
            if browser.protection.ready { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(browser.protection.ready, browser.protection.error ?? "Browser protection did not initialize")
        let linksURL = base.appendingPathComponent("links")
        tab.web.load(URLRequest(url: linksURL))
        // A cold WebKit process can spend over ten seconds initializing on CI.
        // Wait for this navigation to finish before clicking its document.
        for _ in 0..<600 { if tab.web.url == linksURL && !tab.web.isLoading && tab.web.title == "Download links" { break }; try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(tab.web.title, "Download links")
        XCTAssertFalse(tab.web.isLoading)
        guard tab.web.title == "Download links", !tab.web.isLoading else { return }
        for id in ["video", "audio", "redirect", "torrent"] {
            let count = browser.downloads.items.count
            // IDs are fixed test constants, never external page data.
            _ = try await tab.web.evaluateJavaScript("document.getElementById('\(id)').click(); true")
            for _ in 0..<300 {
                if browser.downloads.items.count > count, browser.downloads.items.first?.active == false { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertEqual(browser.downloads.items.count, count + 1, id)
            let item = try XCTUnwrap(browser.downloads.items.first)
            let file = try XCTUnwrap(item.localURL, "\(id): \(item.status)")
            XCTAssertGreaterThan(try Data(contentsOf: file).count, 0)
            try FileManager.default.removeItem(at: file); browser.downloads.remove(item)
            XCTAssertEqual(browser.tabs.count, 1, "Download must not leave an empty tab")
        }
    }
    func testAdBlockToggleActuallyBlocksAndRestoresResource() async throws {
        let browser = BrowserModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let tab = browser.selected!
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow })
        tab.web.frame = window.bounds
        window.addSubview(tab.web)
        defer { tab.web.removeFromSuperview() }
        for _ in 0..<1200 { if browser.protection.ready { break }; try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertNil(browser.protection.error)
        XCTAssertTrue(browser.protection.ready)
        for blocked in [false, true, false] {
            browser.protection.setAdBlock(blocked)
            let url = URL(string: "http://127.0.0.1:8765/ad-test?\(UUID().uuidString)")!
            tab.web.load(URLRequest(url: url))
            for _ in 0..<600 { if tab.web.url == url && !tab.web.isLoading && tab.web.title == "Ad test" { break }; try await Task.sleep(nanoseconds: 50_000_000) }
            XCTAssertEqual(tab.web.url, url)
            XCTAssertFalse(tab.web.isLoading)
            let loaded = try await tab.web.evaluateJavaScript("Boolean(window.jizaAdLoaded)") as? Bool
            XCTAssertEqual(loaded, !blocked)
        }
        browser.protection.setPopups(false)
        XCTAssertTrue(tab.web.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        browser.protection.setPopups(true)
        XCTAssertFalse(tab.web.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
    }
}
