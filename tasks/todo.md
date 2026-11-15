# Jiza Music + Video tasks

First single-file video increment implemented. Remaining device checks and library features are tracked below.

## 1. Establish the music and orientation baseline
- [ ] Confirm playback, folder restore, calls, volume and Bluetooth on iPhone.
- [ ] Diagnose landscape behavior and restore a reliable rotation UI test, including return to portrait.
- [ ] Verify existing CI tests on both runners and capture portrait/landscape evidence.

Dependencies: none. Likely files: ContentView.swift, MusicPlayerUITests.swift, project.yml, Info.plist. Scope: medium.

## 2. Play a single video
- [x] Open a playable video from Files and use native play/pause, seek and full-screen controls.
- [ ] Starting video pauses music and starting music pauses video; call handling resumes only the eligible active player.
- [x] Unsupported or unreadable videos show a recoverable error.

Verification: playback/handoff tests, existing CI, real-device sample videos and interruption checks.
Evidence: commit c61560e passed both simulator jobs in run 37004436673. Tests load and seek an H.264/AAC sample, check music/video handoff, invalid files and close-during-load. Device checks remain pending.
Dependencies: 1. Likely files: new VideoPlayerModel.swift and VideoPlayerView.swift, JizaApp.swift, AudioPlayerModel.swift, new VideoPlayerModelTests.swift. Scope: medium.

## Checkpoint: playback foundation
- [ ] Music and video work independently and never overlap.
- [ ] Both CI jobs pass; review the first video build on iPhone.

## 3. Browse video folders
- [ ] Choose and restore a video folder without autoplay; preserve existing music bookmarks.
- [ ] List nested videos with title and asynchronously loaded thumbnail; handle missing provider access.
- [ ] Search and filter Music/Videos in a shared Library, with a music mini-player while browsing.

Verification: folder/filter tests, large-folder responsiveness, relaunch/provider checks and visual review.
Dependencies: 2. Likely files: new MediaLibraryModel.swift, new MediaLibraryTests.swift, ContentView.swift, VideoPlayerModel.swift, JizaApp.swift. Scope: medium; split model and UI into separate commits if necessary.

## 4. Resume videos
- [ ] Save position across termination/relaunch using a stable file identity.
- [ ] Offer Continue Watching and restart; completed videos start from the beginning on next play.
- [ ] Changed, missing or inaccessible files fail safely without resuming a different item.

Verification: persistence, completion, changed-file and interrupted-playback tests plus real-device relaunch.
Dependencies: 3. Likely files: VideoPlayerModel.swift, MediaLibraryModel.swift, ContentView.swift, VideoPlayerModelTests.swift. Scope: medium.

## Checkpoint: library and persistence
- [ ] Browse, play, close and resume a video end to end.
- [ ] Music bookmark and call regression tests remain green.

## 5. Finish the iPhone test release
- [ ] Enable and verify supported Picture in Picture, embedded subtitle/audio controls, and correct return to the app.
- [ ] Verify light/dark, large text, reduced transparency, portrait and landscape.
- [ ] Build and deliver a distinct IPA after both CI jobs pass; record real-device results and remaining limits.

Verification: existing CI workflow, native-player device checklist and release IPA smoke test.
Dependencies: 4. Likely files: VideoPlayerView.swift, ContentView.swift, MusicPlayerUITests.swift, README.md, ROADMAP.md. Scope: medium.

## Final checkpoint
- [ ] All acceptance checks above pass and device evidence is recorded.
- [ ] User reviews the Music + Video build before the downloads phase.
