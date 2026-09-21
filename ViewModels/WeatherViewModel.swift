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
    @Published private(set) var locationMessage = "正在获取位置…"

    private let service: WeatherServicing
    private let defaults: UserDefaults
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var hasRequestedLocation = false
    private var locationTimeoutTask: Task<Void, Never>?

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

        let useAutoLocation = defaults.object(forKey: WeatherDefaults.useAutoLocationKey) as? Bool ?? true
        if useAutoLocation {
            requestCurrentLocation()
        }

        if settings.hasCoordinates || (defaults.string(forKey: WeatherDefaults.cityNameKey) != nil && !settings.cityName.isEmpty) {
            refresh()
        }
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
        let loadedSettings = WeatherViewModel.loadSettings(from: defaults)
        settings = loadedSettings
        refresh()
    }

    func requestCurrentLocation() {
        hasRequestedLocation = false
        locationTimeoutTask?.cancel()

        locationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)
            guard let self, !self.hasRequestedLocation else { return }
            self.locationManager.stopUpdatingLocation()
            await self.fallbackToIPLocation()
        }

        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways:
            locationMessage = "正在获取当前位置…"
            startLocationUpdates()
        case .notDetermined:
            locationMessage = "请在系统提示中允许定位权限…"
            NSApp.activate(ignoringOtherApps: true)
            locationManager.requestAlwaysAuthorization()
            startLocationUpdates()
        case .denied, .restricted:
            locationMessage = "定位权限已关闭，正在尝试通过网络识别位置…"
            Task { @MainActor in
                await self.fallbackToIPLocation()
            }
        @unknown default:
            locationMessage = "无法获取系统定位，正在尝试通过网络识别位置…"
            Task { @MainActor in
                await self.fallbackToIPLocation()
            }
        }
    }

    func updateManualCity(_ cityName: String) async {
        let trimmed = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        locationMessage = "正在解析城市位置：\(trimmed)…"
        if let coords = await geocodeCity(name: trimmed) {
            saveLocation(latitude: coords.latitude, longitude: coords.longitude, cityName: trimmed)
            locationMessage = "已设定城市：\(trimmed)"
        } else {
            defaults.set(trimmed, forKey: WeatherDefaults.cityNameKey)
            settings = WeatherSettings(
                provider: settings.provider,
                apiKey: settings.apiKey,
                cityCode: settings.cityCode,
                cityName: trimmed,
                latitude: nil,
                longitude: nil
            )
            locationMessage = "已保存城市：\(trimmed)"
        }
        refresh()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorizationChange(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handleAuthorizationChange(status)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !hasRequestedLocation,
              let location = locations.last,
              location.horizontalAccuracy >= 0 else { return }

        hasRequestedLocation = true
        locationTimeoutTask?.cancel()
        manager.stopUpdatingLocation()

        Task { @MainActor [weak self] in
            guard let self else { return }
            let detectedCity = await self.cityName(for: location)
            let finalCityName: String
            if let detectedCity, !detectedCity.isEmpty {
                finalCityName = detectedCity
            } else if !self.settings.cityName.isEmpty && self.settings.cityName != "北京" {
                finalCityName = self.settings.cityName
            } else {
                finalCityName = "当前位置"
            }

            self.saveLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                cityName: finalCityName
            )
            self.locationMessage = "已获取当前位置：\(finalCityName)"
            self.refresh()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clErr = error as? CLError {
            if clErr.code == .locationUnknown {
                return
            }
            if clErr.code == .denied {
                manager.stopUpdatingLocation()
                locationTimeoutTask?.cancel()
                locationMessage = "定位权限已被拒绝，正在尝试通过网络识别位置…"
                Task { @MainActor in
                    await self.fallbackToIPLocation()
                }
                return
            }
        }
    }

    func openLocationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func startLocationUpdates() {
        guard !hasRequestedLocation else { return }
        locationManager.startUpdatingLocation()
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorized, .authorizedAlways:
            guard !hasRequestedLocation else { return }
            locationMessage = "正在获取当前位置…"
            startLocationUpdates()
        case .denied, .restricted:
            locationMessage = "定位权限已关闭，正在尝试通过网络识别位置…"
            Task { @MainActor in
                await self.fallbackToIPLocation()
            }
        case .notDetermined:
            locationMessage = "请在系统提示中允许定位权限…"
        @unknown default:
            locationMessage = "无法获取系统定位，正在尝试通过网络识别位置…"
            Task { @MainActor in
                await self.fallbackToIPLocation()
            }
        }
    }

    private func fallbackToIPLocation() async {
        guard !hasRequestedLocation else { return }
        locationMessage = "正在通过网络识别当前位置…"

        if let city = await IPLocationService.fetchCityName() {
            if let coords = await geocodeCity(name: city) {
                hasRequestedLocation = true
                saveLocation(latitude: coords.latitude, longitude: coords.longitude, cityName: city)
                locationMessage = "已通过网络识别位置：\(city)"
                refresh()
                return
            } else {
                hasRequestedLocation = true
                defaults.set(city, forKey: WeatherDefaults.cityNameKey)
                settings = WeatherSettings(
                    provider: settings.provider,
                    apiKey: settings.apiKey,
                    cityCode: settings.cityCode,
                    cityName: city,
                    latitude: settings.latitude,
                    longitude: settings.longitude
                )
                locationMessage = "已通过网络识别城市：\(city)"
                refresh()
                return
            }
        }

        if settings.hasCoordinates || defaults.string(forKey: WeatherDefaults.cityNameKey) != nil {
            locationMessage = "无法获取当前位置，已使用上次保存的位置"
            if weather == nil {
                refresh()
            }
        } else {
            locationMessage = "未能获取位置，请在设置中指定城市"
        }
    }

    private func geocodeCity(name: String) async -> CLLocationCoordinate2D? {
        do {
            let placemarks = try await geocoder.geocodeAddressString(name)
            return placemarks.first?.location?.coordinate
        } catch {
            return nil
        }
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

    private func saveLocation(latitude: Double, longitude: Double, cityName: String) {
        defaults.set(latitude, forKey: WeatherDefaults.latitudeKey)
        defaults.set(longitude, forKey: WeatherDefaults.longitudeKey)
        defaults.set(cityName, forKey: WeatherDefaults.cityNameKey)

        settings = WeatherSettings(
            provider: settings.provider,
            apiKey: settings.apiKey,
            cityCode: settings.cityCode,
            cityName: cityName,
            latitude: latitude,
            longitude: longitude
        )
    }

    private static func loadSettings(from defaults: UserDefaults) -> WeatherSettings {
        let storedCityCode = defaults.string(forKey: WeatherDefaults.cityCodeKey) ?? "101010100"
        let cityCode = storedCityCode == "110000" ? "101010100" : storedCityCode
        let storedCityName = defaults.string(forKey: WeatherDefaults.cityNameKey)

        let latitude = defaults.object(forKey: WeatherDefaults.latitudeKey) as? Double
        let longitude = defaults.object(forKey: WeatherDefaults.longitudeKey) as? Double

        let cityName: String
        if let storedCityName, !storedCityName.isEmpty {
            cityName = storedCityName
        } else if latitude != nil && longitude != nil {
            cityName = "当前位置"
        } else {
            cityName = "北京"
        }

        return WeatherSettings(
            provider: .lunarBar,
            apiKey: "",
            cityCode: cityCode,
            cityName: cityName,
            latitude: latitude,
            longitude: longitude
        )
    }
}

enum WeatherDefaults {
    static let providerKey = "weather.provider"
    static let apiKeyKey = "weather.apiKey"
    static let cityCodeKey = "weather.cityCode"
    static let cityNameKey = "weather.cityName"
    static let latitudeKey = "weather.latitude"
    static let longitudeKey = "weather.longitude"
    static let useAutoLocationKey = "weather.useAutoLocation"
}
