import Foundation

/// A coordinated, app-owned copy keeps Files-provider access valid for playback.
final class PreparedVideoFile {
    let url: URL
    private let directory: URL
    init(source: URL) throws {
        let access = VideoFileAccess(source)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("JizaVideo-" + UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
            do {
                let values = try readable.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
                try FileManager.default.copyItem(at: readable, to: url)
            } catch { copyError = error }
        }
        withExtendedLifetime(access) {}
        if let error = coordinationError ?? copyError as NSError? {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}
