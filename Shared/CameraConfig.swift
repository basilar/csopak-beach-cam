import Foundation

enum CameraConfig {
    static let uniqueId = "66799108828d0"

    static var playerPageURL: URL {
        URL(string: "https://g0.ipcamlive.com/player/player.php?alias=\(uniqueId)&autoplay=1")!
    }
}
