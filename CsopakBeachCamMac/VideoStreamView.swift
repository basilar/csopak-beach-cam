import SwiftUI
import AVKit
import AVFoundation

struct VideoStreamView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = false
        view.videoGravity = .resizeAspect
        let player = AVPlayer(url: url)
        player.allowsExternalPlayback = true
        view.player = player
        player.play()
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if (nsView.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            let player = AVPlayer(url: url)
            player.allowsExternalPlayback = true
            nsView.player = player
            player.play()
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}
