import SwiftUI
import WebKit

/// A private, browser-based remote desktop viewer for an authenticated Guacamole gateway.
/// No credentials are embedded in the application or stored in UserDefaults.
struct JizaRemoteDesktopView: View {
    @AppStorage("jizaRemoteGatewayURL") private var gatewayURL = ""
    @AppStorage("jizaOracleDesktopProfile") private var oracleProfile = ""
    @AppStorage("jizaWindowsDesktopProfile") private var windowsProfile = ""

    @State private var settingsPresented = false
    @State private var gatewayDraft = ""
    @State private var oracleDraft = ""
    @State private var windowsDraft = ""
    @State private var activeTarget: RemoteTarget?
    @State private var viewerVersion = UUID()

    private enum RemoteTarget: String, Identifiable {
        case oracle, windows
        var id: String { rawValue }
        var title: String {
            switch self {
            case .oracle: return "Oracle Desktop"
            case .windows: return "Windows Desktop"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                JizaWorkspaceBackdrop()
                Group {
                if let activeTarget, let url = connectionURL(for: activeTarget) {
                    JizaRemoteWebView(url: url).id(viewerVersion)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            JizaWorkspaceIntro(
                                eyebrow: "Your devices",
                                title: "Remote Desktop",
                                detail: "Take your workspace anywhere. Open Ubuntu or Windows in one tap.",
                                symbol: "rectangle.on.rectangle"
                            )
                            JizaWorkspaceCard(
                                title: "Oracle Cloud",
                                detail: "Ubuntu · Graphical desktop",
                                symbol: "cloud.fill",
                                color: JizaStyle.blue
                            ) { connect(.oracle) }
                            JizaWorkspaceCard(
                                title: "Windows PC",
                                detail: "Windows Pro · Remote Desktop",
                                symbol: "desktopcomputer",
                                color: JizaStyle.violet
                            ) { connect(.windows) }
                            JizaWorkspaceNote(
                                text: "Tailscale private access required. Guacamole provides authenticated desktop viewing; RDP ports stay closed to the public."
                            )
                            Button("Connection Settings") { configure() }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(JizaStyle.mint)
                                .padding(.vertical, 8)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 30)
                    }
                }
                }
            }
            .navigationTitle(activeTarget?.title ?? "Remote Desktop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if activeTarget != nil {
                        Button {
                            activeTarget = nil
                        } label: {
                            Label("Connections", systemImage: "chevron.left")
                        }
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if activeTarget != nil {
                        Button { viewerVersion = UUID() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    Button { configure() } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $settingsPresented) {
                NavigationStack {
                    Form {
                        Section("Private Guacamole URL") {
                            TextField("https://your-gateway.tailnet.ts.net/guacamole/", text: $gatewayDraft)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Section("Guacamole Client Keys") {
                            TextField("Oracle encoded client key", text: $oracleDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("Windows encoded client key", text: $windowsDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Text("Copy the value after #/client/ from each Guacamole connection URL. It is a Base64 client key, not the numeric connection ID.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Section {
                            Button("Save Connections") {
                                gatewayURL = gatewayDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                oracleProfile = oracleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                windowsProfile = windowsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                activeTarget = nil
                                settingsPresented = false
                            }
                            .disabled(validGateway(gatewayDraft) == nil)
                        }
                        Section {
                            Text("Jiza does not store your RDP password. Guacamole handles login and credentials. Never expose ports 3389 or 4822 to the public internet.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Desktop Settings")
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

    private func configure() {
        gatewayDraft = gatewayURL
        oracleDraft = oracleProfile
        windowsDraft = windowsProfile
        settingsPresented = true
    }

    private func connect(_ target: RemoteTarget) {
        guard connectionURL(for: target) != nil else { configure(); return }
        activeTarget = target
        viewerVersion = UUID()
    }

    private func validGateway(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        return url
    }

    private func connectionURL(for target: RemoteTarget) -> URL? {
        guard let base = validGateway(gatewayURL) else { return nil }
        let clientKey = target == .oracle ? oracleProfile : windowsProfile
        guard !clientKey.isEmpty,
              clientKey.range(of: "^[A-Za-z0-9_+/=-]{1,256}$", options: .regularExpression) != nil else { return nil }
        // Guacamole supports connection-link fragments as #/client/<identifier>.
        // The client key is Base64-encoded and comes from an authenticated Guacamole instance.
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)
        parts?.fragment = "/client/\(clientKey)"
        return parts?.url
    }
}

private struct JizaRemoteWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.bounces = false
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
