import Foundation
import Combine

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published private(set) var weather: WeatherInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var settings: WeatherSettings

    private let service: WeatherServicing
    private let defaults: UserDefaults

    init(
        service: WeatherServicing = WeatherService(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
        self.settings = WeatherViewModel.loadSettings(from: defaults)

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
        settings = WeatherViewModel.loadSettings(from: defaults)
        refresh()
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
