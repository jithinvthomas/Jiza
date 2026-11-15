# All-in-one Jiza release

Source baseline: `feature/jiza-home-hub`, commit `0bb6ccf60885428838f2ba7614450239b6f0a401`.
The default `main` branch contains a separate Windows download-manager update and the older iOS music app. Its successful IPA builds do not validate the all-in-one iOS app.

## Release fixes

- Combine PR #4's Terminal and Remote Desktop with Music, Video, Browser, Downloader and Trading in the same home screen. Keep existing media, browser, lock and download code.
- Terminal and Desktop share an HTTPS-only viewer with connection errors, isolated in-memory website data and cleanup on leaving. Saved gateway addresses reject credentials, queries and fragments. No SSH/RDP service is deployed or exposed by this source integration.

- Preserve HTTP and destination errors when WebKit subsequently reports cancellation.
- Wait for cancellation to finish before exposing Resume or Retry. Reject callbacks from replaced transfers and honor cancellation while a new transfer is being created.
- Preserve the atomic saving step; saved files must not acquire a Retry action through cancellation.
- Accept shared text files returned as file URLs, holding provider access until copying finishes.
- Mount the ad-block integration-test web view in a window and wait for the requested navigation, rather than a previous page title.
- Scroll to the download-folder action before tapping it in the UI test.
- Require both simulator jobs before IPA packaging, and export readable test summaries alongside screenshots.

## Verification

Native XCTest and archive validation must run on macOS through the checked-in workflows. Windows source checks and review are not substitutes for those results.

Target device: iPhone 14 Pro with the user's latest installed iOS. Compatibility CI uses macOS 15 / Xcode 16.3 and explicitly installs iOS 18.4 for an iPhone 14 Pro simulator; the runner's preinstalled iOS 18.5 runtime does not match that SDK. macOS 14 runners were retired on 2 November 2026. Xcode 16.4 was excluded after the documented missing-libswiftWebKit simulator launch crash (https://developer.apple.com/forums/thread/785964). The other job retains the newer iOS SDK and simulator coverage. Jobs have a 40-minute limit so a launch failure cannot hang for six hours.

The baseline's macOS 14 simulator job passed. Its macOS 26 job failed in ad-block integration and download-folder UI coverage. These tests remain enabled with their behavior assertions intact.

Before calling the release complete, record the new CI results, package the exact tested commit, and test the signed IPA on iPhone: music/video handoff, calls, Bluetooth, folder permissions after relaunch, share a text file, download pause/resume/retry, app/browser locks, rotation, large text, PiP and Trading connectivity.

Limits remain as documented in README: active browser/torrent transfers require Jiza to stay open; server resume and media compatibility vary; exported files remain accessible through Files. Background download restoration and a general file manager are not implemented by this repair.
