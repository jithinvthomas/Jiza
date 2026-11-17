import SwiftUI
import ios_system

/// ios_system owns process-wide shell state, so all native dispatch is serialized.
enum LocalShell {
    struct Result {
        let output: String
        let directory: URL
        let status: Int32
    }
    private static let queue = DispatchQueue(label: "com.jiza.local-shell", qos: .userInitiated)
    // The library requires a stable, NUL-terminated session name for the app lifetime.
    private static let session = strdup("jiza-local-shell")!
    private static var initialized = false

    static func run(_ command: String, directory: URL) async -> Result {
        await withCheckedContinuation { continuation in
            queue.async {
                let previousDirectory = FileManager.default.currentDirectoryPath
                defer { FileManager.default.changeCurrentDirectoryPath(previousDirectory) }
                if !initialized { initializeEnvironment(); initialized = true }
                ios_switchSession(session)
                _ = ios_setMiniRoot(NSHomeDirectory())
                ios_setDirectoryURL(directory)
                _ = ios_setenv("CLICOLOR", "0", 1)
                _ = ios_setenv("TERM", "dumb", 1)
                guard let input = fopen("/dev/null", "r") else {
                    continuation.resume(returning: Result(output: "Could not open terminal input.\n", directory: directory, status: 1)); return
                }
                defer { fclose(input) }
                guard let output = tmpfile() else {
                    continuation.resume(returning: Result(output: "Could not open terminal output.\n", directory: directory, status: 1)); return
                }
                defer { ios_setStreams(nil, nil, nil); fclose(output) }
                ios_setStreams(input, output, output)
                let pid = ios_fork()
                let status = ios_system(command)
                ios_waitpid(pid)
                ios_releaseThreadId(pid)
                fflush(output)
                rewind(output)
                var bytes = [UInt8](repeating: 0, count: 65_537)
                let count = fread(&bytes, 1, bytes.count, output)
                let text = String(decoding: bytes.prefix(min(count, 65_536)), as: UTF8.self)
                    + (count > 65_536 ? "\n[Output limited to 64 KB]\n" : "")
                let path = ios_getLogicalPWD(session) ?? directory.path
                continuation.resume(returning: Result(output: text, directory: URL(fileURLWithPath: path), status: status))
            }
        }
    }

    static func interrupt() { _ = ios_kill() }
}

@MainActor
final class LocalTerminalModel: ObservableObject {
    static let shared = LocalTerminalModel()
    @Published var transcript = "Jiza local terminal\nUnix commands run inside this app's iOS sandbox. Type help to get started.\n"
    @Published var isRunning = false
    @Published var directory: URL
    private(set) var history: [String] = []

    init() {
        directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Terminal", isDirectory: true)
    }

    func execute(_ command: String) async {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !isRunning else { return }
        guard command.utf8.count <= 16_384, !command.contains("\0") else {
            transcript += "Command is too long or contains a NUL character.\n"; return
        }
        history.append(command)
        if history.count > 100 { history.removeFirst() }
        transcript += "\n\(directory.lastPathComponent) $ \(command)\n"
        if command == "clear" { transcript = ""; return }
        if command == "help" {
            transcript += "Commands: ls, pwd, cd, mkdir, touch, cp, mv, rm, cat, echo, grep, sed, awk, wc, tar. Pipes and file redirection are supported.\nFiles live in Jiza/Terminal and remain between launches.\nThis is a local command shell, not a Linux installation. For interactive programs, Python/Node, Claude Code or Codex, use Oracle or Windows.\n"
            return
        }
        isRunning = true
        defer { isRunning = false }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { transcript += "Cannot open the terminal folder: \(error.localizedDescription)\n"; return }
        let result = await LocalShell.run(command, directory: directory)
        directory = result.directory
        transcript += result.output
        if result.status != 0 { transcript += "[Exit \(result.status)]\n" }
        if transcript.count > 100_000 { transcript = String(transcript.suffix(100_000)) }
    }
}

struct LocalTerminalView: View {
    @StateObject private var model = LocalTerminalModel.shared
    @State private var command = ""
    @State private var historyIndex = 0
    @FocusState private var commandFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.transcript)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .accessibilityIdentifier("localTerminalOutput")
                    Color.clear.frame(height: 1).id("end")
                }
                .onChange(of: model.transcript) { _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            HStack(spacing: 12) {
                Text("$").foregroundStyle(JizaStyle.mint)
                TextField("Command", text: $command)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($commandFocused)
                    .onSubmit(submit)
                    .disabled(model.isRunning)
                    .accessibilityIdentifier("localTerminalCommand")
                if model.isRunning {
                    Button("Stop") { LocalShell.interrupt() }
                } else {
                    Button(action: submit) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .accessibilityLabel("Run command")
                        .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .background(JizaStyle.surface)
        }
        .background(Color.black)
        .navigationTitle("Local Terminal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { command = "help"; submit() } label: { Image(systemName: "questionmark.circle") }
                    .accessibilityLabel("Terminal help")
                    .disabled(model.isRunning)
                Button {
                    guard !model.history.isEmpty else { return }
                    historyIndex = max(0, historyIndex - 1)
                    command = model.history[historyIndex]
                    commandFocused = true
                } label: { Image(systemName: "clock.arrow.circlepath") }
                .accessibilityLabel("Previous command")
                .disabled(model.isRunning || model.history.isEmpty)
            }
        }
        .tint(JizaStyle.mint)
        .preferredColorScheme(.dark)
    }

    private func submit() {
        guard !model.isRunning else { return }
        let submitted = command
        command = ""
        Task {
            await model.execute(submitted)
            historyIndex = model.history.count
        }
    }
}
