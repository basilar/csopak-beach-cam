import SwiftUI

struct ContentView: View {
    @StateObject private var streamManager: StreamManager
    @StateObject private var sleepBlocker = DisplaySleepBlocker()
    @StateObject private var weather = WeatherViewModel()
    private let showWeather: Bool

    @MainActor
    init(streamManager: StreamManager? = nil, showWeather: Bool = true) {
        _streamManager = StateObject(wrappedValue: streamManager ?? StreamManager())
        self.showWeather = showWeather
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
                ZStack(alignment: .top) {
                    VideoStreamView(url: streamURL)
                        .background(Color.black)
                    if showWeather {
                        if weather.visible {
                            WeatherOverlayView(viewModel: weather)
                                .padding(8)
                                .allowsHitTesting(true)
                        } else {
                            HStack {
                                Spacer()
                                Button {
                                    weather.visible = true
                                } label: {
                                    Image(systemName: "eye")
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                        }
                    }
                }
                .onAppear {
                    sleepBlocker.start()
                    if showWeather { weather.start() }
                }
                .onDisappear {
                    sleepBlocker.stop()
                    weather.stop()
                }
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
