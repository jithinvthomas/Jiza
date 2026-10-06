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

## Video playback
- Choose **Open video file** from the header menu, then select a downloaded video in Files.
- Videos open in a full-screen viewer with native play/pause and seeking controls. Tap Done to return to music.
- Opening a video pauses music and cancels any pending music resume. Starting music closes the video.
- File access stays active during loading and playback. Closing the viewer releases it and prevents late loading from starting playback.
- Playback uses device-supported video codecs. MP4/MOV containers can still contain unsupported codecs; unreadable or unsupported media shows a recovery message.
- This first video build does not include a video folder library, saved viewing positions or Picture in Picture.
- Tests use a generated three-second H.264/AAC MP4 to check readiness, seeking, music handoff and cleanup, plus invalid-file and cancellation cases.
- On an iPhone, test a local MP4 and MOV, an iCloud video, portrait/landscape, calls and Bluetooth disconnection. Native AVPlayer handles video interruptions; real-call behavior still needs device verification.

## Native Liquid Glass
Build releases with Xcode 26 or newer. iOS 26 uses glassEffect and GlassEffectContainer; earlier iOS versions keep the material fallback. Reduce Transparency uses opaque panels and Reduce Motion disables interactive glass reactions. CI tests both paths.
https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views

## Jiza home
Jiza now opens with Player, Browser, and Trading choices. Back returns to the home menu; audio remains owned by the app while switching sections. Incoming audio/video files open Player directly.

Browser opens HTTPS websites inside Jiza using Safari Services. Trading saves a user-entered HTTPS server address on the device; no production address is assumed. The Python Jiza-Trading service must run on a server or authenticated development tunnel reachable from the phone. `localhost:8000` on a PC is not reachable as localhost on an iPhone. This change does not deploy or expose the trading backend.
