import Foundation
import CoreLocation

/// Feeds the beacon. The shipping wallpaper asks for location with the string
/// "Your location is used to display your position on the globe."
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published var latitude: Float = 51.5074      // fallback: London
    @Published var longitude: Float = -0.1278
    @Published var hasFix = false

    private let manager = CLLocationManager()

    var statusLabel: String {
        hasFix ? String(format: "%.1f°, %.1f°", latitude, longitude) : "Recentre"
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.startUpdatingLocation()
        default: break
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        latitude = Float(c.latitude)
        longitude = Float(c.longitude)
        hasFix = true
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        // keep the fallback coordinate; the globe still works without a fix
    }
}
