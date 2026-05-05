import SwiftUI
import AVKit
import AVFoundation

struct VideoStreamView: NSViewRepresentable {
    let url: URL
    var onReloadRequested: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = false
        view.videoGravity = .resizeAspect
        context.coordinator.onReloadRequested = onReloadRequested
        context.coordinator.attach(to: view, url: url)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        context.coordinator.onReloadRequested = onReloadRequested
        if context.coordinator.currentURL != url {
            context.coordinator.attach(to: nsView, url: url)
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var onReloadRequested: (() -> Void)?
        private(set) var currentURL: URL?
        private weak var playerView: AVPlayerView?
        private var player: AVPlayer?
        private var statusObservation: NSKeyValueObservation?
        private var timeControlObservation: NSKeyValueObservation?
        private var notificationTokens: [NSObjectProtocol] = []
        private var watchdog: Timer?
        private var lastReloadAt: Date?

        func attach(to view: AVPlayerView, url: URL) {
            teardownPlayer()
            playerView = view
            currentURL = url
            let newPlayer = AVPlayer(url: url)
            newPlayer.allowsExternalPlayback = true
            view.player = newPlayer
            player = newPlayer
            observe(player: newPlayer)
            newPlayer.play()
        }

        func detach() {
            teardownPlayer()
            currentURL = nil
        }

        private func teardownPlayer() {
            stopWatchdog()
            statusObservation?.invalidate()
            statusObservation = nil
            timeControlObservation?.invalidate()
            timeControlObservation = nil
            for token in notificationTokens {
                NotificationCenter.default.removeObserver(token)
            }
            notificationTokens.removeAll()
            player?.pause()
            playerView?.player = nil
            player = nil
        }

        private func observe(player: AVPlayer) {
            guard let item = player.currentItem else { return }
            let center = NotificationCenter.default

            let interruptionNames: [Notification.Name] = [
                AVPlayerItem.playbackStalledNotification,
                AVPlayerItem.failedToPlayToEndTimeNotification,
                AVPlayerItem.didPlayToEndTimeNotification
            ]
            for name in interruptionNames {
                let token = center.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                    self?.handleInterruption()
                }
                notificationTokens.append(token)
            }

            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                DispatchQueue.main.async { self?.handleInterruption() }
            }

            timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                let isPlaying = player.timeControlStatus == .playing
                DispatchQueue.main.async {
                    if isPlaying {
                        self?.stopWatchdog()
                    } else {
                        self?.startWatchdog()
                    }
                }
            }
        }

        private func startWatchdog() {
            stopWatchdog()
            watchdog = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                self?.handleInterruption()
            }
        }

        private func stopWatchdog() {
            watchdog?.invalidate()
            watchdog = nil
        }

        private func handleInterruption() {
            let now = Date()
            if let last = lastReloadAt, now.timeIntervalSince(last) < 5 {
                return
            }
            lastReloadAt = now

            if let view = playerView, let url = currentURL {
                attach(to: view, url: url)
            }
            onReloadRequested?()
        }
    }
}
