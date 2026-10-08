import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct BrowserView: View {
    @EnvironmentObject private var security: AppSecurity
    @EnvironmentObject private var browser: BrowserModel
    @State private var media: [BrowserMediaLink] = []
    @State private var address = ""
    @State private var panel: BrowserPanel?
    @State private var find = ""
    @State private var showFind = false
    @State private var findResult = ""
    @FocusState private var addressFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            addressBar
            if browser.selected?.web.url?.scheme == "http" { Text("Not secure - HTTP").font(.caption).foregroundStyle(.orange) }
            if let tab = browser.selected { content(tab) }
            navigationControls
        }
        .navigationTitle("Browser").navigationBarTitleDisplayMode(.inline)
        .background(JizaPalette.background)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) { JizaWordmark(height: 18); Text("Browser").font(.headline) }
            }
        }
        .onChange(of: browser.selectedID) { _ in syncAddress() }
        .onChange(of: browser.selected?.web.url) { _ in if !addressFocused { syncAddress() } }
        .onAppear { syncAddress(); security.browserVisible = true }
        .onDisappear { security.leaveBrowser() }
        .onReceive(browser.downloads.$items.dropFirst()) { items in if items.first?.active == true { panel = .downloads } }
        .sheet(item: $panel) { selectedPanel in
            NavigationStack {
                panelContent(selectedPanel)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { panel = nil } } }
            }
        }
        .alert("Browser", isPresented: Binding(get: { browser.error != nil }, set: { if !$0 { browser.error = nil } })) {
            Button("OK") { browser.error = nil }
        } message: { Text(browser.error ?? "") }
    }
    private var addressIcon: String {
        if browser.selected?.isPrivate == true { return "eye.slash" }
        return browser.selected?.web.url?.scheme == "https" ? "lock" : "globe"
    }
    private var addressBar: some View {
        HStack(spacing: 8) {
            Image(systemName: addressIcon).foregroundStyle(.secondary)
            TextField("Search or enter website", text: $address)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.webSearch)
                .submitLabel(.go).focused($addressFocused).onSubmit(go)
                .accessibilityIdentifier("webAddress")
            Button(action: go) { Image(systemName: "arrow.right.circle.fill").frame(width: 44, height: 44) }.accessibilityLabel("Open website")
            if !address.isEmpty {
                Button {
                    address = ""
                    addressFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Clear address").accessibilityIdentifier("clearWebAddress")
            }
        }.padding(.horizontal, 12).padding(.vertical, 2).modifier(JizaSurface(radius: 18)).padding(.horizontal).padding(.vertical, 8)
    }
    @ViewBuilder private func content(_ tab: BrowserTab) -> some View {
        if tab.isPrivate {
            Text("Private tab - history and cookies aren't kept after closing private tabs")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
        if showFind {
            HStack {
                TextField("Find on page", text: $find).onSubmit { searchPage(tab) }
                Button("Find") { searchPage(tab) }
                Button("Done") { showFind = false }
            }.padding(.horizontal)
            if !findResult.isEmpty { Text(findResult).font(.caption) }
        }
        BrowserPageView(tab: tab).id(tab.id)
    }
    private var navigationControls: some View {
        HStack {
            Button { browser.selected?.web.goBack() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .disabled(browser.selected?.web.canGoBack != true).accessibilityLabel("Back")
            Spacer()
            Button { browser.selected?.web.goForward() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(browser.selected?.web.canGoForward != true).accessibilityLabel("Forward")
            Spacer()
            Button {
                guard let web = browser.selected?.web else { return }
                if web.isLoading { web.stopLoading() } else { web.reload() }
            } label: { Image(systemName: browser.selected?.web.isLoading == true ? "xmark" : "arrow.clockwise").frame(width: 44, height: 44) }
                .accessibilityLabel("Reload or stop")
            Spacer()
            Button { panel = .tabs } label: {
                ZStack { Image(systemName: "square"); Text("\(browser.tabs.count)").font(.system(size: 10, weight: .semibold, design: .rounded)) }.frame(width: 44, height: 44)
            }.accessibilityLabel("Tabs").accessibilityValue("\(browser.tabs.count) open tabs")
            Spacer()
            Button { panel = .downloads } label: { Image(systemName: "arrow.down.circle").frame(width: 44, height: 44) }.accessibilityLabel("Downloads")
            Spacer()
            browserMenu
        }.font(.title3).buttonStyle(.borderless).padding(.horizontal, 8).frame(minHeight: 56)
            .modifier(JizaSurface(radius: 28, interactive: true)).padding(.horizontal, 12).padding(.vertical, 8)
    }
    private var browserMenu: some View {
        Menu {
            Button("New tab") { browser.newTab() }
            Button("New private tab") { browser.newTab(isPrivate: true) }
            Button("Bookmarks") { panel = .bookmarks }
            Button("Add bookmark") { browser.bookmark() }.disabled(browser.selected?.web.url == nil)
            Button("History") { panel = .history }
            Button("Ad blocker & pop-ups") { panel = .protection }
            Button("Privacy & locks") { panel = .locks }
            Button("Website data & cookies") { panel = .data }
            if let tab = browser.selected { pageMenu(tab) }
        } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Browser menu")
    }
    @ViewBuilder private func pageMenu(_ tab: BrowserTab) -> some View {
        Toggle("Desktop site", isOn: Binding(get: { tab.desktop }, set: { tab.setDesktop($0) }))
        Toggle("Automatically download file links", isOn: Binding(get: { browser.automaticallyDownloadFiles }, set: { browser.automaticallyDownloadFiles = $0 }))
        Button("Download media on this page") { Task { media = await tab.findMedia(); panel = .media } }
        Button("Find on page") { showFind = true }
        Menu("Page size") {
            ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { zoom in
                Button("\(Int(zoom * 100))%") { tab.web.pageZoom = zoom }
            }
        }
        if let url = tab.web.url {
            ShareLink(item: url)
            Button("Download this page or file") { browser.downloads.downloadPage(tab.web, isPrivate: tab.isPrivate); panel = .downloads }
        }
    }
    @ViewBuilder private func panelContent(_ value: BrowserPanel) -> some View {
        switch value {
        case .tabs: tabsPanel
        case .bookmarks: pagesPanel(history: false)
        case .history: pagesPanel(history: true)
        case .downloads: BrowserDownloadsView(downloads: browser.downloads)
        case .data: BrowserDataView()
        case .protection: BrowserProtectionView(protection: browser.protection)
        case .locks: SecuritySettingsView()
        case .media:
            List {
                if media.isEmpty { Text("No direct media files found. Encrypted video, segmented streams and media inside other frames may not expose a downloadable file.").foregroundStyle(.secondary) }
                ForEach(media) { item in
                    Button { browser.selected?.downloadLink(item.url); panel = .downloads } label: {
                        VStack(alignment: .leading) { Text(item.label); Text(item.url.lastPathComponent).font(.caption).lineLimit(2) }
                    }
                }
            }.navigationTitle("Page media")
        }
    }
    private func go() { addressFocused = false; browser.navigate(address) }
    private func syncAddress() { address = browser.selected?.web.url?.absoluteString ?? ""; findResult = "" }
    private func searchPage(_ tab: BrowserTab) {
        guard !find.isEmpty else { return }
        let config = WKFindConfiguration(); config.wraps = true
        tab.web.find(find, configuration: config) { result in findResult = result.matchFound ? "Match found" : "No matches" }
    }
    private var tabsPanel: some View {
        List {
            Section {
                Button("New tab") { browser.newTab(); panel = nil }
                Button("New private tab") { browser.newTab(isPrivate: true); panel = nil }
            }
            ForEach(browser.tabs) { tab in tabRow(tab) }
        }.navigationTitle("Tabs")
    }
    private func tabRow(_ tab: BrowserTab) -> some View {
        HStack {
            Button { browser.selectedID = tab.id; panel = nil } label: {
                Label {
                    VStack(alignment: .leading) {
                        Text(tab.web.title ?? "New tab").lineLimit(1)
                        Text(tab.web.url?.host ?? (tab.isPrivate ? "Private browsing" : "Start browsing")).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: tab.isPrivate ? "eye.slash" : "globe") }
            }.buttonStyle(.plain)
            Spacer()
            if browser.selectedID == tab.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
            Button { browser.close(tab) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).accessibilityLabel("Close tab")
        }
    }
    private func pagesPanel(history: Bool) -> some View {
        BrowserPagesView(browser: browser, historyMode: history) { url in browser.navigate(url.absoluteString); panel = nil }
    }
}
private enum BrowserPanel: String, Identifiable { case tabs, bookmarks, history, downloads, data, protection, locks, media; var id: String { rawValue } }

private struct BrowserPageView: View {
    @ObservedObject var tab: BrowserTab
    var body: some View {
        VStack(spacing: 0) {
            if tab.web.isLoading { ProgressView(value: tab.web.estimatedProgress).progressViewStyle(.linear) }
            if let error = tab.pageError {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                    Text(error).multilineTextAlignment(.center)
                    Button("Reload") { tab.web.reload() }
                }.padding()
            }
            if tab.web.url == nil {
                VStack(spacing: 16) {
                    Spacer()
                    Image("JizaBrowser").resizable().scaledToFit().frame(width: 90, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    Text(tab.isPrivate ? "Browse privately" : "Explore with Jiza").font(.title2.bold())
                    Text("Search, open websites, and keep your favourite pages together.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Spacer()
                }.padding(32).frame(maxWidth: .infinity)
            }
            BrowserWebSurface(web: tab.web).frame(maxHeight: tab.web.url == nil ? 0 : .infinity)
        }
    }
}
private struct BrowserWebSurface: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
private struct BrowserPagesView: View {
    @ObservedObject var browser: BrowserModel
    let historyMode: Bool
    let open: (URL) -> Void
    @State private var search = ""
    @State private var confirmClear = false
    private var pages: [BrowserPage] {
        (historyMode ? browser.history : browser.bookmarks).filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.url.absoluteString.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List {
            if pages.isEmpty { Text(historyMode ? "No browsing history" : "No bookmarks yet").foregroundStyle(.secondary) }
            ForEach(pages) { page in
                Button { open(page.url) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(page.title).foregroundStyle(.primary)
                        Text(page.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if historyMode { Text(page.date, style: .date).font(.caption2).foregroundStyle(.secondary) }
                    }
                }.swipeActions { Button("Delete", role: .destructive) { historyMode ? browser.removeHistory(page.id) : browser.deleteBookmark(page.id) } }
            }
        }.searchable(text: $search).navigationTitle(historyMode ? "History" : "Bookmarks")
            .toolbar { if historyMode { ToolbarItem(placement: .navigationBarLeading) { Button("Clear") { confirmClear = true } } } }
            .confirmationDialog("Clear browsing history?", isPresented: $confirmClear) { Button("Clear history", role: .destructive) { browser.clearHistory() } }
    }
}

struct BrowserDownloadsView: View {
    @ObservedObject private var torrents = TorrentModel.shared
    @State private var chooseTorrent = false
    @EnvironmentObject private var browser: BrowserModel
    @ObservedObject var downloads: BrowserDownloads
    @State private var address = ""
    @State private var chooseFolder = false
    @State private var exportURL: ExportedFile?
    @State private var sharedFiles: [URL] = []
    var body: some View {
        List {
            Section("Torrents on this iPhone") {
                Button("Open .torrent file") { chooseTorrent = true }
                    .accessibilityIdentifier("openTorrentFile")
                Text("Downloads save in Jiza / Downloads / Torrents. Keep Jiza open while downloading; iOS can suspend transfers in the background.").font(.caption).foregroundStyle(.secondary)
                ForEach(torrents.rows.indices, id: \.self) { index in
                    let row = torrents.rows[index]
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row["name"] as? String ?? "Torrent").font(.headline)
                        Text(row["state"] as? String ?? "Connecting")
                        ProgressView(value: (row["progress"] as? NSNumber)?.doubleValue ?? 0)
                        Text("\((row["peers"] as? NSNumber)?.intValue ?? 0) peers · \((row["seeds"] as? NSNumber)?.intValue ?? 0) seeds · \((row["rate"] as? NSNumber)?.intValue ?? 0) bytes/s").font(.caption)
                        Button((row["paused"] as? Bool ?? false) ? "Resume" : "Pause") {
                            torrents.pause(!(row["paused"] as? Bool ?? false), index: (row["id"] as? NSNumber)?.intValue ?? index)
                        }
                    }
                }
                if let error = torrents.error { Text(error).foregroundStyle(.red) }
            }
            Section("Add download") {
                ForEach(sharedFiles, id: \.self) { file in
                    Button("Shared: " + file.lastPathComponent) {
                        if file.lastPathComponent == "Shared link.txt", let text = try? String(contentsOf: file, encoding: .utf8) { address = text }
                        else if file.pathExtension.lowercased() == "torrent" { torrents.importFile(file) }
                        else { exportURL = ExportedFile(url: file) }
                    }
                }
                Button("Refresh shared files") { sharedFiles = (try? SharedInbox.files()) ?? [] }
                TextField("File URL or magnet link", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Download URL") {
                    let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
                    if input.hasPrefix("magnet:") { torrents.start(input); address = ""; return }
                    guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)), BrowserModel.isWebURL(url), let tab = browser.selected else { downloads.error = "Enter a complete HTTP or HTTPS file URL."; return }
                    downloads.start(URLRequest(url: url), web: tab.web, isPrivate: tab.isPrivate); address = ""
                }
                Text("Paste a direct file URL or a magnet link. For a downloaded torrent, choose Open .torrent file above.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Save downloads to") {
                Text(downloads.folderName).font(.subheadline)
                Button("Choose download folder") { chooseFolder = true }
                Button("Use Jiza Downloads folder") { downloads.useDefaultFolder() }
                Text("Downloads also keep a copy in Jiza. Private downloads are saved files too. Keep Jiza open until downloads finish.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Downloads") {
                if downloads.items.isEmpty { Text("No downloads yet. Use a website's download link or Download this page or file in the browser menu.").foregroundStyle(.secondary) }
                ForEach(downloads.items) { item in
                    if let url = item.localURL, url.pathExtension.lowercased() == "torrent" {
                        Button("Start torrent: " + item.name) { torrents.importFile(url) }
                    }
                    BrowserDownloadRow(item: item) { exportURL = ExportedFile(url: $0) }
                        .swipeActions { Button("Forget", role: .destructive) { downloads.remove(item) } }
                }
            }
        }.navigationTitle("Downloader").scrollContentBackground(.hidden).background(JizaPalette.background)
            .onAppear { sharedFiles = (try? SharedInbox.files()) ?? [] }
            .task {
                while !Task.isCancelled {
                    torrents.refresh()
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { break }
                }
            }
            .fileImporter(isPresented: $chooseTorrent, allowedContentTypes: [.data, .item]) { result in
                switch result {
                case .success(let url): torrents.importFile(url)
                case .failure(let error): torrents.error = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $chooseFolder, allowedContentTypes: [.folder]) { result in
                switch result { case .success(let url): downloads.chooseFolder(url); case .failure(let error): downloads.error = error.localizedDescription }
            }
            .sheet(item: $exportURL) { ExportDownload(url: $0.url) }
            .alert("Downloads", isPresented: Binding(get: { downloads.error != nil }, set: { if !$0 { downloads.error = nil } })) { Button("OK") { downloads.error = nil } } message: { Text(downloads.error ?? "") }
    }
}
private struct BrowserDownloadRow: View {
    @ObservedObject var item: BrowserDownload
    let export: (URL) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.active ? "arrow.down" : item.localURL != nil ? "checkmark" : "exclamationmark")
                    .font(.headline).foregroundStyle(item.localURL != nil ? Color.green : JizaPalette.cobalt)
                    .frame(width: 40, height: 40).background(JizaPalette.background, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.headline).lineLimit(2)
                    Text(item.status).font(.caption).foregroundStyle(.secondary)
                }
            }
            if item.active {
                ProgressView(value: item.fraction)
                Text("\(ByteCountFormatter.string(fromByteCount: item.transferred, countStyle: .file)) / \(item.total > 0 ? ByteCountFormatter.string(fromByteCount: item.total, countStyle: .file) : "Unknown size") - \(ByteCountFormatter.string(fromByteCount: Int64(item.bytesPerSecond), countStyle: .file))/s").font(.caption)
                if item.status == "Downloading" { HStack { Button("Pause") { item.pause() }; Button("Cancel download") { item.cancel() } } }
            }
            if item.canResume && !item.active { Button("Resume download") { item.resume() } }
            if item.canRetry && !item.canResume && !item.active { Button("Retry download") { item.retry() } }
            if let url = item.localURL {
                HStack { ShareLink(item: url); Spacer(); Button("Save a copy") { export(url) } }
            }
        }.padding(.vertical, 6)
    }
}
private struct ExportedFile: Identifiable { let id = UUID(); let url: URL }
private struct ExportDownload: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController { UIDocumentPickerViewController(forExporting: [url], asCopy: true) }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}

