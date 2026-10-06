import SwiftUI
import AVKit
import MediaPlayer
import MobileVLCKit
import UniformTypeIdentifiers

struct VideoPlayerView: View {
    @ObservedObject var video: VideoPlayerModel
    @State private var locked = false
    @State private var showSubtitles = false
    @State private var brightness = Double(UIScreen.main.brightness)
    @State private var originalBrightness: CGFloat?
    @State private var controlsVisible = true
    @State private var scrub = 0.0
    @State private var isScrubbing = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    if controlsVisible {
                        HStack {
                            Button { video.close() } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }.accessibilityLabel("Close video")
                            Text(video.title).font(.headline).lineLimit(1)
                            Spacer()
                            Button { locked = true } label: { Image(systemName: "lock").frame(width: 44, height: 44) }.accessibilityLabel("Lock video controls")
                        }.padding(.horizontal, 10)
                    }
                    ZStack {
                        if video.usingVLC {
                            VLCVideoSurface(video: video)
                            HStack(spacing: 0) {
                                seekZone(-10)
                                seekZone(10)
                            }
                            .gesture(DragGesture(minimumDistance: 25).onEnded { value in
                                if abs(value.translation.width) > abs(value.translation.height) {
                                    video.skip(Double(value.translation.width / max(geometry.size.width, 1)) * 120)
                                }
                            })
                        } else {
                            NativeVideoPlayer(video: video)
                        }
                        if video.isLoading {
                            ProgressView("Opening videoâ€¦").padding(20).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                        }
                        if let error = video.errorMessage {
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                                Text(error).multilineTextAlignment(.center)
                                Button("Return to videos") { video.close() }.buttonStyle(.bordered)
                            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if controlsVisible && video.errorMessage == nil {
                        controls
                    }
                }
                .allowsHitTesting(!locked)
                .accessibilityHidden(locked)
                if locked {
                    Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                    VStack {
                        HStack {
                            Spacer()
                            Button { locked = false } label: { Label("Unlock", systemImage: "lock.open").padding(14).background(.ultraThinMaterial, in: Capsule()) }
                                .accessibilityLabel("Unlock video controls")
                        }
                        Spacer()
                    }.padding(16)
                }
            }
        }
        .foregroundStyle(.white).tint(.white).background(.black).preferredColorScheme(.dark)
        .onAppear { originalBrightness = UIScreen.main.brightness; UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            if let originalBrightness { UIScreen.main.brightness = originalBrightness }
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background && video.usingVLC { video.pause() }
        }
        .fileImporter(isPresented: $showSubtitles, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { Task { await video.addSubtitles(url) } }
        }
    }

    private func seekZone(_ seconds: Double) -> some View {
        Color.clear.contentShape(Rectangle())
            .onTapGesture(count: 2) { video.skip(seconds) }
            .onTapGesture { controlsVisible.toggle() }
            .accessibilityHidden(true)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if video.usingVLC {
                Slider(value: Binding(get: { isScrubbing ? scrub : video.position }, set: { scrub = $0 }),
                       in: 0...max(1, video.duration), onEditingChanged: { editing in
                    if editing { scrub = video.position }
                    else { video.seek(scrub) }
                    isScrubbing = editing
                }).disabled(!video.seekable).accessibilityLabel("Video position")
                HStack {
                    Text(videoTime(video.position)); Spacer(); Text(videoTime(video.duration))
                }.font(.caption.monospacedDigit())
                HStack {
                    Button { video.next(-1) } label: { Image(systemName: "backward.end.fill") }.disabled(!video.canGoNext).accessibilityLabel("Previous video")
                    Spacer()
                    Button { video.skip(-10) } label: { Image(systemName: "gobackward.10") }.disabled(!video.seekable).accessibilityLabel("Back ten seconds")
                    Spacer()
                    Button { video.toggle() } label: { Image(systemName: video.isPlaying ? "pause.fill" : "play.fill").font(.title) }.accessibilityLabel(video.isPlaying ? "Pause video" : "Play video")
                    Spacer()
                    Button { video.skip(10) } label: { Image(systemName: "goforward.10") }.disabled(!video.seekable).accessibilityLabel("Forward ten seconds")
                    Spacer()
                    Button { video.next() } label: { Image(systemName: "forward.end.fill") }.disabled(!video.canGoNext).accessibilityLabel("Next video")
                }.buttonStyle(VideoControlStyle())
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    Menu {
                        ForEach([Float(0.25), 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3], id: \.self) { rate in
                            Button("\(rate.formatted())Ã—") { video.setSpeed(rate) }
                        }
                    } label: { Text("\(video.speed.formatted())Ã—").frame(minHeight: 44) }.accessibilityLabel("Playback speed")
                    Menu {
                        Picker("Display", selection: $video.fit) { ForEach(VideoFit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    } label: { Label(video.fit.rawValue, systemImage: "arrow.up.left.and.arrow.down.right").frame(minHeight: 44) }
                    Menu {
                        ForEach(video.audioChoices) { choice in Button(choice.name) { video.selectAudio(choice.id) } }
                        if video.audioChoices.isEmpty { Text("No alternate audio tracks") }
                    } label: { Image(systemName: "waveform").frame(width: 44, height: 44) }.accessibilityLabel("Audio tracks")
                    Menu {
                        Button("Subtitles off") { video.selectSubtitle(-1) }
                        ForEach(video.subtitleChoices.filter { $0.id >= 0 }) { choice in Button(choice.name) { video.selectSubtitle(choice.id) } }
                        Button("Load subtitle fileâ€¦") { showSubtitles = true }
                        if video.usingVLC {
                            Button("Delay +0.5s (\(video.subtitleDelay.formatted())s)") { video.subtitleDelay += 0.5 }
                            Button("Delay âˆ’0.5s") { video.subtitleDelay -= 0.5 }
                            Button("Reset subtitle timing") { video.subtitleDelay = 0 }
                        }
                    } label: { Image(systemName: "captions.bubble").frame(width: 44, height: 44) }.accessibilityLabel("Subtitles")
                    Menu {
                        Toggle("Repeat video", isOn: $video.repeatVideo)
                        Button("Previous video") { video.next(-1) }.disabled(!video.canGoNext)
                        Button("Next video") { video.next() }.disabled(!video.canGoNext)
                        Menu("Sleep timer") {
                            ForEach([15, 30, 60, 90], id: \.self) { minutes in Button("\(minutes) minutes") { video.setSleepTimer(minutes: minutes) } }
                            Button("Off") { video.setSleepTimer(minutes: nil) }
                        }
                        if let until = video.sleepUntil { Text("Stops at \(until.formatted(date: .omitted, time: .shortened))") }
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("Video options")
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "sun.max").accessibilityHidden(true)
                Slider(value: $brightness, in: 0...1).onChange(of: brightness) { UIScreen.main.brightness = CGFloat($0) }.accessibilityLabel("Screen brightness")
                SystemVolume().frame(width: 130, height: 30).accessibilityLabel("System volume")
            }
        }.padding(.horizontal, 18).padding(.bottom, 12)
    }
}

