import SwiftUI

/// Just the globe. One finger spins it, two fingers dragged vertically scrub
/// time (the Astronomy watch face does the same thing with the Digital Crown),
/// double tap springs back to your location.
struct ContentView: View {
    init() { DebugLog.reset(); DebugLog.write("app start") }
    @StateObject private var location = LocationProvider()

    var body: some View {
        ZStack {
            Color.black
            GlobeView(locationLatitude: location.latitude,
                      locationLongitude: location.longitude)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
    }
}
