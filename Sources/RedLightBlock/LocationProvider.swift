import CoreLocation
import Foundation

/// One-shot CoreLocation fix. The result is stored by AppState in UserDefaults.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((Result<CLLocationCoordinate2D, Error>) -> Void)?
    private var waitingForAuth = false

    struct Denied: LocalizedError {
        var errorDescription: String? {
            "Location access denied. Enable it in System Settings > Privacy & Security > Location Services, or enter lat/lon."
        }
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestOnce(_ completion: @escaping (Result<CLLocationCoordinate2D, Error>) -> Void) {
        self.completion = completion
        switch manager.authorizationStatus {
        case .notDetermined:
            waitingForAuth = true
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(.failure(Denied()))
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard waitingForAuth else { return }
        switch manager.authorizationStatus {
        case .notDetermined: return
        case .denied, .restricted:
            waitingForAuth = false
            finish(.failure(Denied()))
        default:
            waitingForAuth = false
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        finish(.success(loc.coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        let c = completion
        completion = nil
        DispatchQueue.main.async { c?(result) }
    }
}
