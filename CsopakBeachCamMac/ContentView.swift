import SwiftUI

struct ContentView: View {
    @StateObject private var streamManager: StreamManager
    @StateObject private var sleepBlocker = DisplaySleepBlocker()

    @MainActor
    init(streamManager: StreamManager? = nil) {
        _streamManager = StateObject(wrappedValue: streamManager ?? StreamManager())
    }

    var body: some View {
        Group {
            if streamManager.isLoading && streamManager.streamURL == nil {
                ProgressView("Loading stream…")
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else if let streamURL = streamManager.streamURL {
                VideoStreamView(url: streamURL)
                    .background(Color.black)
                    .onAppear { sleepBlocker.start() }
                    .onDisappear { sleepBlocker.stop() }
            } else {
                VStack(spacing: 16) {
                    Text("Failed to load stream")
                        .foregroundColor(.white)
                    Button("Retry") {
                        Task { await streamManager.fetchStreamURL() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }
        }
        .task {
            if streamManager.streamURL == nil {
                await streamManager.fetchStreamURL()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