private struct BrowserDataView: View {
    @State private var records: [WKWebsiteDataRecord] = []
    @State private var confirmClear = false
    @State private var busy = false
    var body: some View {
        List {
            Section {
                Text("Normal tabs keep cookies and website storage so you can stay signed in. Private tabs use temporary storage and do not save browsing history.").font(.subheadline)
                Text("Removing website data can sign you out. It does not remove bookmarks or saved downloads.").font(.caption).foregroundStyle(.secondary)
                Button("Clear all cookies and website data", role: .destructive) { confirmClear = true }.disabled(busy)
            }
            Section("Stored websites") {
                if busy { ProgressView() }
                if records.isEmpty && !busy { Text("No saved website data") }
                ForEach(records, id: \.displayName) { record in
                    Text(record.displayName).swipeActions {
                        Button("Delete", role: .destructive) {
                            busy = true
                            WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: [record]) { refresh() }
                        }
                    }
                }
            }
        }.navigationTitle("Website data").onAppear(perform: refresh)
            .confirmationDialog("Clear cookies and website data?", isPresented: $confirmClear) {
                Button("Clear website data", role: .destructive) {
                    busy = true
                    WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { refresh() }
                }
            }
    }
    private func refresh() {
        busy = true
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { values in
            records = values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }; busy = false
        }
    }
}

