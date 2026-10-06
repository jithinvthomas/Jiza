import AVFoundation
import Combine
import MediaPlayer
import MobileVLCKit
import UIKit
import UniformTypeIdentifiers

final class VideoFileAccess {
    let url: URL
    private let scoped: Bool
    init(_ url: URL) {
        self.url = url
        scoped = url.isFileURL && url.startAccessingSecurityScopedResource()
    }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}

struct VideoChoice: Identifiable, Equatable {
    let id: Int32
    let name: String
}

enum VideoFit: String, CaseIterable { case fit = "Fit", fill = "Fill", stretch = "Stretch" }

@MainActor
final class VideoPlayerModel: ObservableObject {
    let player = AVPlayer()
    let vlc = VLCMediaPlayer()
    let vlcDrawable = UIView()
    @Published var isPresented = false
    @Published var isPiPActive = false
    @Published private(set) var isLoading = false
    @Published private(set) var title = "Video"
    @Published private(set) var errorMessage: String?
    @Published var subtitleError: String?
    @Published private(set) var usingVLC = false
    @Published private(set) var isPlaying = false
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var seekable = false
    @Published private(set) var speed: Float = 1
    @Published var fit: VideoFit = .fit
    @Published var repeatVideo = false
    @Published private(set) var audioChoices: [VideoChoice] = []
    @Published private(set) var subtitleChoices: [VideoChoice] = []
    @Published private(set) var sleepUntil: Date?
    @Published private(set) var currentURL: URL?
    @Published private(set) var queue: [URL] = []
    @Published var subtitleDelay = 0.0 {
        didSet { vlc.currentVideoSubTitleDelay = Int(subtitleDelay * 1_000_000) }
    }
    private let audio: AudioPlayerModel
    private let defaults: UserDefaults
    private var fileAccess: VideoFileAccess?
    private var preparedFile: PreparedVideoFile?
    private var subtitleAccess: VideoFileAccess?
    private var generation = UUID()
    private var statusObservation: NSKeyValueObservation?
    private var failureSubscription: AnyCancellable?
    private var endSubscription: AnyCancellable?
    private var timer: Timer?
    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?
    private var pendingResume = 0.0
    private var lastSavedAt = Date.distantPast
    private var interrupted = false
    private var resumeAfterInterruption = false
    private var notifications: [AnyCancellable] = []

