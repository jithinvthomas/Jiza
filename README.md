# Jiza

## iPhone fixes
- The header menu offers Choose folder, Open audio file and Open video file.
- The background fills the display; the menu respects the safe area and content scrolls on short screens.
- The home-screen icon uses the cobalt doorway symbol without wording.
- The player displays embedded song artwork, with the Jiza doorway symbol as the fallback.
- Folder/file security access is retained until the selection changes.
- Import and playback failures display an explanation.
- Folder selection includes supported audio in subfolders, skips hidden files and symbolic links, and retains distinct files with matching names.

## Verify before packaging
On a Mac with Xcode and XcodeGen:
1. Run `xcodegen generate`.
2. Open `InteraMusicPlayer.xcodeproj` and choose an iPhone simulator.
3. Run Product > Test. Test on a small iPhone and a notched iPhone.
4. On a signed development build on an iPhone, open the top-left menu > Choose folder.
5. Select a folder in Files with at least two downloaded songs. Play both, skip tracks, pause/resume, and change folders.
6. Check cancelling the picker, an empty folder, a file with invalid audio, and an iCloud file that is not downloaded.
7. Check portrait, landscape, and larger accessibility text. The menu must remain visible and the playlist reachable by scrolling.

The simulator workflow builds and tests without generating an IPA.
Real iPhone folder-provider permissions require a device test.

## Artwork and icon checks
- TestFixtures contains generated 0.3-second audio with and without embedded cover art.
- Tests verify embedded artwork, missing-artwork fallback, clearing the cover on song changes,
  recursive folder discovery, and the built app's home-screen icon registration.
- On your iPhone, choose a parent folder containing songs in nested folders.
- Switch between songs with and without embedded cover art. The previous cover must clear.
- After installing, confirm the home-screen icon shows the Jiza doorway symbol.

The Jiza doorway symbol was generated with the built-in image tool and exported into Apple's icon sizes.
See Brand/IDENTITY.md for the original prompt and colour specification.

## Folder memory and calls
- A selected folder is saved as an iOS bookmark and restored once on launch, without autoplay.
- A new selection replaces the saved folder; opening an individual song keeps the last folder.
- If access has expired, the app asks you to choose the folder again.
- Calls pause playback. The same song resumes only if it was playing before the interruption
  and iOS supplies shouldResume. Pausing or changing the selection cancels pending resume.
- Audio-session activation happens when playback starts and errors are displayed.
- Disconnecting headphones pauses playback.
- Physical volume buttons retain the system volume behavior; no volume interception is installed.

### Required device checks
1. Choose a local folder, close and relaunch the app: its playlist returns, paused.
2. Repeat with iCloud and your preferred third-party Files provider, including after reboot.
3. Remove or revoke access to the saved folder: check the recovery message and choose another.
4. Play a song, receive and end a call: check same-song position and automatic resume.
5. Repeat when already paused, and after pressing Pause during the call: music stays paused.
6. Disconnect wired/Bluetooth headphones, including during a call: no unexpected speaker playback.
7. Press volume up/down during music: volume changes without changing the selected song.

Reference: https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions
Reference: https://developer.apple.com/documentation/uikit/providing-access-to-directories

## Jiza identity
The app uses the Cobalt Glass identity: a frosted doorway logo, ice/midnight backgrounds and translucent playback controls. Appearance follows the system or the Light/Dark choice in the music menu. Reduce Transparency uses opaque panels.
See [Brand/IDENTITY.md](Brand/IDENTITY.md) for colours, assets and generation prompts.
Repository: https://github.com/jithinvthomas/Jiza

Library search filters the selected folder without changing the playback queue.
UI tests cover the light layout, folder/video pickers and rotation back to portrait. Real-device checks should include dark appearance, Dynamic Type and Reduce Transparency.

## Native Liquid Glass
Build releases with Xcode 26 or newer. iOS 26 uses glassEffect and GlassEffectContainer; earlier iOS versions keep the material fallback. Reduce Transparency uses opaque panels and Reduce Motion disables interactive glass reactions. CI tests both paths.
https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views

