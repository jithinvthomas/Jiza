import XCTest
import Combine
import MediaPlayer
import AVFoundation
@testable import InteraMusic

@MainActor
final class AudioPlayerModelTests: XCTestCase {
    func testBuiltAppKeepsFullScreenLaunchConfiguration() {
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen"))
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool, true)
    }

    func testFolderIncludesNestedMusicAndSkipsHiddenFilesAndLinks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = folder.appendingPathComponent("Artist/Album")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for relative in ["root.mp3", "Artist/Album/song.M4A", "Artist/Album/notes.txt",
                         "Artist/Album/.hidden.mp3"] {
            try Data().write(to: folder.appendingPathComponent(relative))
        }
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("link.mp3"),
            withDestinationURL: folder.appendingPathComponent("root.mp3")
        )
        let (player, _) = isolatedPlayer()
        player.chooseFolder(folder)
        XCTAssertEqual(Set(player.tracks.map { $0.url.lastPathComponent }), ["root.mp3", "song.M4A"])
    }

    func testReadsEmbeddedArtworkFromAudioFile() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "with-artwork", withExtension: "mp3"))
        let image = await AudioPlayerModel.embeddedArtwork(at: url)
        XCTAssertNotNil(image)
    }

    func testFileWithoutArtworkUsesFallback() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "without-artwork", withExtension: "mp3"))
        let image = await AudioPlayerModel.embeddedArtwork(at: url)
        XCTAssertNil(image)
    }

    func testChangingSongClearsPreviousArtwork() async throws {
        let covered = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "with-artwork", withExtension: "mp3"))
        let plain = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "without-artwork", withExtension: "mp3"))
        let (player, _) = isolatedPlayer()
        let loaded = expectation(description: "Song artwork loads")
        let subscription = player.$currentArtwork.compactMap { $0 }.first().sink { _ in loaded.fulfill() }
        defer { subscription.cancel(); player.pause() }
        player.openIncomingFile(covered)
        await fulfillment(of: [loaded], timeout: 10)
        XCTAssertNotNil(player.currentArtwork)
        player.openIncomingFile(plain)
        XCTAssertNil(player.currentArtwork)
    }

    func testAppContainsHomeScreenIcon() {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        XCTAssertEqual(primary?["CFBundleIconName"] as? String, "AppIcon")
    }

    func testUnreadableFolderReportsFailure() {
        let (player, _) = isolatedPlayer()
        player.chooseFolder(URL(fileURLWithPath: "/missing-\(UUID().uuidString)"))
        XCTAssertNotNil(player.errorMessage)
        XCTAssertTrue(player.tracks.isEmpty)
    }

    func testEmptyFolderClearsPreviousPlaybackState() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (player, _) = isolatedPlayer()
        player.progress = 12
        player.duration = 50
        player.isPlaying = true
        player.chooseFolder(folder)
        XCTAssertEqual(player.folderName, folder.lastPathComponent)
        XCTAssertEqual(player.progress, 0)
        XCTAssertEqual(player.duration, 0)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.errorMessage)
    }

    func testInvalidAudioDoesNotClaimToBePlaying() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mp3")
        try Data("invalid audio".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let (player, _) = isolatedPlayer()
        player.openIncomingFile(file)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.errorMessage)
    }

    func testRemoteControlsPublishStateAndChangeTracks() throws {
        let (player, _) = isolatedPlayer()
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "without-artwork", withExtension: "mp3"))
        player.tracks = [Track(url: fixture), Track(url: fixture)]
        player.prepare(index: 0)
        player.play()
        defer { player.releaseRemoteControls() }
        XCTAssertTrue(player.hasRemoteControls)
        XCTAssertTrue(MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled)
        XCTAssertEqual(player.handleRemote(.pause), .success)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
        XCTAssertEqual(player.handleRemote(.seek(0.1)), .success)
        XCTAssertEqual(player.progress, 0.1, accuracy: 0.02)
        XCTAssertEqual(player.handleRemote(.play), .success)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.handleRemote(.next), .success)
        XCTAssertEqual(player.currentIndex, 1)
        XCTAssertEqual(player.handleRemote(.previous), .success)
        XCTAssertEqual(player.currentIndex, 0)
        XCTAssertNotNil(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork])
        player.releaseRemoteControls()
        XCTAssertFalse(player.hasRemoteControls)
        XCTAssertEqual(player.handleRemote(.play), .noSuchContent)
    }

    func testInvalidAudioDoesNotPublishNowPlaying() throws {
        let (player, _) = isolatedPlayer()
        player.openIncomingFile(URL(fileURLWithPath: "/missing.mp3"))
        XCTAssertFalse(player.hasRemoteControls)
        XCTAssertEqual(player.handleRemote(.next), .noSuchContent)
    }
    private func isolatedPlayer() -> (AudioPlayerModel, UserDefaults) {
        let defaults = UserDefaults(suiteName: "InteraTests-\(UUID().uuidString)")!
        return (AudioPlayerModel(defaults: defaults), defaults)
    }

    func testLastFolderRestoresWithoutStartingPlayback() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "without-artwork", withExtension: "mp3"))
        try FileManager.default.copyItem(at: fixture, to: folder.appendingPathComponent("song.mp3"))
        let (first, defaults) = isolatedPlayer()
        first.chooseFolder(folder)
        let restored = AudioPlayerModel(defaults: defaults)
        restored.restoreLastFolder()
        XCTAssertEqual(restored.folderName, folder.lastPathComponent)
        XCTAssertEqual(restored.tracks.map { $0.title }, ["song"])
        XCTAssertFalse(restored.isPlaying)
        XCTAssertNil(restored.errorMessage)
    }

    func testInvalidBookmarkReportsRecoverableError() {
        let (player, defaults) = isolatedPlayer()
        defaults.set(Data("invalid bookmark".utf8), forKey: "lastMusicFolderBookmark")
        player.restoreLastFolder()
        XCTAssertTrue(player.tracks.isEmpty)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.errorMessage)
    }

    func testInvalidSelectionKeepsPreviousSavedFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (player, defaults) = isolatedPlayer()
        player.chooseFolder(folder)
        let bookmark = try XCTUnwrap(defaults.data(forKey: "lastMusicFolderBookmark"))
        player.chooseFolder(folder.appendingPathComponent("missing"))
        XCTAssertEqual(defaults.data(forKey: "lastMusicFolderBookmark"), bookmark)
    }

    private func interruption(_ type: AVAudioSession.InterruptionType,
                              options: AVAudioSession.InterruptionOptions = []) {
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue,
                       AVAudioSessionInterruptionOptionKey: options.rawValue])
    }

    func testCallPausesAndResumesSameTrack() throws {
        let (player, _) = isolatedPlayer()
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "without-artwork", withExtension: "mp3"))
        player.openIncomingFile(fixture)
        defer { player.pause() }
        XCTAssertTrue(player.isPlaying)
        player.seek(0.1)
        let track = player.currentTrack
        interruption(.began)
        XCTAssertFalse(player.isPlaying)
        interruption(.ended, options: [.shouldResume])
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.currentTrack, track)
        XCTAssertEqual(player.progress, 0.1, accuracy: 0.02)
    }

    func testPlaybackUsesDeviceCompatibleAudioSession() throws {
        let (player, _) = isolatedPlayer()
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "without-artwork", withExtension: "mp3"))
        player.openIncomingFile(fixture)
        defer { player.pause() }

        XCTAssertNil(player.errorMessage)
        XCTAssertTrue(player.isPlaying)
        let session = AVAudioSession.sharedInstance()
        XCTAssertEqual(session.category, .playback)
        // These opt-in routes are for playAndRecord. Playback supports them by default.
        XCTAssertFalse(session.categoryOptions.contains(.allowAirPlay))
        XCTAssertFalse(session.categoryOptions.contains(.allowBluetoothA2DP))
    }

    func testManualPauseDuringCallCancelsAutomaticResume() throws {
        let (player, _) = isolatedPlayer()
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "without-artwork", withExtension: "mp3"))
        player.openIncomingFile(fixture)
        interruption(.began)
        player.pause()
        interruption(.ended, options: [.shouldResume])
        XCTAssertFalse(player.isPlaying)
    }

    func testCallDoesNotResumeWhenSystemWithholdsPermission() throws {
        let (player, _) = isolatedPlayer()
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "without-artwork", withExtension: "mp3"))
        player.openIncomingFile(fixture)
        interruption(.began)
        interruption(.ended)
        XCTAssertFalse(player.isPlaying)
    }

    func testCallDoesNotStartPreviouslyPausedMusic() throws {
        let (player, _) = isolatedPlayer()
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "without-artwork", withExtension: "mp3"))
        player.openIncomingFile(fixture)
        player.pause()
        interruption(.began)
        interruption(.ended, options: [.shouldResume])
        XCTAssertFalse(player.isPlaying)
    }
}
