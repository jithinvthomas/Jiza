import SwiftUI
import WebKit

struct PocketTerminalView: View {
    @AppStorage("pocketTerminalGatewayURL") private var legacyGateway = ""
    @AppStorage("oracleTerminalGatewayURL") private var oracleGateway = ""
    @State private var draft = ""
    @State private var editingOracle = false
    @State private var activeURL: URL?
    @State private var reload = UUID()

    var body: some View {
        NavigationStack {
            Group {
                if let activeURL {
                    PocketTerminalWebView(url: activeURL).id(reload)
                } else {
                    VStack(spacing: 22) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 52)).foregroundStyle(.green)
                        Text("Pocket Terminal").font(.title.bold())
                        Text("Connect to your private Oracle Cloud terminal.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button {
                            connectOracle()
                        } label: {
                            Label("Connect to Oracle Cloud", systemImage: "cloud.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Configure Oracle Connection") { configureOracle() }
                            .font(.subheadline)
                    }.padding(24)
                }
            }
            .navigationTitle("Terminal")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if activeURL != nil {
                        Button { activeURL = nil } label: {
                            Label("Connections", systemImage: "chevron.left")
                        }
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if activeURL != nil {
                        Button { reload = UUID() } label: { Image(systemName: "arrow.clockwise") }
                    }
                    Button { configureOracle() } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $editingOracle) {
                NavigationStack {
                    Form {
                        Section("Oracle Cloud HTTPS Gateway") {
                            TextField("https://your-private-gateway.example", text: $draft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }
                        Section {
                            Text("Enter the HTTPS address of your authenticated private terminal gateway, not the server SSH IP or port 22. The gateway must be configured to connect to Oracle Cloud. Do not expose an unauthenticated command shell.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Section {
                            Button("Save Connection") {
                                oracleGateway = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                                activeURL = nil
                                editingOracle = false
                            }.disabled(validURL(draft) == nil)
                        }
                    }
                    .navigationTitle("Oracle Connection")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { editingOracle = false }
                        }
                    }
                }
            }
        }
        .tint(.green)
    }

    private func connectOracle() {
        // Backwards-compatible fallback for an already configured gateway.
        let saved = oracleGateway.isEmpty ? legacyGateway : oracleGateway
        guard let url = validURL(saved) else { configureOracle(); return }
        activeURL = url
        reload = UUID()
    }

    private func configureOracle() {
        draft = oracleGateway.isEmpty ? legacyGateway : oracleGateway
        editingOracle = true
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
        let config = WKWebViewConfiguration()
        // Keep cookies during an app session for authenticated gateway logins.
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .black
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
