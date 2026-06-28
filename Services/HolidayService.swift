import Foundation

struct HolidayInfo: Decodable, Equatable {
    enum Kind: String, Decodable {
        case rest
        case work
    }

    let date: Date
    let name: String
    let kind: Kind

    var badge: DayInfo.HolidayBadge {
        switch kind {
        case .rest:
            return .rest
        case .work:
            return .work
        }
    }
}

actor HolidayService {
    private struct HolidayPayload: Decodable {
        let updatedAt: String
        let source: String
        let holidays: [HolidayRecord]
    }

    private struct HolidayRecord: Decodable {
        let date: String
        let name: String
        let kind: HolidayInfo.Kind
    }

    private let remoteURL: URL?
    private let cacheURL: URL
    private let bundle: Bundle
    private let decoder = JSONDecoder()
    private let isoDateFormatter: DateFormatter

    init(
        remoteURL: URL? = URL(string: "https://raw.githubusercontent.com/msh01/LunarBar-macOS/main/Resources/holidays.json"),
        bundle: Bundle = .main
    ) {
        self.remoteURL = remoteURL
        self.bundle = bundle

        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        self.cacheURL = supportDirectory
            .appendingPathComponent("LunarBar", isDirectory: true)
            .appendingPathComponent("holidays.json")

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        self.isoDateFormatter = formatter
    }

    func loadHolidays() async -> [Date: HolidayInfo] {
        if let remoteData = await fetchRemoteData(),
           let remoteHolidays = decodeHolidayMap(from: remoteData) {
            cache(remoteData)
            return remoteHolidays
        }

        if let cachedData = try? Data(contentsOf: cacheURL),
           let cachedHolidays = decodeHolidayMap(from: cachedData) {
            return cachedHolidays
        }

        guard let localURL = bundle.url(forResource: "holidays", withExtension: "json"),
              let localData = try? Data(contentsOf: localURL),
              let localHolidays = decodeHolidayMap(from: localData) else {
            return [:]
        }

        return localHolidays
    }

    private func fetchRemoteData() async -> Data? {
        guard let remoteURL else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            return data
        } catch {
            return nil
        }
    }

    private func decodeHolidayMap(from data: Data) -> [Date: HolidayInfo]? {
        guard let payload = try? decoder.decode(HolidayPayload.self, from: data) else {
            return nil
        }

        var holidayMap: [Date: HolidayInfo] = [:]

        for record in payload.holidays {
            guard let date = isoDateFormatter.date(from: record.date) else {
                continue
            }

            holidayMap[date] = HolidayInfo(
                date: date,
                name: record.name,
                kind: record.kind
            )
        }

        return holidayMap
    }

    private func cache(_ data: Data) {
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            return
        }
    }
}
