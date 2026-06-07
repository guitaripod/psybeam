import Combine
import CoreLocation
import PsybeamKit

@MainActor
final class LocationLanguageService: NSObject {
    let detected = PassthroughSubject<(country: String, language: String), Never>()

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let table = CldrLanguageTable()

    override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        AppLogger.shared.info("location start status=\(manager.authorizationStatus.rawValue)", category: .location)
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    private func resolve(latitude: Double, longitude: Double) async {
        let placemarks = try? await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: latitude, longitude: longitude)
        )
        guard let country = placemarks?.first?.isoCountryCode else {
            AppLogger.shared.warn("location: geocode returned no country", category: .location)
            return
        }
        let languages = table.languages(forCountry: country)
        AppLogger.shared.info("location resolved country=\(country) langs=\(languages)", category: .location)
        guard let language = languages.first else { return }
        detected.send((country: country, language: language))
    }
}

extension LocationLanguageService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        Task { @MainActor in await self.resolve(latitude: latitude, longitude: longitude) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLogger.shared.warn("location failed: \(error.localizedDescription)", category: .location)
    }
}