## Jiza home
Jiza opens with Music, Video, Browser, and Trading choices. Incoming files open the appropriate player.

Browser uses WebKit with tabs, history, bookmarks and downloads. Trading saves a user-entered HTTPS server address on the device; no production address is assumed. The Python Jiza-Trading service must run on a server or authenticated development tunnel reachable from the phone. `localhost:8000` on a PC is not reachable as localhost on an iPhone. This change does not deploy or expose the trading backend.

## iPhone system playback controls
Audio playback registers play, pause, toggle, next, previous, and seek handlers with MPRemoteCommandCenter. Now Playing includes title, duration, elapsed position, playback rate, and cover art (Jiza fallback). Opening video releases the music handlers so they cannot restart audio while video owns playback.

Device verification after installing this build: play a folder containing two songs, lock the iPhone, check the Now Playing title/artwork, pause/resume, scrub, and skip both directions from Control Center and a Bluetooth accessory. Repeat during video playback and after returning to music. Volume buttons retain iOS volume behavior; accessory-specific long presses only skip if the accessory emits next/previous commands. Simulator tests cannot prove physical Bluetooth or Lock Screen integration.

Reference: https://developer.apple.com/documentation/mediaplayer/mpremotecommand

## Expanded Video section (October 2026)
The home menu now has Music, Video, Browser and Trading. Video has its own generated Jiza film/play logo and a separate folder library with recursive search, reverse ordering, remembered folder access, and saved playback positions. Direct HTTPS and RTSP media URLs can be opened from the library.

Native playback retains Apple's transport controls, AirPlay and Picture in Picture. Files that cannot use native playback fall back to the existing MobileVLCKit dependency; the library also offers Compatibility playback. Additional controls include 0.25-3x speed, Fit/Fill/Stretch, audio-track and embedded-subtitle menus, SRT/ASS/SSA/VTT import through VLC, subtitle timing adjustment, repeat, sleep timer, screen lock, brightness and system volume. VLC controls include a seek bar, double-tap +/-10 seconds and horizontal swipe seeking. Music and video retain exclusive playback ownership.

Limits: native PiP and AirPlay are not promised for VLC; VLC video pauses when the app backgrounds. SMB/DLNA discovery, Chromecast, automatic online-subtitle search, and full parity with desktop VLC/PotPlayer are not implemented. File formats/codecs and streams remain dependent on the content, device and server. Device tests are still required for PiP restoration, AirPlay, file-provider permission renewal, rotation and Bluetooth.

Video logo generated with the built-in image tool from the original cobalt doorway logo: preserve original mark/background and add a frosted glass film frame with a play triangle at lower right, no text. Asset: Assets.xcassets/JizaVideo.imageset/logo.png. See Licenses for VideoLAN source/license information.

## Browser and Files-provider update
Phase 3 now includes an embedded WKWebView browser with normal/private tabs, session restoration for normal pages, back/forward/reload, address/search entry, desktop user-agent mode, page zoom, find, sharing, persistent bookmarks, searchable history, and website-data/cookie deletion. Private tabs share an ephemeral data store until the last private tab closes, and never persist their browsing history or session URLs. Bookmarks explicitly saved from private tabs are retained.

Downloads use WKDownload with progress, cancellation, and in-session resume when WebKit supplies resume data. Completed normal download records persist. Choose a destination folder in Downloads; files are saved in Jiza/Documents/Downloads and copied to the selected Files-provider folder using a remembered security-scoped bookmark and coordinated writing. If that folder is unavailable, the Jiza copy remains available for Share/Save a copy. Names are sanitized and existing files are never overwritten. Files sharing exposes the Jiza Downloads folder in Files. Private downloads still create saved files, as disclosed in the download screen. Active downloads need Jiza to stay open; background queue restoration is not implemented.

