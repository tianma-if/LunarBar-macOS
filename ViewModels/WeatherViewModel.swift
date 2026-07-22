import Foundation
import Combine
import CoreLocation

@MainActor
final class WeatherViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var weather: WeatherInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var settings: WeatherSettings

    private let service: WeatherServicing
    private let defaults: UserDefaults
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var hasRequestedLocation = false

    init(
        service: WeatherServicing = WeatherService(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
        self.settings = WeatherViewModel.loadSettings(from: defaults)

        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        requestCurrentLocation()
        refresh()
    }

    func refresh() {
        guard settings.isReady else {
            weather = nil
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                weather = try await service.fetchWeather(settings: settings)
                isLoading = false
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "天气请求失败"
                isLoading = false
            }
        }
    }

    func reloadSettings() {
        let currentLocation = (settings.latitude, settings.longitude)
        let loadedSettings = WeatherViewModel.loadSettings(from: defaults)
        settings = WeatherSettings(
            provider: loadedSettings.provider,
            apiKey: loadedSettings.apiKey,
            cityCode: loadedSettings.cityCode,
            cityName: loadedSettings.cityName,
            latitude: currentLocation.0,
            longitude: currentLocation.1
        )
        refresh()
    }

    func requestCurrentLocation() {
        hasRequestedLocation = false

        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways:
            startLocationUpdates()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard [.authorized, .authorizedAlways].contains(manager.authorizationStatus),
              !hasRequestedLocation else { return }
        startLocationUpdates()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !hasRequestedLocation, let location = locations.last else { return }
        hasRequestedLocation = true
        manager.stopUpdatingLocation()

        Task { @MainActor [weak self] in
            guard let self else { return }
            let cityName = await self.cityName(for: location) ?? self.settings.cityName
            self.settings = WeatherSettings(
                provider: self.settings.provider,
                apiKey: self.settings.apiKey,
                cityCode: self.settings.cityCode,
                cityName: cityName,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            self.refresh()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        manager.stopUpdatingLocation()
    }

    private func startLocationUpdates() {
        guard !hasRequestedLocation else { return }
        locationManager.requestLocation()
    }

    private func cityName(for location: CLLocation) async -> String? {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first?.locality
                ?? placemarks.first?.administrativeArea
                ?? placemarks.first?.name
        } catch {
            return nil
        }
    }

    private static func loadSettings(from defaults: UserDefaults) -> WeatherSettings {
        let storedCityCode = defaults.string(forKey: WeatherDefaults.cityCodeKey) ?? "101010100"
        let cityCode = storedCityCode == "110000" ? "101010100" : storedCityCode

        return WeatherSettings(
            provider: .lunarBar,
            apiKey: "",
            cityCode: cityCode,
            cityName: defaults.string(forKey: WeatherDefaults.cityNameKey) ?? "北京"
        )
    }
}

enum WeatherDefaults {
    static let providerKey = "weather.provider"
    static let apiKeyKey = "weather.apiKey"
    static let cityCodeKey = "weather.cityCode"
    static let cityNameKey = "weather.cityName"
}
