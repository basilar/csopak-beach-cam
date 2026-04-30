import SwiftUI
import AVKit
import AVFoundation

struct VideoStreamView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { setupPlayer() }
            .onDisappear { player?.pause() }
    }

    private func setupPlayer() {
        let player = AVPlayer(url: url)
        player.allowsExternalPlayback = true
        self.player = player
        player.play()
    }
}
