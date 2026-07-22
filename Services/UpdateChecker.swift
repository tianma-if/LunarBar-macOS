import Foundation

struct UpdateCheckResult: Equatable {
    let latestVersion: String
    let releaseURL: URL
}

enum UpdateCheckerError: LocalizedError {
    case invalidResponse
    case invalidRelease

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "更新服务暂时不可用"
        case .invalidRelease:
            return "更新信息无效"
        }
    }
}

struct UpdateChecker {
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    func checkForUpdates() async throws -> UpdateCheckResult {
        guard let url = URL(string: "https://api.github.com/repos/tianma-if/LunarBar-macOS/releases/latest") else {
            throw UpdateCheckerError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LunarBar/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateCheckerError.invalidResponse
        }

        let release = try JSONDecoder().decode(Release.self, from: data)
        let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard !latestVersion.isEmpty else {
            throw UpdateCheckerError.invalidRelease
        }

        return UpdateCheckResult(latestVersion: latestVersion, releaseURL: release.htmlURL)
    }

    static func isNewer(_ version: String, than currentVersion: String) -> Bool {
        let latest = version.split(separator: ".").map { Int($0) ?? 0 }
        let current = currentVersion.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(latest.count, current.count)

        for index in 0..<count {
            let latestPart = index < latest.count ? latest[index] : 0
            let currentPart = index < current.count ? current[index] : 0
            if latestPart != currentPart {
                return latestPart > currentPart
            }
        }

        return false
    }
}
