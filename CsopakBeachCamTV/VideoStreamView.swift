import SwiftUI
import UIKit
import AVFoundation

struct VideoStreamView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.setStream(url: url)
        return view
    }

    func updateUIView(_ view: PlayerHostView, context: Context) {
        view.setStream(url: url)
    }

    static func dismantleUIView(_ view: PlayerHostView, coordinator: ()) {
        view.tearDown()
    }
}

final class PlayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    override var canBecomeFocused: Bool { false }

    private var player: AVPlayer?
    private var currentURL: URL?

    private var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }

    func setStream(url: URL) {
        if currentURL == url, player != nil { return }
        currentURL = url
        let newPlayer = AVPlayer(url: url)
        playerLayer?.videoGravity = .resizeAspect
        playerLayer?.player = newPlayer
        player = newPlayer
        newPlayer.play()
    }

    func tearDown() {
        player?.pause()
        playerLayer?.player = nil
        player = nil
        currentURL = nil
    }
}
