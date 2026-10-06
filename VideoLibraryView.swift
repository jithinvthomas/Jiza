import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class VideoLibraryModel: ObservableObject {
    @Published private(set) var videos: [URL] = []
    @Published private(set) var folderName = "Your videos"
    @Published private(set) var isScanning = false
    @Published var error: String?
    private var access: VideoFileAccess?
    private var scan: Task<Void, Never>?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func restore() {
        guard videos.isEmpty, access == nil,
              let data = defaults.data(forKey: "jizaVideoFolder") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            chooseFolder(url)
        } catch { self.error = "Choose your video folder again to restore access." }
    }
    func chooseFolder(_ url: URL) {
        scan?.cancel()
        let scope = VideoFileAccess(url)
        isScanning = true
        error = nil
        scan = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[URL], Error> in
                do { return .success(try Self.scanFolder(url)) } catch { return .failure(error) }
            }.value
            guard !Task.isCancelled, let self else { return }
            self.isScanning = false
            switch result {
            case .success(let urls):
                self.access = scope
                self.videos = urls
                self.folderName = url.lastPathComponent
                do {
                    let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                    self.defaults.set(data, forKey: "jizaVideoFolder")
                } catch { self.error = "Folder opened, but could not be remembered. Select it again next time." }
            case .failure:
                self.error = "Unable to read this folder. Download cloud files in Files, then try again."
            }
        }
    }
    nonisolated static func scanFolder(_ url: URL) throws -> [URL] {
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw CocoaError(.fileReadUnknown) }
        var scanError: Error?
        guard let enumerator = FileManager.default.enumerator(at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in scanError = error; return false }) else { throw CocoaError(.fileReadUnknown) }
        var urls: [URL] = []
        for case let file as URL in enumerator {
            guard VideoPlayerModel.isVideo(file) else { continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true && values.isSymbolicLink != true { urls.append(file) }
        }
        if let scanError { throw scanError }
        return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
    deinit { scan?.cancel() }
}

struct VideoLibraryView: View {
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var video: VideoPlayerModel
    @StateObject private var library = VideoLibraryModel()
    @State private var search = ""
    @State private var reverse = false
    @State private var importer = false
    @State private var folderImport = false
    @State private var streamSheet = false
    @State private var showBrowser = false
    @State private var pendingWebsite: URL?
    @State private var stream = ""
    @State private var streamError: String?
    private var visible: [URL] {
        let matches = library.videos.filter { search.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(search) }
        return reverse ? Array(matches.reversed()) : matches
    }
    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image("JizaVideo").resizable().scaledToFit().frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your cinema, anywhere").font(.headline)
                        Text("Files, folders and direct streams").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                Button { folderImport = false; importer = true } label: { Label("Open video", systemImage: "play.rectangle") }
                Button { folderImport = true; importer = true } label: { Label("Choose video folder", systemImage: "folder") }
                Button { streamSheet = true } label: { Label("Open network stream", systemImage: "network") }
            }
            Section(library.folderName) {
                if library.isScanning { ProgressView("Finding videos…") }
                if visible.isEmpty && !library.isScanning {
                    Text(library.videos.isEmpty ? "Choose a folder to build your video library. Your last folder and playback positions are remembered." : "No matching videos.")
                        .foregroundStyle(.secondary)
                }
                ForEach(visible, id: \.absoluteString) { url in
                    Button { open(url) } label: {
                        HStack {
                            Image(systemName: "film").font(.title2).foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(url.deletingPathExtension().lastPathComponent).foregroundStyle(.primary)
                                let saved = video.savedPosition(for: url)
                                Text(saved > 0 ? "Continue at \(videoTime(saved))" : url.pathExtension.uppercased())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 6)
                    }
                    .contextMenu {
                        Button("Compatibility playback") { open(url, vlc: true) }
                        ShareLink(item: url)
                    }
                }
            }
            if let error = library.error { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Text("Supports local videos, network streams, subtitles, AirPlay and Picture in Picture where available.")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink("Open-source licenses") {
                    ScrollView {
                        Text((Bundle.main.url(forResource: "VLCKit-LGPL-2.1", withExtension: "txt").flatMap { try? String(contentsOf: $0) }) ?? "License: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html")
                            .font(.footnote).textSelection(.enabled).padding()
                    }.navigationTitle("Acknowledgements")
                }
                Link("Playback library source", destination: URL(string: "https://code.videolan.org/videolan/VLCKit")!)
            }
        }
        .navigationTitle("Video")
        .searchable(text: $search, prompt: "Search videos")
        .toolbar { Button { reverse.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("Reverse video order") }
        .task { library.restore() }
        .fileImporter(isPresented: $importer, allowedContentTypes: folderImport ? [.folder] : [.item]) { result in
            switch result {
            case .success(let url):
                if folderImport { library.chooseFolder(url) }
                else { video.setQueue([]); Task { await video.open(url) } }
            case .failure(let error): library.error = error.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $showBrowser) {
            NavigationStack {
                BrowserView().toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Back to videos") { showBrowser = false } } }
            }
        }
        .sheet(isPresented: $streamSheet, onDismiss: {
            if let url = pendingWebsite { browser.openWebsite(url); pendingWebsite = nil; showBrowser = true }
        }) {
            NavigationStack {
                Form {
                    Section("Video or website URL") {
                        TextField("https://… or rtsp://…", text: $stream)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("MP4, HLS and RTSP addresses play here. YouTube and other supported video websites open in Jiza Browser.").font(.footnote)
                        if let streamError { Text(streamError).foregroundStyle(.red) }
                        Button("Open video link") {
                            guard let url = VideoPlayerModel.streamURL(stream) else { streamError = "Enter a valid HTTPS or RTSP address without embedded credentials."; return }
                            if BrowserModel.isVideoWebsite(url) { pendingWebsite = url; streamSheet = false; return }
                            streamSheet = false
                            video.setQueue([])
                            Task { await video.open(url) }
                        }
                    }
                }
                .navigationTitle("Network stream")
                .toolbar { Button("Cancel") { streamSheet = false } }
            }
        }
    }
    private func open(_ url: URL, vlc: Bool = false) {
        video.setQueue(visible)
        Task { await video.open(url, forceVLC: vlc) }
    }
}

func videoTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let value = max(0, Int(seconds))
    if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60) }
    return String(format: "%d:%02d", value / 60, value % 60)
}
