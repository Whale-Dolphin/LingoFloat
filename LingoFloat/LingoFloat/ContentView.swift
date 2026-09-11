import SwiftUI

/// Main-window entry point. `CinemaDashboard` owns the active caption UI;
/// the always-on-top CC HUD remains the primary surface while watching video.
struct ContentView: View {
    var body: some View {
        CinemaDashboard()
            .frame(minWidth: 580, idealWidth: 680, minHeight: 350, idealHeight: 420)
            .containerBackground(.background.secondary, for: .window)
    }
}

#Preview {
    ContentView()
}
