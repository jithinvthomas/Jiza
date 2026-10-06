import SwiftUI
import SafariServices

struct JizaHomeView: View {
    @Binding var path: [String]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image("JizaSymbol")
                        .resizable().scaledToFit()
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .accessibilityHidden(true)
                    Text("Your space. Your choice.")
                        .font(.largeTitle.bold())
                    Text("What would you like to open?")
                        .foregroundStyle(.secondary)
                    entry("Music", detail: "Your songs and playlists", route: "Player", asset: "JizaPlayer")
                    entry("Video", detail: "Your films, series and streams")
                    entry("Browser", detail: "Explore the web")
                    entry("Trading", detail: "Your Jiza Trading workspace")
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("jiza")
            .navigationDestination(for: String.self) { destination in
                switch destination {
                case "Player": ContentView().navigationBarTitleDisplayMode(.inline)
                case "Video": VideoLibraryView()
                case "Browser": JizaWebEntryView(trading: false)
                default: JizaWebEntryView(trading: true)
                }
            }
        }
        .tint(Color(red: 49 / 255, green: 91 / 255, blue: 235 / 255))
    }

    private func entry(_ title: String, detail: String, route: String? = nil, asset: String? = nil) -> some View {
        NavigationLink(value: route ?? title) {
            HStack(spacing: 18) {
                Image(asset ?? ("Jiza" + title)).resizable().scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title2.bold())
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").accessibilityHidden(true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home" + (route ?? title))
    }
}

struct JizaWebEntryView: View {
    let trading: Bool
    @AppStorage("jizaTradingAddress") private var tradingAddress = ""
    @State private var address = ""
    @State private var presentedURL: WebDestination?
    @State private var error: String?

    var body: some View {
        Form {
            if trading {
                Section {
                    Label("Connect Jiza Trading", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                    Text("Enter your Jiza Trading server address to open your workspace here.")
                    Text("Still developing? Use an authenticated HTTPS development address reachable from your iPhone. Your computer's localhost address only works on that computer.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section(trading ? "Trading server" : "Website") {
                TextField("https://", text: $address)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("webAddress")
                    .onSubmit(open)
                Button(trading ? "Open Trading" : "Open website", action: open)
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("addressError")
                }
            }
            if trading && !tradingAddress.isEmpty {
                Button("Forget server", role: .destructive) {
                    tradingAddress = ""
                    address = ""
                    error = nil
                }
            }
        }
        .navigationTitle(trading ? "Trading" : "Browser")
        .onAppear {
            if trading && address.isEmpty { address = tradingAddress }
        }
        .fullScreenCover(item: $presentedURL) { destination in
            JizaSafariView(url: destination.url).ignoresSafeArea()
        }
    }

    private func open() {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: input), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              !host.contains(where: { $0.isWhitespace }) else {
            error = "Enter a valid HTTPS website address without embedded credentials."
            return
        }
        if trading && (host.lowercased() == "localhost" || host.hasSuffix(".localhost") || host == "[::1]" || host == "::1" || host.hasPrefix("127.")) {
            error = "Use your server's phone-accessible HTTPS address, not localhost."
            return
        }
        error = nil
        if trading { tradingAddress = url.absoluteString }
        presentedURL = WebDestination(url: url)
    }
}

private struct WebDestination: Identifiable {
    let id = UUID()
    let url: URL
}

private struct JizaSafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
