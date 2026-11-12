import SwiftUI
import WebKit

/// Terminal runs through a user-hosted HTTPS SSH gateway; no SSH credentials are stored in the app.
struct PocketTerminalView: View {
    @AppStorage("pocketTerminalGatewayURL") private var gateway = ""
    @State private var draft = ""
    @State private var settings = false
    @State private var reload = UUID()

    private var endpoint: URL? {
        guard let url = URL(string: gateway), url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil,
              url.fragment == nil else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            Group {
                if let endpoint {
                    PocketTerminalWebView(url: endpoint).id(reload)
                } else {
                    VStack(spacing: 18) {
                        Image(systemName: "terminal.fill").font(.system(size: 56)).foregroundStyle(.green)
                        Text("Pocket Terminal").font(.title.bold())
                        Text("Connect to Windows PowerShell or Oracle Cloud through your private SSH gateway.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Set Up Gateway") { configure() }.buttonStyle(.borderedProminent)
                    }.padding()
                }
            }
            .navigationTitle("Terminal")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { reload = UUID() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(endpoint == nil)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { configure() } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $settings) {
                NavigationStack {
                    Form {
                        Section("Private HTTPS Gateway") {
                            TextField("https://terminal.example.com", text: $draft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }
                        Section {
                            Text("Use a private, authenticated HTTPS gateway (for example via Tailscale Serve). Never expose an unauthenticated SSH gateway to the public internet.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Section {
                            Button("Save & Connect") {
                                gateway = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                                reload = UUID()
                                settings = false
                            }.disabled(!valid(draft))
                        }
                    }
                    .navigationTitle("Terminal Settings")
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { settings = false }
                    }}
                }
            }
        }
        .tint(.green)
    }

    private func configure() { draft = gateway; settings = true }
    private func valid(_ input: String) -> Bool {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme?.lowercased() == "https" && url.host != nil &&
               url.user == nil && url.password == nil && url.fragment == nil
    }
}

private struct PocketTerminalWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
