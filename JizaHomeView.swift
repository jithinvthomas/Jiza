import SwiftUI

struct JizaHomeView: View {
    @Binding var path: [String]
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("jizaAppearance") private var appearance = "system"

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        Image("JizaSymbol").resizable().scaledToFit()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your space.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                            Text("Music, videos, browsing and more.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize >= .xxxLarge ? 1 : 2), spacing: 12) {
                        entry("Music", detail: "Songs & playlists", route: "Player", asset: "JizaPlayer")
                        entry("Video", detail: "Films & streams")
                        entry("Browser", detail: "Tabs & bookmarks")
                        entry("Downloader", detail: "Links & torrents", symbol: "arrow.down.circle.fill")
                        entry("Trading", detail: "Your workspace")
                    }
                    .modifier(JizaGlassGroup())
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background { JizaBackdrop().ignoresSafeArea() }
            .navigationTitle("Jiza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { JizaWordmark(height: 32) }
                ToolbarItem(placement: .navigationBarTrailing) { NavigationLink { SecuritySettingsView() } label: { Image(systemName: "lock.shield") }.accessibilityLabel("Privacy and locks") }
            }
            .navigationDestination(for: String.self) { destination in
                switch destination {
                case "Player": ContentView().navigationTitle("").navigationBarTitleDisplayMode(.inline)
                case "Video": VideoLibraryView().navigationTitle("").navigationBarTitleDisplayMode(.inline)
                case "Browser": BrowserView().navigationTitle("").navigationBarTitleDisplayMode(.inline)
                case "Downloader": BrowserDownloadsView(downloads: browser.downloads).navigationTitle("").navigationBarTitleDisplayMode(.inline)
                default: TradingDashboardView().navigationTitle("").navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .tint(JizaPalette.accent)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
    }

    private func entry(_ title: String, detail: String, route: String? = nil, asset: String? = nil, symbol: String? = nil) -> some View {
        NavigationLink(value: route ?? title) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Group {
                        if let symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(JizaPalette.accent)
                                .frame(width: 56, height: 56)
                                .background(JizaPalette.accent.opacity(0.12))
                        } else {
                            Image(asset ?? ("Jiza" + title)).resizable().scaledToFit()
                                .frame(width: 56, height: 56)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(JizaSurface(interactive: true))
        }
        .buttonStyle(JizaPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home" + (route ?? title))
    }
}

/// Use the approved lettering as an alpha mask, preserving its shape exactly.
struct JizaWordmark: View {
    @Environment(\.colorScheme) private var colorScheme
    var height: CGFloat = 44
    var body: some View {
        Image("JizaWordmark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: height * 2, height: height)
            .foregroundStyle(colorScheme == .dark ? Color.white : Color(red: 24 / 255, green: 33 / 255, blue: 57 / 255))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .accessibilityLabel("Jiza")
            .accessibilityAddTraits(.isHeader)
    }
}
