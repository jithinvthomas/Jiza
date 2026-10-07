import SwiftUI

@main
@MainActor
struct InteraMusicPlayerApp: App {
    @StateObject private var security = AppSecurity()
    @State private var pendingFile: URL?
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var browser = BrowserModel()
    @State private var path: [String] = []
    @StateObject private var player: AudioPlayerModel
    @StateObject private var video: VideoPlayerModel

    init() {
        let audio = AudioPlayerModel()
        _player = StateObject(wrappedValue: audio)
        _video = StateObject(wrappedValue: VideoPlayerModel(audio: audio))
    }

    var body: some Scene {
        WindowGroup {
            JizaHomeView(path: $path)
                .environmentObject(player)
                .environmentObject(video)
                .environmentObject(browser)
                .environmentObject(security)
                .background(SecurityShieldWindow(security: security).frame(width: 0, height: 0))
                .onChange(of: scenePhase) { phase in
                    if phase == .background && security.appLockEnabled { video.close() }
                }
                .onChange(of: security.appUnlocked) { unlocked in
                    if unlocked, let url = pendingFile { pendingFile = nil; openFile(url) }
                }
                .task { player.restoreLastFolder() }
                .fullScreenCover(isPresented: $video.isPresented, onDismiss: {
                    if !video.isPiPActive { video.close() }
                }) { VideoPlayerView(video: video) }
                .onOpenURL { url in
                    if security.needsAppUnlock { pendingFile = url }
                    else { openFile(url) }
                }
        }
    }
    private func openFile(_ url: URL) {
        path = [VideoPlayerModel.isVideo(url) ? "Video" : "Player"]
        if VideoPlayerModel.isVideo(url) { Task { await video.open(url) } }
        else { video.close(); player.openIncomingFile(url) }
    }
}