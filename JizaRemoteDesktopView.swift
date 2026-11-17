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
    @State private var sessionDataStore = WKWebsiteDataStore.nonPersistent()

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
        Group {
            ZStack {
                JizaWorkspaceBackdrop()
                Group {
                if let activeTarget, let url = connectionURL(for: activeTarget) {
                    RemoteWorkspaceSession(url: url, dataStore: sessionDataStore, showsInputControls: true).id(viewerVersion)
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
                            .accessibilityIdentifier("desktopOracle")
                            JizaWorkspaceCard(
                                title: "Windows PC",
                                detail: "Windows · Remote desktop",
                                symbol: "desktopcomputer",
                                color: JizaStyle.violet
                            ) { connect(.windows) }
                            .accessibilityIdentifier("desktopWindows")
                            JizaWorkspaceNote(
                                text: "Connect through your private network to an authenticated Guacamole gateway. Keep RDP ports private; Jiza does not configure the server."
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
            .navigationBarBackButtonHidden(activeTarget != nil)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if activeTarget != nil {
                        Button {
                            activeTarget = nil
                            sessionDataStore = .nonPersistent()
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
                        .accessibilityLabel("Refresh desktop")
                    }
                    Button { configure() } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Desktop settings")
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
                                .accessibilityIdentifier("desktopGateway")
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
                                sessionDataStore = .nonPersistent()
                                settingsPresented = false
                            }
                            .disabled(!canSaveConnections)
                        }
                        Section {
                            Text("Jiza does not store your RDP password. Guacamole handles login and credentials. Never expose ports 3389 or 4822 to the public internet.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text("Save the gateway address without a query, token or password. Remote logins are isolated from Browser and cleared when you leave the connection.")
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
        .onDisappear {
            activeTarget = nil
            sessionDataStore = .nonPersistent()
        }
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
        sessionDataStore = .nonPersistent()
        viewerVersion = UUID()
    }

    private func validGateway(_ text: String) -> URL? {
        RemoteWorkspacePolicy.gateway(text)
    }

    private var canSaveConnections: Bool {
        let oracle = oracleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let windows = windowsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validGateway(gatewayDraft) != nil, !oracle.isEmpty || !windows.isEmpty else { return false }
        return (oracle.isEmpty || RemoteWorkspacePolicy.desktopURL(gateway: gatewayDraft, clientKey: oracle) != nil)
            && (windows.isEmpty || RemoteWorkspacePolicy.desktopURL(gateway: gatewayDraft, clientKey: windows) != nil)
    }

    private func connectionURL(for target: RemoteTarget) -> URL? {
        let clientKey = target == .oracle ? oracleProfile : windowsProfile
        return RemoteWorkspacePolicy.desktopURL(gateway: gatewayURL, clientKey: clientKey)
    }
}
