import SwiftUI

struct ContentView: View {
    @StateObject private var streamManager = StreamManager()
    @StateObject private var weather = WeatherViewModel()
    @StateObject private var mapModel = BalatonMapViewModel()
    @State private var isMapMode = false
    @State private var showSettings = false

    var body: some View {
        Group {
            if streamManager.isLoading {
                VStack {
                    ProgressView("Loading stream...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else if let streamURL = streamManager.streamURL {
                Group {
                    if isMapMode {
                        // Maps sit below the weather overlay, not behind it.
                        VStack(spacing: 0) {
                            weatherBar
                            BalatonMapView(viewModel: mapModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .background(Color.black)
                    } else {
                        ZStack(alignment: .top) {
                            VideoStreamView(url: streamURL)
                                .ignoresSafeArea()
                            weatherBar
                        }
                        .ignoresSafeArea()
                    }
                }
                .focusable()
                .onPlayPauseCommand { showSettings = true }
                // Remote/arrow keys: ↑ camera, ↓ maps, ←/→ step map frames.
                .onMoveCommand { direction in
                    switch direction {
                    case .up:
                        isMapMode = false
                    case .down:
                        isMapMode = true
                    case .left:
                        if isMapMode { mapModel.stepBack() }
                    case .right:
                        if isMapMode { mapModel.stepForward() }
                    @unknown default:
                        break
                    }
                }
                .onAppear { weather.start() }
                .onDisappear { weather.stop() }
                .sheet(isPresented: $showSettings) {
                    WindguruSettingsView()
                        .frame(maxWidth: 720)
                        .padding(40)
                }
            } else {
                VStack {
                    Text("Failed to load stream")
                        .foregroundColor(.white)
                    Button("Retry") {
                        Task {
                            await streamManager.fetchStreamURL()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }
        }
        .onAppear {
            Task {
                await streamManager.fetchStreamURL()
            }
        }
    }

    private var weatherBar: some View {
        WeatherOverlayView(viewModel: weather,
                           isMapMode: isMapMode,
                           highlightTime: isMapMode ? mapModel.currentFrame?.validTime : nil)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .allowsHitTesting(false)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
