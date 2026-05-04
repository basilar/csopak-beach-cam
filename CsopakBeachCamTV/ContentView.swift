import SwiftUI

struct ContentView: View {
    @StateObject private var streamManager = StreamManager()
    @StateObject private var weather = WeatherViewModel()
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
                ZStack(alignment: .top) {
                    VideoStreamView(url: streamURL)
                        .ignoresSafeArea()
                    WeatherOverlayView(viewModel: weather)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
                .focusable()
                .onPlayPauseCommand { showSettings = true }
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
