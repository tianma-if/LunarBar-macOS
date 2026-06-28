import Foundation
import Combine

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published private(set) var days: [DayInfo] = []
    @Published private(set) var monthTitle = ""
    @Published var selectedMonth: Date {
        didSet {
            rebuildMonth()
        }
    }

    let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    private var calendar: Calendar
    private var holidays: [Date: HolidayInfo] = [:]
    private let holidayService: HolidayService
    private let lunarFormatter: LunarCalendarFormatter
    private let titleFormatter: DateFormatter

    init(
        selectedMonth: Date = Date(),
        calendar: Calendar = CalendarViewModel.makeGregorianCalendar(),
        holidayService: HolidayService = HolidayService()
    ) {
        self.selectedMonth = selectedMonth
        self.calendar = calendar
        self.holidayService = holidayService

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月"
        self.titleFormatter = formatter
        self.lunarFormatter = LunarCalendarFormatter(timeZone: calendar.timeZone)

        rebuildMonth()
        loadHolidays()
    }

    func goToPreviousMonth() {
        shiftMonth(by: -1)
    }

    func goToNextMonth() {
        shiftMonth(by: 1)
    }

    func goToToday() {
        selectedMonth = Date()
    }

    private func shiftMonth(by offset: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: selectedMonth) else {
            return
        }
        selectedMonth = newMonth
    }

    private func rebuildMonth() {
        guard let monthStart = startOfMonth(for: selectedMonth) else {
            days = []
            monthTitle = ""
            return
        }

        monthTitle = titleFormatter.string(from: monthStart)
        days = makeMonthGrid(startingAt: monthStart)
    }

    private func makeMonthGrid(startingAt monthStart: Date) -> [DayInfo] {
        let leadingDays = normalizedWeekdayOffset(for: monthStart)

        guard let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) else {
            return []
        }

        return (0..<42).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: gridStart) else {
                return nil
            }

            let dayNumber = calendar.component(.day, from: date)
            let monthPosition = monthPosition(for: date, relativeTo: monthStart)
            let holiday = holidays[calendar.startOfDay(for: date)]
            let officialFestivalName = holiday?.kind == .rest ? holiday?.name : nil

            return DayInfo(
                id: calendar.startOfDay(for: date),
                date: date,
                dayNumber: dayNumber,
                monthPosition: monthPosition,
                isToday: calendar.isDateInToday(date),
                lunarText: lunarFormatter.lunarText(for: date),
                festivalName: officialFestivalName ?? lunarFormatter.festivalName(for: date),
                solarTerm: lunarFormatter.solarTerm(for: date),
                holidayBadge: holiday?.badge
            )
        }
    }

    private func loadHolidays() {
        Task {
            let loadedHolidays = await holidayService.loadHolidays()
            holidays = loadedHolidays
            rebuildMonth()
        }
    }

    private func startOfMonth(for date: Date) -> Date? {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components)
    }

    private func normalizedWeekdayOffset(for date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func monthPosition(for date: Date, relativeTo monthStart: Date) -> DayInfo.MonthPosition {
        if calendar.isDate(date, equalTo: monthStart, toGranularity: .month) {
            return .current
        }

        return date < monthStart ? .previous : .next
    }

    nonisolated static func makeGregorianCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }
}

private struct LunarCalendarFormatter {
    private let chineseCalendar: Calendar
    private let gregorianCalendar: Calendar

