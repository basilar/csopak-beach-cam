import SwiftUI

struct ContentView: View {
    var body: some View {
        WebView(url: CameraConfig.playerPageURL)
            .edgesIgnoringSafeArea(.all)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
