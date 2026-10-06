import SwiftUI

@main
@MainActor
struct InteraMusicPlayerApp: App {
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
                .task { player.restoreLastFolder() }
                .fullScreenCover(isPresented: $video.isPresented, onDismiss: {
                    if !video.isPiPActive { video.close() }
                }) { VideoPlayerView(video: video) }
                .onOpenURL { url in
                    path = [VideoPlayerModel.isVideo(url) ? "Video" : "Player"]
                    if VideoPlayerModel.isVideo(url) {
                        Task { await video.open(url) }
                    } else {
                        video.close()
                        player.openIncomingFile(url)
                    }
                }
        }
    }
}
