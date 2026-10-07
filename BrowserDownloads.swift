import Foundation
import WebKit
import Combine

struct SavedDownload: Codable {
    let name: String
    let date: Date
}

@MainActor
final class BrowserDownloads: ObservableObject {
    @Published var items: [BrowserDownload] = []
    @Published var folderName = "On My iPhone / Jiza / Downloads"
    @Published var error: String?
    private(set) var folderBookmark: Data?
    nonisolated static var directory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true) }
    init() {
        folderBookmark = UserDefaults.standard.data(forKey: "jizaDownloadFolder")
        if let bookmark = folderBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) { folderName = url.lastPathComponent }
        }
        if let data = UserDefaults.standard.data(forKey: "jizaDownloads"), let saved = try? JSONDecoder().decode([SavedDownload].self, from: data) {
            for record in saved where record.name == URL(fileURLWithPath: record.name).lastPathComponent {
                let url = Self.directory.appendingPathComponent(record.name)
                if FileManager.default.fileExists(atPath: url.path) { items.append(BrowserDownload(saved: record, url: url, owner: self)) }
            }
        }
    }
    func chooseFolder(_ url: URL) {
        let scope = VideoFileAccess(url)
        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            folderBookmark = bookmark
            folderName = url.lastPathComponent
            UserDefaults.standard.set(bookmark, forKey: "jizaDownloadFolder")
        } catch { self.error = "Could not remember this folder. Please choose it again." }
        withExtendedLifetime(scope) {}
    }
    func useDefaultFolder() {
        folderBookmark = nil
        folderName = "On My iPhone / Jiza / Downloads"
        UserDefaults.standard.removeObject(forKey: "jizaDownloadFolder")
    }
    func accept(_ download: WKDownload, web: WKWebView, isPrivate: Bool) {
        let item = BrowserDownload(download: download, web: web, isPrivate: isPrivate, owner: self, folder: folderBookmark)
        items.insert(item, at: 0)
    }
    func start(_ request: URLRequest, web: WKWebView, isPrivate: Bool) {
        guard let url = request.url, BrowserModel.isWebURL(url) || url.scheme == "blob" else { error = "Enter a direct HTTP or HTTPS file URL."; return }
        web.startDownload(using: request) { [weak self, weak web] download in
            guard let self, let web else { return }
            self.accept(download, web: web, isPrivate: isPrivate)
        }
    }
    func downloadPage(_ web: WKWebView, isPrivate: Bool) {
        guard let url = web.url, BrowserModel.isWebURL(url) else { return }
        web.startDownload(using: URLRequest(url: url)) { [weak self, weak web] download in
            guard let self, let web else { return }
            self.accept(download, web: web, isPrivate: isPrivate)
        }
    }
    func persist() {
        let saved = items.compactMap { item -> SavedDownload? in
            guard !item.isPrivate, let url = item.localURL else { return nil }
            return SavedDownload(name: url.lastPathComponent, date: item.date)
        }
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "jizaDownloads") }
    }
    func remove(_ item: BrowserDownload) {
        item.cancel()
        // Forgetting a download does not delete the user's saved file.
        items.removeAll { $0.id == item.id }
        persist()
    }
    nonisolated static func safeFilename(_ name: String) -> String {
        let basename = name.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/").last ?? "download"
        let clean = String(basename.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(180))
        return clean.isEmpty || clean == "." || clean == ".." ? "download" : clean
    }
    nonisolated static func unusedURL(in directory: URL, name: String) -> URL {
        let initial = directory.appendingPathComponent(safeFilename(name))
        if !FileManager.default.fileExists(atPath: initial.path) { return initial }
        return directory.appendingPathComponent(UUID().uuidString + "-" + safeFilename(name))
    }
}

