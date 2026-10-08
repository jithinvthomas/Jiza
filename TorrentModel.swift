import Foundation
import Combine

@MainActor final class TorrentModel: ObservableObject {
    static let shared = TorrentModel()
    @Published var rows: [[String: Any]] = []
    @Published var error: String?
    private lazy var engine = JizaTorrent()
    private var sources: [String] = []
    private let queue = DispatchQueue(label: "jiza.torrents")
    static var folder: URL { BrowserDownloads.directory.appendingPathComponent("Torrents", isDirectory: true) }
    init() {
        sources = UserDefaults.standard.stringArray(forKey: "jizaTorrentSources") ?? []
        for source in sources { start(source, remember: false) }
    }
    func importFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            guard url.pathExtension.lowercased() == "torrent" else { throw CocoaError(.fileReadCorruptFile) }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0 && size <= 20 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            let metadata = Self.folder.appendingPathComponent("Metadata", isDirectory: true)
            try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
            let saved = metadata.appendingPathComponent(UUID().uuidString + ".torrent")
            try FileManager.default.copyItem(at: url, to: saved)
            start(saved.path)
        } catch { self.error = "Choose a downloaded .torrent file smaller than 20 MB. " + error.localizedDescription }
    }
    func start(_ source: String, remember: Bool = true) {
        do { try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        catch { self.error = error.localizedDescription; return }
        let engine = self.engine
        let folder = Self.folder.path
        queue.async {
            let message = engine.addSource(source, folder: folder)
            Task { @MainActor in
                if !message.isEmpty { self.error = message }
                else if remember && !self.sources.contains(source) {
                    self.sources.append(source)
                    UserDefaults.standard.set(self.sources, forKey: "jizaTorrentSources")
                }
            }
        }
    }
    func refresh() {
        let engine = self.engine
        queue.async {
            let rows = engine.snapshots() as? [[String: Any]] ?? []
            Task { @MainActor in self.rows = rows }
        }
    }
    func pause(_ paused: Bool, index: Int) {
        let engine = self.engine
        queue.async { engine.setPaused(paused, index: index) }
    }
}
