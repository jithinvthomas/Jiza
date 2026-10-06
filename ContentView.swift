import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var player: AudioPlayerModel
    @EnvironmentObject private var video: VideoPlayerModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("jizaAppearance") private var appearance = "system"
    @State private var showImporter = false
    @State private var importingFolder = true
    @State private var importingVideo = false
    @State private var search = ""

    private let cobalt = Color(red: 49 / 255, green: 91 / 255, blue: 235 / 255)
    private let midnight = Color(red: 23 / 255, green: 32 / 255, blue: 61 / 255)
    private let ice = Color(red: 239 / 255, green: 243 / 255, blue: 1)
    private var dark: Bool { appearance == "dark" || (appearance == "system" && scheme == .dark) }
    private var ink: Color { dark ? .white : midnight }
    private var accent: Color { dark ? Color(red: 0.57, green: 0.70, blue: 1) : cobalt }
    private var preferredScheme: ColorScheme? {
        appearance == "system" ? nil : (appearance == "dark" ? .dark : .light)
    }
    private var filteredTracks: [(offset: Int, element: Track)] {
        Array(player.tracks.enumerated()).filter {
            search.isEmpty || $0.element.title.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 22) {
                    header
                    artwork(height: min(270, max(130, geometry.size.height * 0.29)))
                    controls
                    playlist
                }
                .modifier(JizaGlassGroup())
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(ink)
        .background { backdrop.ignoresSafeArea() }
        .preferredColorScheme(preferredScheme)
        .tint(accent)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importingFolder ? [.folder] : (importingVideo ? [.movie] : [.audio]),
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                search = ""
                if importingFolder { player.chooseFolder(url) }
                else if importingVideo { Task { await video.open(url) } }
                else { player.openIncomingFile(url) }
            case .failure(let error):
                player.errorMessage = "Unable to open your selection: \(error.localizedDescription)"
            }
        }

        .alert("Jiza", isPresented: Binding(
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { player.errorMessage = nil }
        } message: {
            Text(player.errorMessage ?? "")
        }
    }

    private var backdrop: some View {
        ZStack {
            dark ? midnight : ice
            if !reduceTransparency {
                RadialGradient(colors: [cobalt.opacity(dark ? 0.55 : 0.19), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 500)
                RadialGradient(colors: [Color.white.opacity(dark ? 0.07 : 0.8), .clear],
                               center: .leading, startRadius: 0, endRadius: 350)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("jiza")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .tracking(-1)
            Spacer()
            Menu {
                Button {
                    importingFolder = true
                    showImporter = true
                } label: {
                    Label("Choose folder", systemImage: "folder")
                }
                Button {
                    importingFolder = false
                    importingVideo = false
                    showImporter = true
                } label: {
                    Label("Open audio file", systemImage: "music.note")
                }

                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title3.weight(.medium))
                    .frame(width: 48, height: 48)
                    .modifier(JizaGlassSurface(radius: 24, interactive: true))
            }
            .accessibilityLabel("Music menu")
        }
    }

    private func artwork(height: CGFloat) -> some View {
        VStack(spacing: 18) {
            Group {
                if let image = player.currentArtwork {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Album artwork")
                } else {
                    Image("JizaSymbol")
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Jiza logo")
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: cobalt.opacity(dark ? 0.22 : 0.14), radius: 22, y: 12)
            VStack(spacing: 5) {
                Text(player.currentTrack?.title ?? "Your music, your space")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(player.folderName)
                    .font(.subheadline)
                    .foregroundStyle(ink.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Slider(value: Binding(get: { player.progress }, set: { player.seek($0) }),
                   in: 0...max(player.duration, 1))
                .disabled(player.duration == 0)
                .accessibilityLabel("Playback position")
            HStack {
                Text(format(player.progress))
                Spacer()
                Text(format(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(ink.opacity(0.7))
            HStack(spacing: 0) {
                Button { player.shuffle.toggle() } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(player.shuffle ? accent : ink.opacity(0.6))
                        .frame(minWidth: 44, minHeight: 48)
                }
                .accessibilityLabel(player.shuffle ? "Shuffle on" : "Shuffle off")
                .accessibilityValue(player.shuffle ? "On" : "Off")
                Spacer(minLength: 0)
                Button { player.previous() } label: {
                    Image(systemName: "backward.end.fill").frame(width: 44, height: 48)
                }.accessibilityLabel("Previous track")
                Spacer(minLength: 0)
                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .background {
                            Circle().fill(cobalt.gradient)
                                .overlay {
                                    Circle().strokeBorder(
                                        LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.15)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 1.5)
                                }
                                .shadow(color: cobalt.opacity(0.35), radius: 10, y: 5)
                        }
                }.accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Spacer(minLength: 0)
                Button { player.next() } label: {
                    Image(systemName: "forward.end.fill").frame(width: 44, height: 48)
                }.accessibilityLabel("Next track")
                Spacer(minLength: 0)
                Button { player.repeatTrack.toggle() } label: {
                    Image(systemName: "repeat")
                        .foregroundStyle(player.repeatTrack ? accent : ink.opacity(0.6))
                        .frame(minWidth: 44, minHeight: 48)
                }
                .accessibilityLabel(player.repeatTrack ? "Repeat on" : "Repeat off")
                .accessibilityValue(player.repeatTrack ? "On" : "Off")
            }
            .buttonStyle(.plain)
            .disabled(player.tracks.isEmpty)
        }
        .padding(18)
        .modifier(JizaGlassSurface(radius: 30))
    }

    private var playlist: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your library").font(.title2.bold())
                Spacer()
                Text("\(player.tracks.count) tracks")
                    .font(.caption)
                    .foregroundStyle(ink.opacity(0.65))
            }
            if player.tracks.isEmpty {
                Button {
                    importingFolder = true
                    showImporter = true
                } label: {
                    Label("Choose music folder", systemImage: "folder.badge.plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .modifier(JizaGlassSurface(radius: 20, interactive: true))
                Text("Add a folder to bring your songs together, including music in subfolders.")
                    .font(.subheadline)
                    .foregroundStyle(ink.opacity(0.7))
            } else {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(ink.opacity(0.6))
                    TextField("Search your music", text: $search)
                        .accessibilityLabel("Search your music")
                        .autocorrectionDisabled()
                }
                .padding(14)
                .modifier(JizaGlassSurface(radius: 18))
                if filteredTracks.isEmpty {
                    Text("No songs match your search.")
                        .font(.subheadline).foregroundStyle(ink.opacity(0.7))
                }
                LazyVStack(spacing: 0) {
                    ForEach(filteredTracks, id: \.element.id) { index, track in
                        Button {
                            player.prepare(index: index)
                            player.play()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: index == player.currentIndex ? "waveform" : "music.note")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(accent)
                                    .frame(width: 44, height: 44)
                                    .background(cobalt.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                                Text(track.title).font(.body.weight(.medium)).lineLimit(2)
                                Spacer(minLength: 8)
                                if index == player.currentIndex {
                                    Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                        .foregroundStyle(accent)
                                }
                            }
                            .frame(minHeight: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(ink.opacity(0.06))
                    }
                }
            }
        }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        return "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))"
    }
}


private struct JizaGlassGroup: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct JizaGlassSurface: ViewModifier {
    let radius: CGFloat
    var interactive = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background {
                shape.fill(scheme == .dark ? Color(red: 0.13, green: 0.18, blue: 0.31) : .white)
                    .overlay { shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 1) }
            }
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.interactive(interactive && !reduceMotion), in: shape)
            } else {
                fallback(content)
            }
            #else
            fallback(content)
            #endif
        }
    }

    private func fallback(_ content: Content) -> some View {
        content.background {
            shape.fill(.regularMaterial)
                .overlay { shape.fill(.white.opacity(scheme == .dark ? 0.03 : 0.18)) }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.12)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                }
                .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.07), radius: 16, y: 8)
        }
    }
}
