import XCTest
import AVFoundation
import Combine
import UIKit
@testable import InteraMusic

@MainActor
final class VideoPlayerModelTests: XCTestCase {
    func testVLCOpensMatroskaAndSupportsSeekAndSpeed() async throws {
        let video = VideoPlayerModel(audio: music(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow })
        video.vlcDrawable.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        window.addSubview(video.vlcDrawable)
        defer { video.vlcDrawable.removeFromSuperview() }
        await video.open(try fixture("sample-video", "mkv"), forceVLC: true)
        defer { video.close() }
        XCTAssertNil(video.errorMessage)
        XCTAssertTrue(video.usingVLC)
        XCTAssertTrue(video.vlc.hasVideoOut)
        for _ in 0..<100 {
            if video.seekable && video.duration > 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(video.seekable)
        XCTAssertGreaterThan(video.duration, 5)
        video.pause()
        video.setSpeed(1.5)
        XCTAssertEqual(video.speed, 1.5)
        video.seek(2)
        XCTAssertEqual(video.position, 2, accuracy: 0.2)
        XCTAssertFalse(video.audioChoices.isEmpty)
    }

    func testResumePositionSurvivesReopen() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let video = VideoPlayerModel(audio: music(), defaults: defaults)
        let url = try fixture("sample-video", "mp4")
        await video.open(url)
        for _ in 0..<100 {
            if video.seekable { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        video.pause()
        video.seek(1)
        video.close()
        XCTAssertEqual(video.savedPosition(for: url), 1, accuracy: 0.2)
        await video.open(url)
        defer { video.close() }
        for _ in 0..<100 {
            if video.position >= 0.9 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertGreaterThanOrEqual(video.position, 0.9)
    }

    func testVideoFolderFiltersNestedFilesAndStreamValidation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for file in ["one.mp4", "nested/two.mkv", "music.mp3", ".hidden.mp4"] {
            try Data().write(to: root.appendingPathComponent(file))
        }
        let files = try VideoLibraryModel.scanFolder(root)
        XCTAssertEqual(Set(files.map { $0.lastPathComponent }), ["one.mp4", "two.mkv"])
        XCTAssertNotNil(VideoPlayerModel.streamURL("https://example.com/video.m3u8"))
        XCTAssertNotNil(VideoPlayerModel.streamURL("rtsp://example.com/live"))
        XCTAssertNil(VideoPlayerModel.streamURL("javascript:alert(1)"))
        XCTAssertNil(VideoPlayerModel.streamURL("https://user:password@example.com/video"))
    }
    private func music() -> AudioPlayerModel {
        AudioPlayerModel(defaults: UserDefaults(suiteName: "VideoTests-\(UUID().uuidString)")!)
    }

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext))
    }

    func testVideoPausesMusicAndClosingReleasesPlayer() async throws {
        let audio = music()
        let video = VideoPlayerModel(audio: audio)
        audio.openIncomingFile(try fixture("without-artwork", "mp3"))
        XCTAssertTrue(audio.isPlaying)
        await video.open(try fixture("sample-video", "mp4"))
        XCTAssertFalse(audio.isPlaying)
        XCTAssertTrue(video.isPresented)
        XCTAssertFalse(audio.hasRemoteControls)
        XCTAssertNotNil(video.player.currentItem)
        XCTAssertNil(video.errorMessage)
        let item = try XCTUnwrap(video.player.currentItem)
        let ready = expectation(description: "Video becomes ready for playback")
        let subscription = item.publisher(for: \.status)
            .filter { $0 != .unknown }.first().sink { _ in ready.fulfill() }
        await fulfillment(of: [ready], timeout: 10)
        subscription.cancel()
        XCTAssertEqual(item.status, .readyToPlay)
        video.player.pause()
        let sought = await video.player.seek(to: CMTime(seconds: 1, preferredTimescale: 600),
                                             toleranceBefore: .zero, toleranceAfter: .zero)
        XCTAssertTrue(sought)
        XCTAssertEqual(video.player.currentTime().seconds, 1, accuracy: 0.1)
        video.close()
        XCTAssertNil(video.player.currentItem)
        XCTAssertEqual(video.player.rate, 0)
        XCTAssertFalse(video.isPresented)
        XCTAssertFalse(audio.isPlaying)
    }

    func testStartingMusicClosesVideo() async throws {
        let audio = music()
        let video = VideoPlayerModel(audio: audio)
        await video.open(try fixture("sample-video", "mp4"))
        audio.openIncomingFile(try fixture("without-artwork", "mp3"))
        defer { audio.pause() }
        XCTAssertTrue(audio.isPlaying)
        XCTAssertFalse(video.isPresented)
        XCTAssertNil(video.player.currentItem)
    }

    func testInvalidVideoShowsRecoverableError() async throws {
        let video = VideoPlayerModel(audio: music())
        await video.open(URL(fileURLWithPath: "/missing-\(UUID().uuidString).mp4"))
        XCTAssertNotNil(video.errorMessage)
        XCTAssertFalse(video.isLoading)
        XCTAssertNil(video.player.currentItem)
        await video.open(try fixture("sample-video", "mp4"))
        XCTAssertNil(video.errorMessage)
        XCTAssertNotNil(video.player.currentItem)
        video.close()
    }

    func testAudioOnlyFileIsNotAcceptedAsVideo() async throws {
        let video = VideoPlayerModel(audio: music())
        await video.open(try fixture("without-artwork", "mp3"))
        XCTAssertNotNil(video.errorMessage)
        XCTAssertNil(video.player.currentItem)
        video.close()
    }

    func testClosingDuringLoadCannotStartPlaybackLater() async throws {
        let video = VideoPlayerModel(audio: music())
        let url = try fixture("sample-video", "mp4")
        let opening = Task { await video.open(url) }
        // Let open begin, then close while asynchronous metadata is loading.
        for _ in 0..<1000 {
            if video.isPresented { break }
            await Task.yield()
        }
        XCTAssertTrue(video.isPresented)

        video.close()
        await opening.value
        XCTAssertFalse(video.isPresented)
        XCTAssertNil(video.player.currentItem)
        XCTAssertEqual(video.player.rate, 0)
    }
}

extension VideoPlayerModelTests {
    func testCoordinatedImportCopiesVideoAndCleansUp() throws {
        let original = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sample-video", withExtension: "mp4"))
        var prepared: PreparedVideoFile? = try PreparedVideoFile(source: original)
        let copy = try XCTUnwrap(prepared?.url)
        XCTAssertNotEqual(copy, original)
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: original))
        prepared = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }
}
