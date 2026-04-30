# Csopak Beach Cam

SwiftUI clients for a live beach camera in Csopak, Hungary, powered by [IPCamLive](https://ipcamlive.com/). The project ships four apps from one workspace: **iPhone/iPad**, **Apple TV**, **Mac**, and **Apple Watch**.

## Platforms

| Target | Behavior |
|--------|----------|
| **iOS** (`CsopakBeachCam`) | Embeds the IPCamLive web player in a `WKWebView` with inline playback and pinch-to-zoom. The idle timer is disabled so the screen stays on while you watch. |
| **tvOS** (`CsopakBeachCamTV`) | Resolves the HLS stream URL and plays it with `AVPlayer` / `VideoPlayer`. |
| **macOS** (`CsopakBeachCamMac`) | Menu-bar-only app (no Dock icon). Click the menu bar icon to drop down a small live preview; click anywhere inside the preview to detach it as a resizable window; click the menu bar icon again to re-attach. Right-click the icon for **Quit**. The detached window's position and size are remembered between sessions. Display sleep is suppressed via `IOPMAssertion` while the stream is playing. Plays the HLS stream with `AVPlayer` / `VideoPlayer`. |
| **watchOS** (`CsopakBeachCamWatch`) | Fetches periodic JPEG snapshots (about every 5 seconds) for a lightweight wrist experience. |

Shared logic lives under `Shared/`:

- `CameraConfig` — camera alias / player URL.
- `StreamManager` — loads the IPCamLive player HTML, derives the stream state API URL, reads JSON, and produces HLS (`stream.m3u8`) and snapshot (`snapshot.jpg`) URLs.

## Requirements

- **Xcode** with current iOS, tvOS, macOS, and watchOS SDKs (project targets **iOS 18.5**, **tvOS 18.5**, **macOS 14**, **watchOS 11** as configured in the Xcode project).
- Valid **signing** for each bundle identifier you build (Apple Watch companion apps must use a bundle ID prefixed with the iOS app’s bundle ID plus a dot; see Apple’s Watch app packaging rules).

## Building

1. Open `CsopakBeachCam.xcodeproj` in Xcode.
2. Select the scheme for the platform you want: **CsopakBeachCam**, **CsopakBeachCamTV**, **CsopakBeachCamMac**, or **CsopakBeachCamWatch**.
3. Choose a simulator or device, then **Run** (⌘R).

For the **macOS** scheme, pick **My Mac** as the destination. After launch the app has no window or Dock icon — look for the sailboat icon in the menu bar.

Unit and UI test targets exist for iOS and tvOS.

## Pointing at another camera

Change the IPCamLive alias in `Shared/CameraConfig.swift` (`uniqueId` and related URLs). The same value is used by all targets that resolve streams through `StreamManager`.

## Helper script

`get-m3u8-playlist-from-ipcamlive.js` is a small **Node.js** utility that mirrors the URL extraction flow in `StreamManager` — useful for debugging or verifying stream endpoints outside the app:

```bash
node get-m3u8-playlist-from-ipcamlive.js
```

(Requires a recent Node with `fetch`.)

## Third-party stream

Video is served by **IPCamLive** and its CDN; availability and terms depend on that service. This repository only contains the client apps.

## License

This project is released under the [MIT License](LICENSE).
