import Foundation

enum WeatherProvider: String, CaseIterable, Identifiable {
    case lunarBar
    case amap
    case qweather

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lunarBar:
            return "LunarBar Weather"
        case .amap:
            return "高德天气"
        case .qweather:
            return "QWeather"
        }
    }
}

struct WeatherSettings: Equatable {
    let provider: WeatherProvider
    let apiKey: String
    let cityCode: String
    let cityName: String

    var isReady: Bool {
        !cityCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

protocol WeatherServicing {
    func fetchWeather(settings: WeatherSettings) async throws -> WeatherInfo
}

enum WeatherServiceError: LocalizedError {
    case missingSettings
    case badURL
    case invalidResponse
    case providerMessage(String)

    var errorDescription: String? {
        switch self {
        case .missingSettings:
            return "未配置"
        case .badURL:
            return "地址无效"
        case .invalidResponse:
            return "数据无效"
        case .providerMessage(let message):
            return message
        }
    }
}

struct WeatherService: WeatherServicing {
    private let workerService = WorkerWeatherService()
    private let amapService = AMapWeatherService()
    private let qweatherService = QWeatherService()

    func fetchWeather(settings: WeatherSettings) async throws -> WeatherInfo {
        guard settings.isReady else {
            throw WeatherServiceError.missingSettings
        }

        switch settings.provider {
        case .lunarBar:
            return try await workerService.fetchWeather(settings: settings)
        case .amap:
            return try await amapService.fetchWeather(settings: settings)
        case .qweather:
            return try await qweatherService.fetchWeather(settings: settings)
        }
    }
}

private struct WorkerWeatherService: WeatherServicing {
    private struct Response: Decodable {
        let cityName: String
        let condition: String
        let temperature: String
        let symbolName: String
        let reportTime: String
        let providerName: String
    }

    func fetchWeather(settings: WeatherSettings) async throws -> WeatherInfo {
        var components = URLComponents(string: "https://lunarbar-weather.yingwaizhiying8671.workers.dev/weather")
        components?.queryItems = [
            URLQueryItem(name: "location", value: settings.cityCode),
            URLQueryItem(name: "cityName", value: settings.cityName)
        ]

        guard let url = components?.url else {
            throw WeatherServiceError.badURL
        }

        let response: Response = try await fetchJSON(from: url)
        return WeatherInfo(
            cityName: response.cityName,
            condition: response.condition,
            temperature: response.temperature,
            symbolName: response.symbolName,
            reportTime: response.reportTime,
            providerName: response.providerName
        )
    }
}

private struct AMapWeatherService: WeatherServicing {
    private struct Response: Decodable {
        let status: String
        let info: String?
        let lives: [LiveWeather]
    }

    private struct LiveWeather: Decodable {
        let city: String
        let weather: String
        let temperature: String
        let reporttime: String
    }

    func fetchWeather(settings: WeatherSettings) async throws -> WeatherInfo {
        var components = URLComponents(string: "https://restapi.amap.com/v3/weather/weatherInfo")
        components?.queryItems = [
            URLQueryItem(name: "key", value: settings.apiKey),
            URLQueryItem(name: "city", value: settings.cityCode),
            URLQueryItem(name: "extensions", value: "base"),
            URLQueryItem(name: "output", value: "JSON")
        ]

        guard let url = components?.url else {
            throw WeatherServiceError.badURL
        }

        let response: Response = try await fetchJSON(from: url)

        guard response.status == "1", let live = response.lives.first else {
            throw WeatherServiceError.providerMessage(response.info ?? "高德天气请求失败")
        }

        return WeatherInfo(
            cityName: live.city,
            condition: live.weather,
            temperature: live.temperature,
            symbolName: WeatherSymbolMapper.symbolName(for: live.weather),
            reportTime: live.reporttime,
            providerName: WeatherProvider.amap.displayName
        )
    }
}

private struct QWeatherService: WeatherServicing {
    private struct Response: Decodable {
        let code: String
        let updateTime: String?
        let now: NowWeather?
    }

    private struct NowWeather: Decodable {
        let temp: String
        let text: String
        let obsTime: String
    }

    func fetchWeather(settings: WeatherSettings) async throws -> WeatherInfo {
        var components = URLComponents(string: "https://devapi.qweather.com/v7/weather/now")
        components?.queryItems = [
            URLQueryItem(name: "location", value: settings.cityCode),
            URLQueryItem(name: "key", value: settings.apiKey),
            URLQueryItem(name: "lang", value: "zh")
        ]

        guard let url = components?.url else {
            throw WeatherServiceError.badURL
        }

        let response: Response = try await fetchJSON(from: url)

        guard response.code == "200", let now = response.now else {
            throw WeatherServiceError.providerMessage("QWeather 请求失败：\(response.code)")
        }

        return WeatherInfo(
            cityName: settings.cityName.isEmpty ? settings.cityCode : settings.cityName,
            condition: now.text,
            temperature: now.temp,
            symbolName: WeatherSymbolMapper.symbolName(for: now.text),
            reportTime: response.updateTime ?? now.obsTime,
            providerName: WeatherProvider.qweather.displayName
        )
    }
}

private func fetchJSON<T: Decodable>(from url: URL) async throws -> T {
    let (data, response) = try await URLSession.shared.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse,
          (200..<300).contains(httpResponse.statusCode) else {
        throw WeatherServiceError.invalidResponse
    }

    return try JSONDecoder().decode(T.self, from: data)
}

private enum WeatherSymbolMapper {
    static func symbolName(for condition: String) -> String {
        if condition.contains("雷") {
            return "cloud.bolt.rain.fill"
        }

        if condition.contains("雨") {
            return "cloud.rain.fill"
        }

        if condition.contains("雪") {
            return "snowflake"
        }

        if condition.contains("雾") || condition.contains("霾") {
            return "cloud.fog.fill"
        }

        if condition.contains("阴") {
            return "smoke.fill"
        }

        if condition.contains("云") {
            return "cloud.sun.fill"
        }

        return "sun.max.fill"
    }
}
