# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SwiftUI clients for a public IPCamLive beach camera in Csopak, Hungary. One Xcode project (`CsopakBeachCam.xcodeproj`) ships **four** app targets — iOS, tvOS, macOS, watchOS — plus iOS/tvOS test targets. There is no SwiftPM/CocoaPods/Carthage; everything is built with Xcode and the platform SDKs.

- Swift 5.0. Deployment targets: iOS 18.5, tvOS 18.5, macOS 14, watchOS 11.
- Bundle IDs are `hu.randart.CsopakBeachCam{,Mac,TV,.watch}` and matching `*Tests` / `*UITests`.

## Build & test

```bash
# Build a specific target (no workspace — open the xcodeproj directly)
xcodebuild -project CsopakBeachCam.xcodeproj -scheme CsopakBeachCam      -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -project CsopakBeachCam.xcodeproj -scheme CsopakBeachCamTV    -destination 'platform=tvOS Simulator,name=Apple TV' build

# Mac and Watch don't have shared schemes — build via Xcode UI, or pass the implicit scheme name with -scheme CsopakBeachCamMac / CsopakBeachCamWatch after the project generates user schemes.

# Tests (iOS + tvOS only)
xcodebuild -project CsopakBeachCam.xcodeproj -scheme CsopakBeachCam   -destination 'platform=iOS Simulator,name=iPhone 15' test
xcodebuild -project CsopakBeachCam.xcodeproj -scheme CsopakBeachCamTV -destination 'platform=tvOS Simulator,name=Apple TV' test

# Run a single test:
# -only-testing:CsopakBeachCamTests/CsopakBeachCamTests/<testMethodName>

# Verify the IPCamLive URL-extraction flow outside the app
node get-m3u8-playlist-from-ipcamlive.js
```

The macOS app is **menu-bar only** — `LSUIElement` is set, so when run there is no window or Dock icon. Look for the sailboat icon in the menu bar; right-click for Quit / Windguru Credentials.

## Releasing

Pushing a `v*` tag runs `.github/workflows/release.yml`: it builds the macOS app with `-target CsopakBeachCamMac` (deliberately not `-scheme` — the Mac scheme isn't shared, and CI only sees shared schemes), ad-hoc signs it (`codesign -s -`; Apple Silicon won't launch fully unsigned binaries), zips it with `ditto`, and publishes a GitHub release via `gh` with auto-generated notes. The tag minus the `v` prefix is injected as `MARKETING_VERSION`. Only the macOS app is released; the app is not notarized. No third-party actions beyond `actions/checkout` — keep it that way.

```bash
git tag v1.1.0 && git push origin v1.1.0
```

## Architecture

### Shared code is folder-linked, not a framework

Two source folders are attached to multiple targets as `fileSystemSynchronizedGroups` in the pbxproj — there is no shared library/target:

- `Shared/` → linked into **all four** app targets.
- `SharedWeather/` → linked into **iOS, macOS, and tvOS** (not watchOS).

Because the folders are synchronized, a new file dropped into one of them is compiled by **every** target that syncs it — platform-specific code inside these folders must be fenced with `#if os(...)` (see `WeatherOverlayView.swift`, `WindguruSettingsView.swift`) or it will break the other platforms' builds.

### Stream resolution (`Shared/StreamManager.swift`)

IPCamLive does not expose a stable HLS URL — it has to be derived per session:

1. Fetch `player.php?alias=<uniqueId>` HTML.
2. Regex out `groupaddress`, `token`, `alias` JS vars.
3. Hit `getcamerastreamstate.php` on the resolved host with a cache-buster timestamp.
4. From the JSON `details.address` + `details.streamid`, construct both `stream.m3u8` and `snapshot.jpg` URLs.

`CameraConfig.uniqueId` is the single switch for pointing all four apps at a different camera. The Node helper script mirrors this flow exactly — keep them in sync.

### Per-target playback strategy

Each platform plays the stream differently on purpose:

