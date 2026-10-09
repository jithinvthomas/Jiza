import SwiftUI

struct JizaHomeView: View {
    @Binding var path: [String]
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("jizaAppearance") private var appearance = "system"

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 16) {
                        Image("JizaSymbol").resizable().scaledToFit()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your space.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                            Text("Listen, watch, explore.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 14) {
                        entry("Music", detail: "Songs & playlists", route: "Player", asset: "JizaPlayer")
                        entry("Video", detail: "Films & streams")
                        entry("Browser", detail: "Web & downloads")
                        entry("Downloader", detail: "Files & links", asset: "JizaBrowser")
                        entry("Trading", detail: "Your workspace")
                    }
                    .modifier(JizaGlassGroup())
                }
                .padding(24)
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

    private func entry(_ title: String, detail: String, route: String? = nil, asset: String? = nil) -> some View {
        NavigationLink(value: route ?? title) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                Image(asset ?? ("Jiza" + title)).resizable().scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(JizaSurface(interactive: true))
        }
        .buttonStyle(JizaPressStyle())
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
