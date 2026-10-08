import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let status = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        status.text = "Saving to Jiza…"
        status.numberOfLines = 0
        status.textAlignment = .center
        let done = UIButton(type: .system)
        done.setTitle("Done", for: .normal)
        done.addTarget(self, action: #selector(close), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [status, done])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerYAnchor.constraint(equalTo: view.centerYAnchor), stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)])
        Task { await save() }
    }
    @objc private func close() { extensionContext?.completeRequest(returningItems: nil) }
    @MainActor private func save() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var saved = 0
        for provider in providers.prefix(20) {
            do {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) && !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
                    guard let url = item as? URL else { continue }
                    try SharedInbox.saveText(url.absoluteString)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
                    guard let text = item as? String else { continue }
                    try SharedInbox.saveText(text)
                } else if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .data) == true && $0 != UTType.fileURL.identifier }) {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                            do {
                                guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                                try SharedInbox.save(url)
                                continuation.resume()
                            } catch { continuation.resume(throwing: error) }
                        }
                    }
                } else {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
                    guard let url = item as? URL else { continue }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try SharedInbox.save(url)
                }
                saved += 1
            } catch {
                status.text = "Saved \(saved) item(s). Could not save another item: \(error.localizedDescription)"
                return
            }
        }
        status.text = saved > 0 ? "Saved \(saved) item(s). Open Jiza → Downloader → Shared with Jiza." : "No supported files or links were provided."
    }
}