Video import now coordinates reading with the Files provider and copies into an app-owned temporary file before playback, instead of rejecting files that are not materialized yet. Copies are released after playback. YouTube/Vimeo/Dailymotion page links entered in Video open in Jiza Browser; they are not passed to AVPlayer as direct streams. Website playback is subject to the website's restrictions. No YouTube extraction, DRM bypass, or universal website-video downloader is implemented. VLC wording is removed from playback controls; dependency notices remain under acknowledgements.

Browser security: user input accepts HTTP/HTTPS web addresses or encoded search queries; URL credentials and file/custom-scheme navigation are rejected. WebKit handles TLS validation without custom trust bypass. HTTP pages are labelled Not secure; the ATS exception applies only to web content, as required for a general-purpose browser. This app has no JavaScript-to-native command bridge. Private storage is ephemeral, not an anonymity service.

Verification: simulator tests cover coordinated MP4 copying/playback/cleanup, URL routing, private tab storage isolation, history/bookmark persistence, actual local HTTP browsing, cookies, and a WKDownload copied to a selected folder. UI tests cover tab creation and Files-folder selection. Physical-device checks remain necessary for your exact iCloud/third-party provider, YouTube playback, interrupted downloads and large files. UC Browser feature parity, ad blocking, proxy/data compression, extensions and background download restoration are not claimed.

Apple API references:
- https://developer.apple.com/documentation/foundation/nsfilecoordinator
- https://developer.apple.com/documentation/webkit/wkdownloaddelegate
- https://developer.apple.com/documentation/webkit/wkwebsitedatastore/nonpersistent()
- https://developer.apple.com/documentation/webkit/wkhttpcookiestore
- https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsinwebcontent

For local Xcode integration tests, first run python3 browser_test_server.py in the repository; CI starts and stops this loopback-only fixture automatically.

## Download routing, protection and locks
Direct file links now download by default, including playable MP4/MP3 responses, MIME-only media endpoints, redirecting links, and .torrent metadata files. Embedded media inside a webpage is not intercepted. New-window file links do not leave an empty tab. Disable Automatically download file links to restore inline navigation. Long-press any web link for Download link, paste a direct HTTP/HTTPS file URL in Downloads, or use Download media on this page to inspect direct media elements. Downloads retain the WebKit session/cookies. Transfer details include bytes, average speed, pause, in-session resume where supported, and retry for GET requests. This is not segmented IDM acceleration, a BitTorrent peer client, or a DRM/segmented-stream extractor. Keep Jiza open for active downloads.

Browser protection provides independently persisted Ad blocker and Block pop-up windows settings. The bundled baseline WebKit rules block known advertising hosts, common ad paths and ad elements. They do not guarantee removal of every first-party or in-video ad. Toggling the ad blocker reapplies rules and reloads existing tabs. Script-created pop-ups are blocked by default; intentional links and direct downloads remain available.

Home > Privacy and locks enables device-owner authentication (Face ID/Touch ID with iPhone passcode fallback) and a separate six-digit browser PIN. Lock configuration, salted PBKDF2-HMAC-SHA256 PIN verification data (600,000 iterations), and failed-attempt cooldown state are stored in the device-only Keychain. No plaintext PIN is saved. Five incorrect attempts start a 30-second delay, increasing to five minutes; relaunch does not reset it. Changing/removing a PIN requires device-owner authentication; Forgot PIN uses the same authenticated recovery. Lock-state writes must succeed before granting access. Backgrounding invalidates pending authentication and relocks sessions. A scene-level window obscures all sheets/covers and app-switcher previews. App-locked incoming media waits for authentication. These locks restrict UI access, not copies already exported to Files.

Threat boundaries: untrusted page URLs/filenames are validated; file names cannot escape download directories; arbitrary page JS is never interpolated into native commands. Authentication cancellation and unavailable Keychain data fail closed. App locking closes video on background so PiP cannot expose it. Existing background music can continue. Device validation remains required for physical Face ID, lockscreen transitions, Files providers, server-dependent resume and site-specific downloads.