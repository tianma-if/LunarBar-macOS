import Foundation

struct DayInfo: Identifiable, Equatable {
    enum MonthPosition: Equatable {
        case previous
        case current
        case next
    }

    enum HolidayBadge: String, Equatable {
        case work = "班"
        case rest = "休"
    }

    let id: Date
    let date: Date
    let dayNumber: Int
    let monthPosition: MonthPosition
    let isToday: Bool
    let lunarText: String?
    let festivalName: String?
    let solarTerm: String?
    let holidayBadge: HolidayBadge?

    var secondaryText: String {
        festivalName ?? solarTerm ?? lunarText ?? ""
    }
}
