import SwiftUI

struct ContentView: View {
    @StateObject private var streamManager = StreamManager()
    @StateObject private var snapshot = SnapshotLoader()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = snapshot.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if streamManager.isLoading || snapshot.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                    Button("Retry") {
                        Task { await refresh() }
                    }
                    .buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
            }
        }
        .task {
            await refresh()
        }
    }

    private func refresh() async {
        if streamManager.snapshotURL == nil {
            await streamManager.fetchStreamURL()
        }
        guard let url = streamManager.snapshotURL else { return }
        await snapshot.start(url: url)
    }
}

@MainActor
final class SnapshotLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false

    private var task: Task<Void, Never>?
    private let refreshInterval: UInt64 = 5_000_000_000

    func start(url: URL) async {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.fetch(url: url)
                try? await Task.sleep(nanoseconds: self.refreshInterval)
            }
        }
    }

    private func fetch(url: URL) async {
        if image == nil { isLoading = true }
        defer { isLoading = false }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let img = UIImage(data: data) {
                image = img
            }
        } catch {
            // Keep showing last good frame on transient failure
        }
    }

    deinit {
        task?.cancel()
    }
}