    private let monthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]

    private let lunarFestivals: [LunarDay: String] = [
        LunarDay(month: 1, day: 1): "春节",
        LunarDay(month: 1, day: 15): "元宵",
        LunarDay(month: 2, day: 2): "龙抬头",
        LunarDay(month: 5, day: 5): "端午",
        LunarDay(month: 7, day: 7): "七夕",
        LunarDay(month: 7, day: 15): "中元",
        LunarDay(month: 8, day: 15): "中秋",
        LunarDay(month: 9, day: 9): "重阳",
        LunarDay(month: 12, day: 8): "腊八",
        LunarDay(month: 12, day: 23): "小年"
    ]

    private let solarFestivals: [SolarDay: String] = [
        SolarDay(month: 1, day: 1): "元旦",
        SolarDay(month: 2, day: 14): "情人节",
        SolarDay(month: 3, day: 8): "妇女节",
        SolarDay(month: 5, day: 1): "劳动节",
        SolarDay(month: 6, day: 1): "儿童节",
        SolarDay(month: 10, day: 1): "国庆"
    ]

    private let solarTerms = SolarTermCalculator()

    init(timeZone: TimeZone) {
        var chineseCalendar = Calendar(identifier: .chinese)
        chineseCalendar.locale = Locale(identifier: "zh_CN")
        chineseCalendar.timeZone = timeZone
        self.chineseCalendar = chineseCalendar

        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.locale = Locale(identifier: "zh_CN")
        gregorianCalendar.timeZone = timeZone
        self.gregorianCalendar = gregorianCalendar
    }

    func lunarText(for date: Date) -> String {
        let components = chineseCalendar.dateComponents([.month, .day, .isLeapMonth], from: date)

        guard let month = components.month, let day = components.day else {
            return ""
        }

        if day == 1 {
            return monthText(month: month, isLeapMonth: components.isLeapMonth == true)
        }

        return dayText(day)
    }

    func festivalName(for date: Date) -> String? {
        let solarComponents = gregorianCalendar.dateComponents([.month, .day], from: date)
        if let month = solarComponents.month,
           let day = solarComponents.day,
           let festival = solarFestivals[SolarDay(month: month, day: day)] {
            return festival
        }

        let lunarComponents = chineseCalendar.dateComponents([.month, .day], from: date)
        if let month = lunarComponents.month,
           let day = lunarComponents.day,
           let festival = lunarFestivals[LunarDay(month: month, day: day)] {
            return festival
        }

        if isLunarNewYearsEve(date) {
            return "除夕"
        }

        return nil
    }

    func solarTerm(for date: Date) -> String? {
        solarTerms.term(on: date, calendar: gregorianCalendar)
    }

    private func isLunarNewYearsEve(_ date: Date) -> Bool {
        guard let tomorrow = gregorianCalendar.date(byAdding: .day, value: 1, to: date) else {
            return false
        }

        let components = chineseCalendar.dateComponents([.month, .day], from: tomorrow)
        return components.month == 1 && components.day == 1
    }

    private func monthText(month: Int, isLeapMonth: Bool) -> String {
        guard monthNames.indices.contains(month - 1) else {
            return ""
        }

        return isLeapMonth ? "闰\(monthNames[month - 1])" : monthNames[month - 1]
    }

    private func dayText(_ day: Int) -> String {
        let numerals = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

        switch day {
        case 1...9:
            return "初\(numerals[day])"
        case 10:
            return "初十"
        case 11...19:
            return "十\(numerals[day - 10])"
        case 20:
            return "二十"
        case 21...29:
            return "廿\(numerals[day - 20])"
        case 30:
            return "三十"
        default:
            return ""
        }
    }
}

private struct LunarDay: Hashable {
    let month: Int
    let day: Int
}

private struct SolarDay: Hashable {
    let month: Int
    let day: Int
}

private struct SolarTermCalculator {
    private let termsByMonth: [[SolarTerm]] = [
        [SolarTerm(name: "小寒", dayCoefficient: 5.4055), SolarTerm(name: "大寒", dayCoefficient: 20.12)],
        [SolarTerm(name: "立春", dayCoefficient: 3.87), SolarTerm(name: "雨水", dayCoefficient: 18.74)],
        [SolarTerm(name: "惊蛰", dayCoefficient: 5.63), SolarTerm(name: "春分", dayCoefficient: 20.646)],
        [SolarTerm(name: "清明", dayCoefficient: 4.81), SolarTerm(name: "谷雨", dayCoefficient: 20.1)],
        [SolarTerm(name: "立夏", dayCoefficient: 5.52), SolarTerm(name: "小满", dayCoefficient: 21.04)],
        [SolarTerm(name: "芒种", dayCoefficient: 5.678), SolarTerm(name: "夏至", dayCoefficient: 21.37)],
        [SolarTerm(name: "小暑", dayCoefficient: 7.108), SolarTerm(name: "大暑", dayCoefficient: 22.83)],
        [SolarTerm(name: "立秋", dayCoefficient: 7.5), SolarTerm(name: "处暑", dayCoefficient: 23.13)],
        [SolarTerm(name: "白露", dayCoefficient: 7.646), SolarTerm(name: "秋分", dayCoefficient: 23.042)],
        [SolarTerm(name: "寒露", dayCoefficient: 8.318), SolarTerm(name: "霜降", dayCoefficient: 23.438)],
        [SolarTerm(name: "立冬", dayCoefficient: 7.438), SolarTerm(name: "小雪", dayCoefficient: 22.36)],
        [SolarTerm(name: "大雪", dayCoefficient: 7.18), SolarTerm(name: "冬至", dayCoefficient: 21.94)]
    ]

    func term(on date: Date, calendar: Calendar) -> String? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              (2000...2099).contains(year),
              termsByMonth.indices.contains(month - 1) else {
            return nil
        }

        let yearOffset = year - 2000
        let terms = termsByMonth[month - 1]

        return terms.first { term in
            day == calculatedDay(for: term, yearOffset: yearOffset)
        }?.name
    }

    private func calculatedDay(for term: SolarTerm, yearOffset: Int) -> Int {
        let drift = floor(Double(yearOffset) * 0.2422 + term.dayCoefficient)
        let leapAdjustment = floor(Double(yearOffset - 1) / 4.0)
        return Int(drift - leapAdjustment)
    }
}

private struct SolarTerm {
    let name: String
    let dayCoefficient: Double
}
