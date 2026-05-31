import SwiftUI

struct ContentView: View {
    @StateObject private var weather = WeatherViewModel()
    @State private var showWindguruSettings = false

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack(alignment: .topTrailing) {
                WebView(url: CameraConfig.playerPageURL)
                    .edgesIgnoringSafeArea(.all)

                if isLandscape {
                    WeatherOverlayView(viewModel: weather)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .allowsHitTesting(false)

                    Button {
                        showWindguruSettings = true
                    } label: {
                        Image(systemName: "key.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                }
            }
            .onChange(of: isLandscape) { _, landscape in
                if landscape {
                    weather.start()
                } else {
                    weather.stop()
                }
            }
            .onAppear {
                if isLandscape { weather.start() }
            }
            .onDisappear { weather.stop() }
            .sheet(isPresented: $showWindguruSettings) {
                NavigationStack {
                    WindguruSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showWindguruSettings = false }
                            }
                        }
                }
                .onDisappear {
                    Task { await weather.refresh() }
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
