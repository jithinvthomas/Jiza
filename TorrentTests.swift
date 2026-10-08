import XCTest
@testable import InteraMusicPlayer

final class TorrentTests: XCTestCase {
    func testInvalidMagnetDoesNotCreateDownload() {
        let engine = JizaTorrent()
        let result = engine.addSource("magnet:?xt=invalid", folder: NSTemporaryDirectory())
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(engine.snapshots().isEmpty)
    }
    func testInvalidTorrentDoesNotCreateDownload() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".torrent")
        try Data("not torrent metadata".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let engine = JizaTorrent()
        XCTAssertFalse(engine.addSource(file.path, folder: NSTemporaryDirectory()).isEmpty)
        XCTAssertTrue(engine.snapshots().isEmpty)
    }
}