@MainActor
final class BrowserDownload: NSObject, ObservableObject, Identifiable, WKDownloadDelegate {
    let id = UUID()
    let isPrivate: Bool
    let date: Date
    @Published var name = "Preparing download"
    @Published var status = "Downloading"
    @Published var fraction = 0.0
    @Published var active = true
    @Published var localURL: URL?
    @Published var canResume = false
    @Published var canRetry = false
    @Published var transferred: Int64 = 0
    @Published var total: Int64 = 0
    @Published var bytesPerSecond = 0.0
    private var originalRequest: URLRequest?
    private var startedAt = Date()
    private var download: WKDownload?
    private var web: WKWebView?
    private weak var owner: BrowserDownloads?
    private var observation: NSKeyValueObservation?
    private var stagingURL: URL?
    private var resumeData: Data?
    private let folder: Data?
    init(download: WKDownload, web: WKWebView, isPrivate: Bool, owner: BrowserDownloads, folder: Data?) {
        self.web = web; self.isPrivate = isPrivate; self.owner = owner; self.folder = folder; date = Date()
        super.init()
        attach(download)
    }
    init(saved: SavedDownload, url: URL, owner: BrowserDownloads) {
        isPrivate = false; date = saved.date; folder = nil; self.owner = owner
        super.init()
        name = saved.name; localURL = url; status = "Saved"; active = false; fraction = 1
    }
    private func attach(_ value: WKDownload) {
        download = value
        value.delegate = self
        originalRequest = value.originalRequest ?? originalRequest
        startedAt = Date()
        canRetry = false
        active = true
        status = "Downloading"
        canResume = false
        observation = value.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            let completed = progress.completedUnitCount
            let total = progress.totalUnitCount
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.fraction = fraction; self.transferred = completed; self.total = total
                self.bytesPerSecond = Double(completed) / max(1, Date().timeIntervalSince(self.startedAt))
            }
        }
    }
    func pause() { cancel(); status = "Paused" }
    func retry() {
        guard !active, let web, let request = originalRequest else { return }
        web.startDownload(using: request) { [weak self] in self?.attach($0) }
    }
    func cancel() {
        guard active else { return }
        active = false; status = "Cancelled"; canRetry = originalRequest?.httpMethod == "GET"
        download?.cancel { [weak self] data in
            Task { @MainActor [weak self] in self?.resumeData = data; self?.canResume = data != nil }
        }
    }
    func resume() {
        guard let resumeData, let web else { return }
        web.resumeDownload(fromResumeData: resumeData) { [weak self] in self?.attach($0) }
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        if let response = response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
            active = false; status = "Server returned HTTP \(response.statusCode). Sign in or refresh the download link, then retry."
            canRetry = true; completionHandler(nil); return
        }
        name = BrowserDownloads.safeFilename(suggestedFilename)
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JizaDownload-" + id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = BrowserDownloads.unusedURL(in: directory, name: name)
            stagingURL = destination
            completionHandler(destination)
        } catch { active = false; status = "Could not create download file"; completionHandler(nil) }
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let stagingURL else { return }
        status = "Saving"
        let bookmark = folder
        let targetName = name
        Task {
            do {
                let saved = try await Task.detached(priority: .utility) {
                    let directory = BrowserDownloads.directory
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let local = BrowserDownloads.unusedURL(in: directory, name: targetName)
                    try FileManager.default.moveItem(at: stagingURL, to: local)
                    try? FileManager.default.removeItem(at: stagingURL.deletingLastPathComponent())
                    return local
                }.value
                localURL = saved; name = saved.lastPathComponent; fraction = 1
                owner?.persist()
                if let bookmark {
                    do {
                        try await Task.detached(priority: .utility) {
                            var stale = false
                            let folder = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
                            let access = VideoFileAccess(folder)
                            defer { withExtendedLifetime(access) {} }
                            var coordinationError: NSError?
                            var copyError: Error?
                            NSFileCoordinator().coordinate(writingItemAt: folder, options: .forMerging, error: &coordinationError) { destination in
                                do { try FileManager.default.copyItem(at: saved, to: BrowserDownloads.unusedURL(in: destination, name: saved.lastPathComponent)) }
                                catch { copyError = error }
                            }
                            if let coordinationError { throw coordinationError }
                            if let copyError { throw copyError }
                        }.value
                        status = "Saved to chosen folder and Jiza"
                    } catch { status = "Saved in Jiza. Folder unavailable; use Save a copy." }
                } else { status = "Saved" }
            } catch { status = "Save failed: " + error.localizedDescription }
            active = false
            self.download = nil; self.web = nil; observation = nil
        }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        active = false
        if status != "Cancelled" && status != "Paused" { status = "Failed: " + error.localizedDescription }
        self.resumeData = resumeData; canResume = resumeData != nil; canRetry = originalRequest?.httpMethod == "GET"
        observation = nil
    }
}
