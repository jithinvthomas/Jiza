import SwiftUI
import AVFoundation

@main
struct InteraMusicPlayerApp: App {
    @StateObject private var player = AudioPlayerModel()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .default,
            options: [.allowAirPlay, .allowBluetoothA2DP]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem { Label("Music", systemImage: "music.note") }
                PocketTerminalView()
                    .tabItem { Label("Terminal", systemImage: "terminal") }
            }
            .environmentObject(player)
            .onOpenURL { url in player.openIncomingFile(url) }
        }
    }
}
