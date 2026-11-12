# Jiza Remote Workspace

This iOS 16+ SwiftUI app now includes the existing Music player, a Pocket Terminal tab, and a Remote Desktop tab. The new workspace visual language uses original SwiftUI components with dark navy surfaces, cyan/mint accents, rounded device cards, and shared spacing tokens in `JizaWorkspaceDesign.swift`.

## Design inspiration

The project uses the idea of reusable, theme-driven SwiftUI components popularized by open-source libraries such as [ThemeKit](https://github.com/isamercan/ThemeKit) and [HIGDesign](https://github.com/promptdora/HIGDesign). **No source from these projects has been copied and neither package is installed**; the app retains its original iOS 16 deployment target and avoids additional dependencies.

## What works in the code

- **Music:** existing audio player remains in its tab.
- **Terminal:** Oracle Cloud and Windows entry cards save separate authenticated HTTPS terminal gateway URLs. A configured card opens that web terminal inside a WKWebView. `claude` and `codex` are shown as commands to use once connected; the app does **not** silently run either CLI.
- **Remote Desktop:** Oracle Ubuntu and Windows Pro entry cards open a private Guacamole HTTPS web app with the saved encoded Guacamole client key. The app does **not** implement native RDP or VNC itself.
- **Authentication:** delegated to the gateway / Guacamole. No SSH private keys or RDP passwords are bundled in this app.

## Required server deployment — not performed by this repository

1. On Oracle Ubuntu, check OS, disk space and available memory before installing a graphical desktop or Docker. Small Oracle instances may not be suitable for both Guacamole and XFCE.
2. Install and authenticate [Tailscale](https://tailscale.com/download/linux) on Oracle Ubuntu, [Windows](https://tailscale.com/download/windows) and the iPhone. Keep all hosts in your authorized private tailnet.
3. Enable **Remote Desktop** on Windows Pro under Settings > System > Remote Desktop. Use a proper account password and Network Level Authentication. Restrict inbound RDP to the Tailscale interface/private addresses. Never open TCP 3389 on the public internet.
4. If you need a graphical Ubuntu desktop, install a light desktop environment such as XFCE and configure XRDP. Restrict XRDP access to local/private networking; never expose its RDP port publicly.
5. Deploy [Apache Guacamole](https://guacamole.apache.org/doc/gug/) on Oracle, for example with Docker. It requires Guacamole web app, guacd, and an authentication provider/database. Configure strong sign-in and MFA where available. Bind HTTP to **127.0.0.1** and isolate guacd/database from the public network.
6. Use [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve) to privately expose Guacamole over HTTPS. Check the URL in iPhone Safari while Tailscale is enabled before adding it to Jiza. Do **not** use Tailscale Funnel (public exposure).
7. In Guacamole, create an RDP connection to the **Windows Tailscale IP** and a separate RDP connection to **Ubuntu**'s private RDP endpoint. Test both from Safari first.
8. In Guacamole, open each connection and copy the **encoded key after `#/client/`** from the address bar. Jiza Desktop Settings asks for the HTTPS Guacamole base URL and these encoded *client keys*. A plain numeric connection ID will not work.
9. For the Terminal tab, deploy an authenticated HTTPS interactive PTY/SSH web gateway on private Tailscale (this is **separate** from the Guacamole desktop entry unless it provides the desired web terminal). Configure one HTTPS URL for Oracle and optionally another for Windows. Do not paste the server's SSH public IP into the HTTPS field.
10. Install and authenticate Claude Code and Codex CLI on the remote host using the official vendor setup, and optionally use `tmux` for long-lived coding sessions.

### Example private addresses (not real configuration)

Guacamole gateway: `https://oracle-node.example-tailnet.ts.net/guacamole/`

Windows RDP endpoint inside Guacamole: `100.x.y.z:3389`

Ubuntu terminal HTTPS gateway: `https://oracle-terminal.example-tailnet.ts.net/`

**Never commit passwords, API keys, authentication cookies, private SSH keys, or production environment files.**

## Build on Mac

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open InteraMusicPlayer.xcodeproj
```

Set the Xcode signing team and select your connected iPhone. Build and run. You can reuse the existing bundle ID if it is still associated with the correct signing identity.

## Validation checklist

- [ ] Generate the project in XcodeGen
- [ ] Compile iOS Swift sources on a Mac/Xcode installation
- [ ] Verify music playback and audio file imports still work
- [ ] Verify Terminal Oracle and Windows settings persist
- [ ] Verify Guacamole login and desktop rendering over Tailscale
- [ ] Test keyboard, gestures, screen rotation and iPhone disconnects
- [ ] Confirm public IP cannot reach Guacamole, guacd, XRDP or Windows RDP
- [ ] Review the draft pull request before merging

This branch is a **source integration**, not a deployed or device-tested remote access system.
