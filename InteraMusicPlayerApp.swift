import SwiftUI

@main
@MainActor
struct InteraMusicPlayerApp: App {
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
                .task { player.restoreLastFolder() }
                .onOpenURL { url in
                    path = ["Player"]
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
