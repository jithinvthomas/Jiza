import XCTest
import WebKit
import Network
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

extension BrowserModelTests {
    func testWebNavigationHistoryCookiesAndDownloadToChosenFolder() async throws {
        let payload = Data("Jiza downloaded file fixture".utf8)
        let server = try BrowserFixtureServer(payload: payload)
        defer { server.listener.cancel() }
        for _ in 0..<100 {
            if server.listener.port != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let port = try XCTUnwrap(server.listener.port)
        let base = URL(string: "http://127.0.0.1:\(port.rawValue)")!
        let browser = BrowserModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let tab = browser.selected!
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

private final class BrowserFixtureServer {
    let listener: NWListener
    init(payload: Data) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            Self.receive(connection, request: Data(), payload: payload)
        }
        listener.start(queue: .global())
    }
    private static func receive(_ connection: NWConnection, request: Data, payload: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
            var buffer = request
            if let data { buffer.append(data) }
            guard let requestText = String(data: buffer, encoding: .utf8), requestText.contains("\r\n\r\n") else {
                if complete || error != nil { connection.cancel() }
                else { receive(connection, request: buffer, payload: payload) }
                return
            }
            let file = requestText.hasPrefix("GET /file ")
            let body = file ? payload : Data("<html><head><title>Jiza test page</title></head><body>Browser fixture</body></html>".utf8)
            let extra = file ? "Content-Disposition: attachment; filename=fixture.txt\r\n" : "Set-Cookie: jiza_test=yes; Path=/; SameSite=Lax\r\n"
            let mime = file ? "application/octet-stream" : "text/html"
            var response = Data("HTTP/1.1 200 OK\r\nContent-Type: \(mime)\r\nContent-Length: \(body.count)\r\n\(extra)Connection: close\r\n\r\n".utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