    init(audio: AudioPlayerModel, defaults: UserDefaults = .standard) {
        self.audio = audio
        self.defaults = defaults
        audio.beforePlayback = { [weak self] in self?.close() }
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] note in self?.interruption(note) }
            .store(in: &notifications)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] note in
                if (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
            }.store(in: &notifications)
    }

    nonisolated static func isVideo(_ url: URL) -> Bool {
        ["mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv", "flv", "ts", "mts", "m2ts", "mpg", "mpeg", "3gp", "ogv"].contains(url.pathExtension.lowercased()) ||
            UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true
    }

    static func streamURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "rtsp"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    func setQueue(_ urls: [URL]) { queue = urls }
    var canGoNext: Bool { queue.count > 1 && queue.contains(where: { $0 == currentURL }) }
    func next(_ offset: Int = 1) {
        guard let currentURL, let index = queue.firstIndex(of: currentURL), queue.count > 1 else { return }
        let url = queue[(index + offset + queue.count) % queue.count]
        Task { await open(url) }
    }

    func open(_ url: URL, forceVLC: Bool = false) async {
        close()
        audio.releaseRemoteControls()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        let request = generation
        currentURL = url
        title = url.lastPathComponent.isEmpty ? (url.host ?? "Stream") : url.deletingPathExtension().lastPathComponent
        isLoading = true
        isPresented = true
        let access = VideoFileAccess(url)
        fileAccess = access
        pendingResume = savedPosition(for: url)
        guard !url.isFileURL || Self.isVideo(url) else {
            fail("Choose a video file such as MP4, MOV or MKV.")
            return
        }
        do {
            let playbackURL: URL
            if url.isFileURL {
                let prepared = try await Task.detached(priority: .userInitiated) { try PreparedVideoFile(source: url) }.value
                guard request == generation, !Task.isCancelled else { return }
                preparedFile = prepared
                playbackURL = prepared.url
            } else { playbackURL = url }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
            if !forceVLC && url.scheme != "rtsp" {
                let asset = AVURLAsset(url: playbackURL)
                let playable = (try? await asset.load(.isPlayable)) ?? false
                let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
                guard request == generation, !Task.isCancelled else { return }
                if playable && (!tracks.isEmpty || !url.isFileURL) {
                    audioGroup = try? await asset.loadMediaSelectionGroup(for: .audible)
                    subtitleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)
                    guard request == generation, !Task.isCancelled else { return }
                    audioChoices = (audioGroup?.options ?? []).enumerated().map { VideoChoice(id: Int32($0.offset), name: $0.element.displayName) }
                    subtitleChoices = (subtitleGroup?.options ?? []).enumerated().map { VideoChoice(id: Int32($0.offset), name: $0.element.displayName) }
                    let item = AVPlayerItem(asset: asset)
                    statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                        let failed = item.status == .failed
                        Task { @MainActor [weak self] in
                            guard let self, request == self.generation, failed else { return }
                            self.fail("Video playback failed. Try Compatibility playback from the Video library.")
                        }
                    }
                    failureSubscription = NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
                        .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.fail("Playback stopped. Reopen the file or check your connection.") }
                    endSubscription = NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
                        .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.finished() }
                    player.replaceCurrentItem(with: item)
                    player.playImmediately(atRate: speed)
                    startTimer()
                    isLoading = false
                    return
                }
            }
            guard request == generation, !Task.isCancelled else { return }
            usingVLC = true
            vlc.drawable = vlcDrawable
            vlc.media = VLCMedia(url: playbackURL)
            vlc.play()
            for _ in 0..<300 {
                try await Task.sleep(nanoseconds: 100_000_000)
                guard request == generation, !Task.isCancelled else { return }
                if vlc.state == .error { throw CocoaError(.fileReadCorruptFile) }
                // VLC may report a buffering/stream-added event while decoding is active.
                if vlc.isPlaying && vlc.hasVideoOut {
                    guard vlc.numberOfVideoTracks > 0 else { throw CocoaError(.fileReadUnsupportedScheme) }
                    vlc.rate = speed
                    isLoading = false
                    startTimer()
                    return
                }
            }
            print("Jiza VLC startup timeout: state=\(vlc.state.rawValue), playing=\(vlc.isPlaying), video=\(vlc.hasVideoOut), tracks=\(vlc.numberOfVideoTracks)")
            fail("The video did not start. Check the file or stream address and try again.")
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            fail("Unable to read or play this video. Check your Files provider connection and available storage, then try again.")
        }
    }

    func play() {
        guard currentURL != nil, errorMessage == nil, !isLoading, !interrupted else { return }
        if usingVLC { vlc.play(); vlc.rate = speed } else { player.playImmediately(atRate: speed) }
        isPlaying = true
    }
    func pause() {
        resumeAfterInterruption = false
        if usingVLC { vlc.pause() } else { player.pause() }
        isPlaying = false
        savePosition()
    }
    func toggle() { isPlaying ? pause() : play() }
    func setSpeed(_ value: Float) {
        speed = min(max(value, 0.25), 3)
        player.defaultRate = speed
        if usingVLC { vlc.rate = speed } else if player.rate != 0 { player.rate = speed }
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite, duration > 0, seekable else { return }
        position = min(max(seconds, 0), max(0, duration - 0.1))
        if usingVLC { vlc.time = VLCTime(int: Int32(min(position * 1000, Double(Int32.max)))) }
        else { player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
    }
    func skip(_ seconds: Double) { seek(position + seconds) }
    func selectAudio(_ id: Int32) {
        if usingVLC { vlc.currentAudioTrackIndex = id }
        else if let group = audioGroup, group.options.indices.contains(Int(id)) { player.currentItem?.select(group.options[Int(id)], in: group) }
    }
    func selectSubtitle(_ id: Int32) {
        if usingVLC { vlc.currentVideoSubTitleIndex = id }
        else if let group = subtitleGroup {
            let option = group.options.indices.contains(Int(id)) ? group.options[Int(id)] : nil
            player.currentItem?.select(option, in: group)
        }
    }
    func addSubtitles(_ url: URL) async {
        subtitleError = nil
        guard let source = currentURL else { return }
        let access = VideoFileAccess(url)
        guard ["srt", "ass", "ssa", "vtt"].contains(url.pathExtension.lowercased()) else {
            subtitleError = "Choose an SRT, ASS, SSA or VTT subtitle file."
            return
        }
        if !usingVLC { await open(source, forceVLC: true) }
        guard usingVLC, !isLoading, errorMessage == nil, currentURL == source else { return }
        if vlc.addPlaybackSlave(url, type: .subtitle, enforce: true) == 0 {
            subtitleAccess = access
        } else { subtitleError = "This subtitle file could not be loaded. Try an SRT, ASS, SSA or VTT file." }
    }
    func setSleepTimer(minutes: Int?) { sleepUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) } }

    func savedPosition(for url: URL) -> Double {
        (defaults.dictionary(forKey: "jizaVideoPositions")?[url.absoluteString] as? Double) ?? 0
    }
    private func savePosition() {
        guard let url = currentURL, url.isFileURL, duration > 0, position.isFinite else { return }
        var positions = defaults.dictionary(forKey: "jizaVideoPositions") ?? [:]
        positions[url.absoluteString] = position >= duration - 1 ? 0 : position
        if positions.count > 200, let key = positions.keys.first(where: { $0 != url.absoluteString }) { positions.removeValue(forKey: key) }
        defaults.set(positions, forKey: "jizaVideoPositions")
    }
    private func finished() {
        position = duration
        savePosition()
        if repeatVideo { seek(0); play() }
        else if let currentURL, let index = queue.firstIndex(of: currentURL), index + 1 < queue.count { next() }
        else { pause() }
    }
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        tick()
    }
    private func tick() {
        guard currentURL != nil else { return }
        if usingVLC {
            if vlc.state == .error { fail("Video playback stopped. Reopen the video to try again."); return }
            if vlc.state == .ended { finished(); return }
            position = max(0, Double(vlc.time.intValue) / 1000)
            duration = max(0, Double(vlc.media?.length.intValue ?? 0) / 1000)
            seekable = vlc.isSeekable
            isPlaying = vlc.isPlaying
            audioChoices = choices(vlc.audioTrackIndexes, vlc.audioTrackNames)
            subtitleChoices = choices(vlc.videoSubTitlesIndexes, vlc.videoSubTitlesNames)
        } else {
            let time = player.currentTime().seconds
            let length = player.currentItem?.duration.seconds ?? 0
            position = time.isFinite ? max(0, time) : 0
            duration = length.isFinite ? max(0, length) : 0
            seekable = duration > 0 && player.currentItem?.status == .readyToPlay
            isPlaying = player.rate != 0
        }
        if pendingResume > 0 && seekable {
            let value = pendingResume
            pendingResume = 0
            if value < duration - 1 { seek(value) }
        }
        if let until = sleepUntil, Date() >= until { sleepUntil = nil; pause() }
        if Date().timeIntervalSince(lastSavedAt) > 5 { savePosition(); lastSavedAt = Date() }
    }
    private func choices(_ ids: [Any], _ names: [Any]) -> [VideoChoice] {
        zip(ids, names).compactMap { id, name in
            guard let number = id as? NSNumber else { return nil }
            return VideoChoice(id: number.int32Value, name: String(describing: name))
        }
    }
    private func interruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
        if raw == AVAudioSession.InterruptionType.began.rawValue {
            let playing = isPlaying
            pause()
            interrupted = true
            resumeAfterInterruption = playing
        } else {
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            let resume = resumeAfterInterruption && options.contains(.shouldResume)
            interrupted = false
            resumeAfterInterruption = false
            if resume { play() }
        }
    }
    func close() {
        generation = UUID()
        savePosition()
        stop()
        isPresented = false
        isPiPActive = false
        isLoading = false
        errorMessage = nil
        subtitleError = nil
        currentURL = nil
        sleepUntil = nil
        resumeAfterInterruption = false
    }
    private func fail(_ message: String) {
        stop()
        isLoading = false
        errorMessage = message
    }
    private func stop() {
        timer?.invalidate(); timer = nil
        statusObservation = nil
        failureSubscription = nil
        endSubscription = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        if usingVLC { vlc.stop() }
        vlc.media = nil
        fileAccess = nil
        preparedFile = nil
        subtitleAccess = nil
        audioGroup = nil
        subtitleGroup = nil
        audioChoices = []; subtitleChoices = []
        isPlaying = false
        usingVLC = false
        position = 0; duration = 0; seekable = false
    }
    deinit { timer?.invalidate() }
}
