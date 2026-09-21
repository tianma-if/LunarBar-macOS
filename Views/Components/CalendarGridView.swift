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
        ZStack {
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
            .help("回到今天")

            HStack(spacing: 8) {
                Button {
                    viewModel.goToPreviousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上个月")

                Spacer()

                if !viewModel.isTodaySelected {
                    Button {
                        viewModel.goToToday()
                    } label: {
                        Text("今天")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("回到今天")
                    .help("回到今天")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                Button {
                    viewModel.goToNextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下个月")
            }
        }
        .frame(height: 28)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isTodaySelected)
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
                Button {
                    viewModel.selectDate(day.date)
                } label: {
                    DayCellView(day: day)
                }
                .buttonStyle(.plain)
                .help(viewModel.tooltipText(for: day))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: viewModel.selectedDate)
    }
}

private struct DayCellView: View {
    let day: DayInfo
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 2) {
                Text("\(day.dayNumber)")
                    .font(.system(size: 15, weight: (day.isToday || day.isSelected) ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(dayNumberColor)
                    .monospacedDigit()

                Text(day.secondaryText)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .frame(height: 12)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(cellBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(cellBorder)

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
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .opacity(day.monthPosition == .current ? 1 : 0.38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var dayNumberColor: Color {
        if day.isToday && day.isSelected {
            return .white
        }
        if day.isToday {
            return .accentColor
        }
        return day.monthPosition == .current ? .primary : .secondary
    }

    private var secondaryTextColor: Color {
        if day.isToday && day.isSelected {
            return .white.opacity(0.9)
        }

        if day.festivalName != nil {
            return .red
        }

        if day.solarTerm != nil {
            return .accentColor
        }

        if day.isToday {
            return .accentColor.opacity(0.85)
        }

        return .secondary
    }

    @ViewBuilder
    private var cellBackground: some View {
        if day.isToday && day.isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor)
        } else if day.isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.18))
        } else if day.isToday {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        } else if isHovered {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.0001))
        }
    }

    @ViewBuilder
    private var cellBorder: some View {
        if day.isToday && day.isSelected {
            EmptyView()
        } else if day.isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
        } else if day.isToday {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
        } else {
            EmptyView()
        }
    }

    private var accessibilityLabel: String {
        var label = ""
        if day.isToday {
            label += "今天，"
        }
        if day.isSelected {
            label += "已选定，"
        }
        label += "\(day.dayNumber)日"
        if let badge = day.holidayBadge {
            label += "，\(badge == .rest ? "放假" : "调休补班")"
        }
        if !day.secondaryText.isEmpty {
            label += "，\(day.secondaryText)"
        }
        return label
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
