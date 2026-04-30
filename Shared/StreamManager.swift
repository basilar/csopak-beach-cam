import Foundation

enum StreamError: Error {
    case invalidURL
    case invalidStreamInfoURL
    case invalidJSON
}

@MainActor
final class StreamManager: ObservableObject {
    @Published var streamURL: URL?
    @Published var snapshotURL: URL?
    @Published var isLoading = false

    private let uniqueId: String

    init(uniqueId: String = CameraConfig.uniqueId) {
        self.uniqueId = uniqueId
    }

    func fetchStreamURL() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let urls = try await Self.extractURLsForIpCamLive(uniqueId: uniqueId)
            streamURL = URL(string: urls.stream)
            snapshotURL = URL(string: urls.snapshot)
        } catch {
            print("Failed to fetch stream URL: \(error)")
            streamURL = nil
            snapshotURL = nil
        }
    }

    private static func extractURLsForIpCamLive(uniqueId: String) async throws -> (stream: String, snapshot: String) {
        let playerURL = "https://g0.ipcamlive.com/player/player.php?alias=\(uniqueId)"

        guard let url = URL(string: playerURL) else {
            throw StreamError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let html = String(data: data, encoding: .utf8) ?? ""

        let streamInfoUrl = extractStreamInfoUrlFromHtml(htmlContent: html)

        guard let streamInfoURL = URL(string: streamInfoUrl) else {
            throw StreamError.invalidStreamInfoURL
        }

        let (streamData, _) = try await URLSession.shared.data(from: streamInfoURL)
        let jsonString = String(data: streamData, encoding: .utf8) ?? ""

        guard let jsonData = jsonString.data(using: .utf8),
              let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let details = jsonObject["details"] as? [String: Any],
              let baseAddress = details["address"] as? String,
              let streamId = details["streamid"] as? String else {
            throw StreamError.invalidJSON
        }

        return (
            stream: "\(baseAddress)streams/\(streamId)/stream.m3u8",
            snapshot: "\(baseAddress)streams/\(streamId)/snapshot.jpg"
        )
    }

    private static func extractStreamInfoUrlFromHtml(htmlContent: String) -> String {
        func extractVariable(_ html: String, _ varName: String) -> String? {
            let pattern = "var \(varName)\\s*=\\s*['\"]([^'\"]*)['\"];"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) else {
                return nil
            }
            return String(html[Range(match.range(at: 1), in: html)!])
        }

        let groupaddress = extractVariable(htmlContent, "groupaddress") ?? ""
        let token = extractVariable(htmlContent, "token") ?? ""
        let alias = extractVariable(htmlContent, "alias") ?? ""

        guard let groupURL = URL(string: groupaddress) else {
            return ""
        }

        let domain = groupURL.host ?? ""
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)

        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        components.path = "/player/getcamerastreamstate.php"
        components.queryItems = [
            URLQueryItem(name: "_", value: String(timestamp)),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "alias", value: alias),
            URLQueryItem(name: "targetdomain", value: domain),
            URLQueryItem(name: "bufferingpercent", value: "0")
        ]

        return components.url?.absoluteString ?? ""
    }
}
