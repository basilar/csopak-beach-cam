import SwiftUI

struct ContentView: View {
    @StateObject private var streamManager: StreamManager
    @StateObject private var sleepBlocker = DisplaySleepBlocker()
    @StateObject private var weather = WeatherViewModel()
    @StateObject private var mapModel = BalatonMapViewModel()
    @State private var isMapMode = false
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
                Group {
                    if isMapMode && showWeather {
                        // Maps sit below the weather overlay, not behind it.
                        VStack(alignment: .leading, spacing: 0) {
                            weatherBar
                            BalatonMapView(viewModel: mapModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .background(Color.black)
                    } else {
                        ZStack(alignment: .top) {
                            VideoStreamView(url: streamURL) {
                                Task { await streamManager.fetchStreamURL() }
                            }
                            .background(Color.black)
                            if showWeather {
                                weatherBar
                            }
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

    @ViewBuilder
    private var weatherBar: some View {
        if weather.visible {
            WeatherOverlayView(viewModel: weather,
                               isMapMode: isMapMode,
                               onToggleMapMode: { isMapMode.toggle() },
                               highlightTime: isMapMode ? mapModel.currentFrame?.validTime : nil,
                               onSelectTime: isMapMode ? { mapModel.select(closestTo: $0) } : nil,
                               onRefresh: isMapMode ? { Task { await mapModel.load() } } : nil)
                .padding(8)
        } else {
            HStack {
                Spacer()
                Button {
                    isMapMode.toggle()
                } label: {
                    Image(systemName: isMapMode ? "video" : "map")
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
