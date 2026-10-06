import AVFoundation
import Combine
import MediaPlayer
import UniformTypeIdentifiers

// The scope stays alive while either metadata loading or playback uses the file.
private final class VideoFileAccess {
    let url: URL
    private let scoped: Bool
    init(_ url: URL) {
        self.url = url
        scoped = url.startAccessingSecurityScopedResource()
    }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}

@MainActor
final class VideoPlayerModel: ObservableObject {
    let player = AVPlayer()
    @Published var isPresented = false
    @Published private(set) var isLoading = false
    @Published private(set) var title = "Video"
    @Published private(set) var errorMessage: String?
    private let audio: AudioPlayerModel
    private var fileAccess: VideoFileAccess?
    private var generation = UUID()
    private var statusObservation: NSKeyValueObservation?
    private var failureSubscription: AnyCancellable?

    init(audio: AudioPlayerModel) {
        self.audio = audio
        audio.beforePlayback = { [weak self] in self?.close() }
    }

    static func isVideo(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true
    }

    func open(_ url: URL) async {
        close()
        audio.releaseRemoteControls() // Hand system controls to the video player.
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        let request = generation
        title = url.deletingPathExtension().lastPathComponent
        isLoading = true
        isPresented = true
        let access = VideoFileAccess(url)
        let asset = AVURLAsset(url: access.url)
        do {
            let playable = try await asset.load(.isPlayable)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard request == generation, !Task.isCancelled else { return }
            guard playable, !videoTracks.isEmpty else {
                fail("This file does not contain a video that your iPhone can play.")
                return
            }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
            fileAccess = access
            let item = AVPlayerItem(asset: asset)
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                let failed = item.status == .failed
                Task { @MainActor [weak self] in
                    guard let self, request == self.generation, failed else { return }
                    self.fail("This video could not be played. Try another file or download it in Files first.")
                }
            }
            failureSubscription = NotificationCenter.default.publisher(
                for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item
            ).receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self, request == self.generation else { return }
                self.fail("Video playback stopped because the file could not be read. Reopen it from Files to try again.")
            }
            player.replaceCurrentItem(with: item)
            isLoading = false
            player.play()
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            fail("Unable to open this video. Download it in Files and try again, or choose another file. \(error.localizedDescription)")
        }
    }

    func close() {
        generation = UUID()
        stop()
        isPresented = false
        isLoading = false
        errorMessage = nil
    }

    private func fail(_ message: String) {
        stop()
        isLoading = false
        errorMessage = message
    }

    private func stop() {
        statusObservation = nil
        failureSubscription = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        fileAccess = nil
    }
}
