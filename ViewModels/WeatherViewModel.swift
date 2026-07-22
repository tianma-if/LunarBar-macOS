import Foundation
import Combine
import CoreLocation
import AppKit

@MainActor
final class WeatherViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var weather: WeatherInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var settings: WeatherSettings
    @Published private(set) var locationMessage = "正在请求定位权限…"

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
            locationMessage = "正在获取当前位置…"
            startLocationUpdates()
        case .notDetermined:
            locationMessage = "请在系统提示中允许定位权限"
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            locationMessage = "定位权限已关闭，请在系统设置中开启"
            openLocationSettings()
        @unknown default:
            locationMessage = "无法获取定位权限"
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorizationChange(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handleAuthorizationChange(status)
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
            self.locationMessage = "已获取当前位置：\(cityName)"
            self.refresh()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        manager.stopUpdatingLocation()
        locationMessage = "暂时无法获取当前位置，将使用备用城市"
    }

    private func startLocationUpdates() {
        guard !hasRequestedLocation else { return }
        locationManager.requestLocation()
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorized, .authorizedAlways:
            guard !hasRequestedLocation else { return }
            locationMessage = "正在获取当前位置…"
            startLocationUpdates()
        case .denied, .restricted:
            locationMessage = "定位权限已关闭，请在系统设置中开启"
        case .notDetermined:
            locationMessage = "请在系统提示中允许定位权限"
        @unknown default:
            locationMessage = "无法获取定位权限"
        }
    }

    private func openLocationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
            return
        }
        NSWorkspace.shared.open(url)
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
