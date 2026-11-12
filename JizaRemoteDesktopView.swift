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
            Group {
                if let activeTarget, let url = connectionURL(for: activeTarget) {
                    JizaRemoteWebView(url: url).id(viewerVersion)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Remote Workspace").font(.largeTitle.bold())
                                Text("Access your Ubuntu and Windows Pro desktops securely from Jiza.")
                                    .foregroundStyle(.secondary)
                            }
                            connectionCard("Oracle Cloud", detail: "Ubuntu desktop (XRDP)", symbol: "cloud.fill") {
                                connect(.oracle)
                            }
                            connectionCard("Windows PC", detail: "Windows Pro Remote Desktop", symbol: "desktopcomputer") {
                                connect(.windows)
                            }
                            Label("Requires private HTTPS access to an authenticated Apache Guacamole gateway. Install Tailscale on your iPhone before connecting.", systemImage: "lock.shield")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                            Button("Configure Remote Desktops") { configure() }
                                .buttonStyle(.bordered)
                        }
                        .padding(20)
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
                        Section("Connection IDs") {
                            TextField("Oracle connection identifier", text: $oracleDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("Windows connection identifier", text: $windowsDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Text("Use the connection identifiers shown by your Guacamole administrator. The connections themselves must be set up in Guacamole first.")
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
    }

    private func connectionCard(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 28)).frame(width: 46)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
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
        let connectionID = target == .oracle ? oracleProfile : windowsProfile
        guard !connectionID.isEmpty,
              connectionID.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { return nil }
        // Guacamole supports connection-link fragments as #/client/<identifier>.
        // The ID must come from an authenticated Guacamole instance.
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)
        parts?.fragment = "/client/\(connectionID)"
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
