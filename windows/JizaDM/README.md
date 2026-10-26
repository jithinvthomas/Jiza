# Jiza Download Manager

An Internet Download Manager–style app for Windows (`JizaDM.exe`), built from the downloader in the Jiza iOS app
(`~/dev/intera-music-player`: `BrowserDownloads.swift`, `BrowserDownloadPolicy.swift`, `TorrentModel.swift`).

## What it does
- **Accelerated downloads**: 16 parallel connections per file by default (up to 32). When a connection finishes, it takes over
  half of the slowest remaining range, so every connection stays busy to the last byte. Sparse preallocation, 256 KB buffers,
  HTTP/1.1 on purpose (HTTP/2 would multiplex everything onto one connection), and Happy Eyeballs, so a broken IPv6 route doesn't stall connections.
- **Resume** after pause, crash or reboot (segment state in `%AppData%\JizaDM\downloads.json`, `If-Range` detects changed files).
- **Adapts to limiting servers**: when a server answers 429/503 to extra connections, those connections retire and the rest carry on.
- **Any link**: HTTP(S), FTP/FTPS, HLS `.m3u8` (parallel segments, AES-128), video sites and DASH via yt-dlp (1000+ sites,
  quality picker), magnet links and `.torrent` files (MonoTorrent with DHT, peer exchange and fast resume). DRM-protected services are not supported.
- **Queue and scheduler**: concurrent download limit, global and per-download speed limits, start/stop times, days, and when-done actions (exit, sleep, shutdown).
- **Browser integration** for Chrome, Edge, Brave and Vivaldi: takes over downloads with their cookies and referrer, adds "Download with Jiza" right-click
  menus, adds a floating "Download with Jiza" button on videos, and detects streams. Also `jiza://download?url=...` links.
- **Clipboard monitor**, tray icon, drag-and-drop of links and `.torrent` files, categories, Jiza cobalt-glass dark theme.

## Build
```
dotnet test tests/Jiza.Core.Tests
dotnet publish src/Jiza.App -c Release -o dist      # -> dist/JizaDM.exe (self-contained, single file)
```

## Install the browser extension (one time)
1. Run `JizaDM.exe` once. It registers itself for Chrome/Edge/Brave (per user, HKCU) and unpacks the extension to `%AppData%\JizaDM\extension`.
2. Open `chrome://extensions` (or `edge://extensions`), turn on **Developer mode**, click **Load unpacked**, and choose that folder.
   The extension ID is fixed (`ajdhdfdokfleaaafolicdlbafcfhdhne`) by the `key` in `extension/manifest.json`.

## Layout
- `src/Jiza.Core`: engine (HTTP, FTP, HLS, yt-dlp, torrents), queue, persistence, plus naming and policy ported from Jiza.
- `src/Jiza.App`: WPF app, tray, clipboard monitor, scheduler, named-pipe IPC, native messaging host.
- `extension/`: Manifest V3 browser extension.
- `tests/Jiza.Core.Tests`: xUnit tests against a local Kestrel server (ranges, no ranges, 429 limits, slow resume, HLS AES-128).
