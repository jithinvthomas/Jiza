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
        XCTAssertEqual(proposed.deletingLastPathComponent(), root)
        XCTAssertNotEqual(proposed, existing)
        XCTAssertEqual(try Data(contentsOf: existing), Data([1, 2, 3]))
    }
}