private struct BrowserProtectionView: View {
    @ObservedObject var protection: BrowserProtection
    var body: some View {
        Form {
            Section("Ads") {
                Toggle("Ad blocker", isOn: Binding(get: { protection.adBlockEnabled }, set: { protection.setAdBlock($0) }))
                Text("Blocks known advertising servers and common ad elements. Changing this setting reloads open tabs. Some first-party and in-video ads may remain.").font(.footnote)
                if !protection.ready { ProgressView("Preparing filters") }
                NavigationLink("Filter source & licence") {
                    ScrollView { Text((Bundle.main.url(forResource: "EasyList-Attribution", withExtension: "txt").flatMap { try? String(contentsOf: $0) }) ?? "The EasyList authors, https://easylist.to/ - CC BY-SA 3.0").font(.footnote).textSelection(.enabled).padding() }.navigationTitle("Filter attribution")
                }
                if let error = protection.error { Text(error).foregroundStyle(.red) }
            }
            Section("Pop-ups") {
                Toggle("Block pop-up windows", isOn: Binding(get: { protection.blockPopups }, set: { protection.setPopups($0) }))
                Text("Blocks script-created windows. Links you deliberately open in a new tab and file downloads remain available.").font(.footnote)
            }
        }.navigationTitle("Browser protection")
    }
}
