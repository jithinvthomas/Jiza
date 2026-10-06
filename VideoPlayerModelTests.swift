import XCTest
import AVFoundation
import Combine
@testable import InteraMusic

@MainActor
final class VideoPlayerModelTests: XCTestCase {
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
