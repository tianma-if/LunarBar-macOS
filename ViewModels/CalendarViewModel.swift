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
    private let titleFormatter: DateFormatter

    init(
        selectedMonth: Date = Date(),
        calendar: Calendar = CalendarViewModel.makeGregorianCalendar()
    ) {
        self.selectedMonth = selectedMonth
        self.calendar = calendar

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月"
        self.titleFormatter = formatter

        rebuildMonth()
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

            return DayInfo(
                id: calendar.startOfDay(for: date),
                date: date,
                dayNumber: dayNumber,
                monthPosition: monthPosition,
                isToday: calendar.isDateInToday(date),
                lunarText: nil,
                festivalName: nil,
                solarTerm: nil,
                holidayBadge: nil
            )
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
