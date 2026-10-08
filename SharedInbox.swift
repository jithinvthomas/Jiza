import Foundation

enum SharedInbox {
    static func directory() throws -> URL {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.interaauditsolutions.music") else {
            throw NSError(domain: "Jiza", code: 1, userInfo: [NSLocalizedDescriptionKey: "Shared storage requires signing Jiza with its App Group enabled."])
        }
        let folder = root.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    static func save(_ source: URL) throws {
        let folder = try directory().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
        try Data().write(to: folder.appendingPathComponent(".ready"), options: .atomic)
    }
    static func saveText(_ text: String) throws {
        let folder = try directory().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(to: folder.appendingPathComponent("Shared link.txt"), atomically: true, encoding: .utf8)
        try Data().write(to: folder.appendingPathComponent(".ready"), options: .atomic)
    }
    static func files() throws -> [URL] {
        let folders = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)
        return try folders.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent(".ready").path) }
            .flatMap { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) }
    }
}