private struct VideoControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 44, minHeight: 44).opacity(configuration.isPressed ? 0.5 : 1)
    }
}
private struct SystemVolume: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView { MPVolumeView(frame: .zero) }
    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

private struct NativeVideoPlayer: UIViewControllerRepresentable {
    @ObservedObject var video: VideoPlayerModel
    func makeCoordinator() -> Coordinator { Coordinator(video: video) }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = video.player
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = video.player
        controller.videoGravity = video.fit == .fit ? .resizeAspect : video.fit == .fill ? .resizeAspectFill : .resize
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player = nil
    }
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let video: VideoPlayerModel
        init(video: VideoPlayerModel) { self.video = video }
        func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) { Task { @MainActor in video.isPiPActive = true } }
        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) { Task { @MainActor in video.isPiPActive = false } }
        func playerViewController(_ playerViewController: AVPlayerViewController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            Task { @MainActor in
                video.isPresented = true
                completionHandler(true)
            }
        }
    }
}

private struct VLCVideoSurface: UIViewRepresentable {
    @ObservedObject var video: VideoPlayerModel
    func makeUIView(context: Context) -> VLCOutputView {
        let view = VLCOutputView()
        view.player = video.vlc
        view.output = video.vlcDrawable
        view.addSubview(video.vlcDrawable)
        return view
    }
    func updateUIView(_ view: VLCOutputView, context: Context) { view.fit = video.fit; view.setNeedsLayout() }
    static func dismantleUIView(_ view: VLCOutputView, coordinator: ()) { view.player?.drawable = nil }
}
private final class VLCOutputView: UIView {
    weak var player: VLCMediaPlayer?
    var output: UIView?
    var fit: VideoFit = .fit
    override func layoutSubviews() {
        super.layoutSubviews()
        output?.frame = bounds
        guard let player, bounds.width > 0, bounds.height > 0 else { return }
        player.videoAspectRatio = nil
        player.videoCropGeometry = nil
        player.scaleFactor = 0
        let ratio = "\(Int(bounds.width)):\(Int(bounds.height))"
        ratio.withCString { pointer in
            if fit == .fill { player.videoCropGeometry = UnsafeMutablePointer(mutating: pointer) }
            if fit == .stretch { player.videoAspectRatio = UnsafeMutablePointer(mutating: pointer) }
        }
    }
}
