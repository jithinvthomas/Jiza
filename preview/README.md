# Jiza live design preview

Run `python preview/serve.py` from the repository and open http://127.0.0.1:8789.
The server binds only to this PC and serves an explicit allowlist of preview files and existing Jiza assets.
Changing index.html, style.css or app.js automatically reloads the browser. Keep this process running while reviewing.

This is an interactive web counterpart of the SwiftUI design, not an iOS emulator. Swift files do not automatically translate into this preview; update both implementations when a design is accepted. Web glass approximates the native material. The real iOS 26 app uses Apple's Liquid Glass renderer.

Working preview interactions: light/dark mode, portrait/landscape, screen navigation, sample audio and video playback, five-second full-screen controls, URL clearing, sample-page refresh and link actions, tabs and settings panels.
Downloads, authentication, trading and torrent engines are deliberately disconnected and labelled. No PIN or credentials are collected. Use simulator/device checks for actual app behavior.
