import SwiftUI

struct CalendarGridView: View {
    @ObservedObject var viewModel: CalendarViewModel

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 34, maximum: 44), spacing: 6),
        count: 7
    )

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayHeader
            dayGrid
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上个月")

            Spacer()

            Button {
                viewModel.goToToday()
            } label: {
                Text(viewModel.monthTitle)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("回到今天")

            Spacer()

            Button {
                viewModel.goToNextMonth()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下个月")
        }
        .frame(height: 28)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(viewModel.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(viewModel.days) { day in
                DayCellView(day: day)
            }
        }
    }
}

private struct DayCellView: View {
    let day: DayInfo

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 2) {
                Text("\(day.dayNumber)")
                    .font(.system(size: 15, weight: day.isToday ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(dayNumberColor)
                    .monospacedDigit()

                Text(day.secondaryText)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: 12)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(cellBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let badge = day.holidayBadge {
                Text(badge.rawValue)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .background(badgeColor(for: badge))
                    .clipShape(Circle())
                    .offset(x: 4, y: -4)
            }
        }
        .opacity(day.monthPosition == .current ? 1 : 0.38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var dayNumberColor: Color {
        if day.isToday {
            return .white
        }

        return day.monthPosition == .current ? .primary : .secondary
    }

    @ViewBuilder
    private var cellBackground: some View {
        if day.isToday {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.0001))
        }
    }

    private var accessibilityLabel: String {
        if day.isToday {
            return "今天，\(day.dayNumber)日"
        }

        return "\(day.dayNumber)日"
    }

    private func badgeColor(for badge: DayInfo.HolidayBadge) -> Color {
        switch badge {
        case .work:
            return .secondary
        case .rest:
            return .red
        }
    }
}

struct CalendarGridView_Previews: PreviewProvider {
    static var previews: some View {
        CalendarGridView(viewModel: CalendarViewModel())
            .padding()
            .frame(width: 360)
    }
}
