import SwiftUI
import WebKit

/// Saved private HTTPS terminal connections for remote Claude Code and Codex CLI.
struct PocketTerminalView: View {
    @AppStorage("pocketTerminalGatewayURL") private var oldGateway = ""
    @AppStorage("oracleTerminalGatewayURL") private var oracleGateway = ""
    @AppStorage("windowsTerminalGatewayURL") private var windowsGateway = ""

    @State private var draft = ""
    @State private var editingHost: TerminalHost = .oracle
    @State private var settingsPresented = false
    @State private var activeHost: TerminalHost?
    @State private var activeURL: URL?
    @State private var reload = UUID()

    private enum TerminalHost: String {
        case oracle, windows

        var title: String {
            switch self {
            case .oracle: return "Oracle Cloud"
            case .windows: return "Windows PC"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                JizaWorkspaceBackdrop()
                if let activeURL {
                    PocketTerminalWebView(url: activeURL).id(reload)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            JizaWorkspaceIntro(
                                eyebrow: "Developer tools",
                                title: "Pocket Terminal",
                                detail: "Your coding workspace, wherever you are. Connect to a remote shell and run Claude Code or Codex.",
                                symbol: "terminal.fill"
                            )

                            JizaWorkspaceCard(
                                title: "Oracle Cloud",
                                detail: "Ubuntu · SSH terminal",
                                symbol: "cloud.fill",
                                color: JizaStyle.mint
                            ) { connect(.oracle) }

                            JizaWorkspaceCard(
                                title: "Windows PC",
                                detail: "Windows · PowerShell or WSL",
                                symbol: "desktopcomputer",
                                color: JizaStyle.blue
                            ) { connect(.windows) }

                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                                        .foregroundStyle(JizaStyle.mint)
                                    Text("Coding assistants").font(.headline)
                                        .foregroundStyle(.white)
                                }
                                HStack(spacing: 10) {
                                    commandTile("Claude Code", command: "claude", symbol: "sparkles")
                                    commandTile("OpenAI Codex", command: "codex", symbol: "curlybraces")
                                }
                            }
                            .padding(16)
                            .background(JizaStyle.surface,
                                        in: RoundedRectangle(cornerRadius: 22))

                            JizaWorkspaceNote(
                                text: "One-tap connections require a previously configured, authenticated HTTPS SSH gateway. Commands execute on the remote server, not on your iPhone."
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle(activeHost?.title ?? "Terminal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if activeURL != nil {
                        Button {
                            activeURL = nil
                            activeHost = nil
                        } label: {
                            Label("Connections", systemImage: "chevron.left")
                        }
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if activeURL != nil {
                        Button { reload = UUID() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    Menu {
                        Button("Oracle Gateway") { configure(.oracle) }
                        Button("Windows Gateway") { configure(.windows) }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $settingsPresented) {
                NavigationStack {
                    Form {
                        Section("\(editingHost.title) Private HTTPS Gateway") {
                            TextField("https://your-private-terminal.example", text: $draft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }
                        Section {
                            Text("Enter an authenticated private HTTPS web terminal gateway, not an SSH IP address or port 22. It must already be configured to connect to the selected remote host.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Section {
                            Button("Save Connection") {
                                let saved = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                                switch editingHost {
                                case .oracle: oracleGateway = saved
                                case .windows: windowsGateway = saved
                                }
                                activeURL = nil
                                activeHost = nil
                                settingsPresented = false
                            }
                            .disabled(validURL(draft) == nil)
                        }
                    }
                    .navigationTitle("\(editingHost.title) Settings")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { settingsPresented = false }
                        }
                    }
                }
            }
        }
        .tint(JizaStyle.mint)
        .preferredColorScheme(.dark)
    }

    private func commandTile(_ name: String, command: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(JizaStyle.mint)
                .font(.system(size: 21))
            Text(name)
                .foregroundStyle(.white)
                .font(.subheadline.weight(.semibold))
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(JizaStyle.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(JizaStyle.elevated, in: RoundedRectangle(cornerRadius: 15))
        .accessibilityElement(children: .combine)
    }

    private func savedGateway(for host: TerminalHost) -> String {
        switch host {
        case .oracle: return oracleGateway.isEmpty ? oldGateway : oracleGateway
        case .windows: return windowsGateway
        }
    }

    private func configure(_ host: TerminalHost) {
        editingHost = host
        draft = savedGateway(for: host)
        settingsPresented = true
    }

    private func connect(_ host: TerminalHost) {
        guard let url = validURL(savedGateway(for: host)) else {
            configure(host)
            return
        }
        activeHost = host
        activeURL = url
        reload = UUID()
    }

    private func validURL(_ input: String) -> URL? {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil,
              url.fragment == nil else { return nil }
        return url
    }
}

private struct PocketTerminalWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