- **iOS** (`WebView.swift`): embeds the IPCamLive player page in `WKWebView` (inline + pinch-to-zoom). Idle timer is disabled so the screen stays on. In landscape, `ContentView` starts a `WeatherViewModel` and lays the (non-interactive) weather overlay over the video, plus a key button that sheets `WindguruSettingsView`; rotating back to portrait stops the polling.
- **tvOS** (`VideoStreamView.swift`): native `AVPlayerViewController` with the transport bar / PiP buttons stripped. Weather overlay pinned at top, non-interactive, covers in-stream watermark.
- **macOS** (`VideoStreamView.swift`): `AVPlayerView` with no controls or hover dimming. `DisplaySleepBlocker` uses `IOPMAssertion` to keep the display awake while playing.
- **watchOS**: no video player — polls `snapshot.jpg` every ~5s and displays as a `UIImage`. Uses `StreamManager` only for the snapshot URL.

### macOS app lifecycle (`CsopakBeachCamMac/AppDelegate.swift`)

The Mac app has a hand-rolled three-state UI tied to one `NSStatusItem`:

- **hidden** → click menu bar → **attached** (`NSPopover` with click-to-detach overlay)
- **attached** → click inside preview → **detached** (`NSWindow` with autosaved frame `CsopakBeachCamDetachedWindow`)
- **detached** → click menu bar → close window + reopen popover (**attached**)

Right-click (or ctrl-click) on the menu bar item shows the context menu via a temporarily-assigned `NSMenu` that's cleared after `performClick`. The attached popover hosts `ContentView(showWeather: false)`; the detached window hosts `ContentView(showWeather: true)`. The same `StreamManager` instance is passed into both so the stream survives the popover↔window transition.

### Weather overlay (`SharedWeather/`, iOS + macOS + tvOS)

Two-source feed, polled every ~90 s by `WeatherViewModel`:

- **Observations**: MET.hu open data portal (`odp.met.hu`). Station metadata is read from CSVs to discover the latest station IDs for Balatonfüred and Balatonalmádi; observations come as zipped CSVs (`HABP_10M_<id>_now.zip` or `HABP_10MWIND_<id>_now.zip`), unpacked in-process by `MiniZip` (a minimal store/deflate ZIP reader — no third-party deps).
- **Forecast**: Windguru Micro endpoint with the `aromehu` (AROME-HU 2.5 km) model. Parses the `<pre>` block — line shape is `"<weekday> <day>. <HH>h <wspd> <gust> ..."`. Custom Windguru spots (e.g. Palóznaki Öböl) need a **Windguru PRO** account, so credentials are stored in the platform Keychain via `WindguruCredentialsStore` (service `windguru-pro`, username mirrored in `UserDefaults`); they're entered through `WindguruSettingsView` (macOS context menu, iOS key-button sheet).

On refresh failure, the view model keeps the **previous good values** rather than blanking the UI — see `refresh()` in `WeatherViewModel.swift`. Preserve that behavior when changing this code; flickering on transient failures was an explicit thing to avoid (see commit `f187664`).

The overlay's map/hide/refresh buttons are gated `#if os(macOS)` — on iOS and tvOS it's render-only. Observations render as a combined wind + gust bar graph; forecast rows carry wind-direction arrows.

### Balaton forecast maps (`CsopakBeachCamMac/BalatonMapView.swift`, macOS only)

The map button in the overlay header toggles `ContentView` into map mode, replacing the video with AROME model forecast maps scraped from MET.hu's Balaton page (`met.hu/idojaras/tavaink/balaton/`). Frame filenames encode model run + lead time (`mwWB<run>_<HHMM>+<HHHMM>.jpg`); only frames valid today (Budapest time) are kept, and all images are prefetched. The overlay stays visible above the maps and highlights the selected frame's time.

## Conventions worth knowing

- The repo uses both `git` and `jj` (`.jj/` is present). Default to `git` unless the user asks otherwise.
- No linter or formatter is configured. Match surrounding style.
- Don't introduce SwiftPM dependencies casually — the "no third-party deps" stance is deliberate (see `MiniZip`).
- Test targets are skeletons (`CsopakBeachCamTests.swift` etc.) — there is effectively no test suite yet.
