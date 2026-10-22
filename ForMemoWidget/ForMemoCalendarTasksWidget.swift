import WidgetKit
import SwiftUI

private func forMemoCalendarWidgetTimeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

private let calendarWidgetKind = "ForMemoCalendarTasksWidget"

private struct CalendarTasksEntry: TimelineEntry {
    let date: Date
    let snapshot: TaskWidgetSnapshot?
}

private struct CalendarTasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarTasksEntry {
        CalendarTasksEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarTasksEntry) -> Void) {
        let snapshot = TaskWidgetSnapshotStore.load()
        completion(CalendarTasksEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarTasksEntry>) -> Void) {
        let now = Date()
        let snapshot = TaskWidgetSnapshotStore.load()
        let calendar = Calendar.current
        var refreshDates: Set<Date> = [now]

        // Keep daily refreshes, but avoid creating a separate timeline entry
        // for every deadline. Frequent recurring tasks can otherwise make the
        // timeline unnecessarily large.
        for offset in 1...42 {
            if let day = calendar.date(
                byAdding: .day,
                value: offset,
                to: calendar.startOfDay(for: now)
            ) {
                refreshDates.insert(day)
            }
        }

        let sortedEntryDates = refreshDates.sorted()
        let entries = sortedEntryDates.map {
            CalendarTasksEntry(date: $0, snapshot: snapshot)
        }
        let refresh = calendar.date(byAdding: .hour, value: 24, to: now)
            ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

private struct CalendarTasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: CalendarTasksEntry

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2 // Monday first, as in ForMemo's calendar.
        return value
    }

    private var startOfToday: Date {
        calendar.startOfDay(for: entry.date)
    }

    private var taskDays: Set<Date> {
        guard let snapshot = entry.snapshot else { return [] }
        let result = Set(snapshot.tasks.compactMap { task -> Date? in
            guard !task.isCompleted, let deadline = task.deadline else {
                return nil
            }
            return calendar.startOfDay(for: deadline)
        })
        return result
    }

    private var monthStart: Date {
        let components = calendar.dateComponents([.year, .month], from: entry.date)
        return calendar.date(from: components) ?? calendar.startOfMonth(for: entry.date)
    }

    private var monthDates: [Date] {
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) ?? monthStart
        let result = (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
        return result
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.calendar = calendar
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: entry.date).capitalized
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...]) + Array(symbols[..<shift])
    }

    private var todayTasks: [TaskWidgetItem] {
        let result = tasks(on: startOfToday)
        return result
    }

    private var hasOverdueTasksInPreviousDays: Bool {
        guard let snapshot = entry.snapshot else { return false }
        let result = snapshot.tasks.contains { task in
            guard !task.isCompleted, let deadline = task.deadline else { return false }
            return deadline < startOfToday
        }
        return result
    }

    private var selectedTaskDay: Date? {
        let result: Date?
        if !todayTasks.isEmpty {
            result = startOfToday
        } else {
            result = taskDays.filter { $0 > startOfToday }.sorted().first
        }
        return result
    }

    private var selectedTasks: [TaskWidgetItem] {
        guard let selectedTaskDay else { return [] }
        let result = tasks(on: selectedTaskDay)
        return result
    }

    private func tasks(on day: Date) -> [TaskWidgetItem] {
        guard let snapshot = entry.snapshot,
              let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        let result = snapshot.tasks
            .filter { task in
                guard !task.isCompleted, let deadline = task.deadline else { return false }
                return deadline >= day && deadline < nextDay
            }
            .sorted { first, second in
                guard let a = first.deadline, let b = second.deadline else {
                    return first.deadline != nil
                }
                if a != b { return a < b }
                return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
            }
        return result
    }

    var body: some View {
        Group {
            if family == .systemSmall {
                smallCalendar
            } else {
                mediumCalendarAndTasks
            }
        }
        .padding(family == .systemSmall ? 6 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            colorScheme == .dark ? Color.black : Color.white
        }
    }

    private var smallCalendar: some View {
        let taskDays = self.taskDays
        return VStack(spacing: 3) {
            Text(monthTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            weekdayHeader(fontSize: 8)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                spacing: 0
            ) {
                ForEach(monthDates, id: \.self) { day in
                    dayCell(day, compact: true, taskDays: taskDays)
                        .frame(height: 16)
                }
            }
        }
    }

    private var mediumCalendarAndTasks: some View {
        let taskDays = self.taskDays
        return HStack(alignment: .top, spacing: 9) {
            VStack(spacing: 3) {
                Text(monthTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
//                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)

                weekdayHeader(fontSize: 7)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                    spacing: 1
                ) {
                    ForEach(monthDates, id: \.self) { day in
                        dayCell(day, compact: false, taskDays: taskDays)
                            .frame(height: 15)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(width: 1)

            taskPanel
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func weekdayHeader(fontSize: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol.uppercased())
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(index == 6 ? Color.red.opacity(0.9) : Color.primary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ day: Date, compact: Bool, taskDays: Set<Date>) -> some View {
        let isInMonth = calendar.isDate(day, equalTo: entry.date, toGranularity: .month)
        let isToday = calendar.isDate(day, inSameDayAs: startOfToday)
        let dayStart = calendar.startOfDay(for: day)
        let hasTasks = taskDays.contains(dayStart)
        let isOverdueDot: Bool = {
            guard hasTasks else { return false }
            if dayStart < startOfToday { return true }
            guard calendar.isDate(day, inSameDayAs: startOfToday) else { return false }

            let dueToday = tasks(on: startOfToday)
            return !dueToday.isEmpty && dueToday.allSatisfy { task in
                guard let deadline = task.deadline else { return false }
                return deadline < entry.date
            }
        }()
        let isSunday = calendar.component(.weekday, from: day) == 1

        return VStack(spacing: 0) {
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: compact ? 8 : 9, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(
                    isToday ? Color.accentColor :
                        (!isInMonth ? Color.secondary.opacity(0.35) :
                            (isSunday ? Color.red.opacity(0.9) : Color.primary))
                )
                .frame(width: compact ? 14 : 17, height: compact ? 12 : 13)
//                .background {
//                    if isToday {
//                        Circle()
//                            .stroke(Color.accentColor, lineWidth: 1.4)
//                            .frame(width: compact ? 18 : 15, height: compact ? 15 : 13)
//                    }
//                }

            Circle()
                .fill(
                    !hasTasks
                        ? Color.clear
                        : (isOverdueDot ? Color.red : Color.accentColor)
                )
                .frame(width: compact ? 2.5 : 3, height: compact ? 2.5 : 3)
                .padding(.top, 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (hasTasks ? ", tasks scheduled" : ""))
    }

    private var taskPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            if entry.snapshot == nil {
                Text("Open ForMemo to refresh")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if let selectedTaskDay {
                let selectedTasks = tasks(on: selectedTaskDay)
                let isToday = calendar.isDate(selectedTaskDay, inSameDayAs: startOfToday)
                HStack{
                    Text(isToday ? String(localized: "TODAY")  : selectedTaskDay.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
                    Text(selectedTaskDay.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                    Divider()
                        .overlay(
                            hasOverdueTasksInPreviousDays
                                ? Color.red
                                : Color.primary.opacity(0.14)
                        )
                
                ForEach(Array(selectedTasks.prefix(4))) { task in
                    HStack(alignment: .center, spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(priorityColor(task.priorityRaw))
                            .frame(width: 3)
                            .padding(.vertical, 1)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if let deadline = task.deadline {
                                Text(forMemoCalendarWidgetTimeString(deadline))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(deadline < entry.date ? Color.red : Color.primary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }

                            Text(task.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if selectedTasks.count > 4 {
                    Text("+\(selectedTasks.count - 4) altre")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No tasks")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("in the coming days")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func priorityColor(_ rawValue: Int) -> Color {
        switch rawValue {
        case 4: return .red
        default: return .clear
        }
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }
}

struct ForMemoCalendarTasksWidget: Widget {
    let kind: String = calendarWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarTasksProvider()) { entry in
            CalendarTasksWidgetView(entry: entry)
        }
        .configurationDisplayName("ForMemo — Calendar")
        .description("Monthly calendar highlighting days with tasks and a daily task list.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    ForMemoCalendarTasksWidget()
} timeline: {
    CalendarTasksEntry(date: .now, snapshot: TaskWidgetSnapshotStore.load())
}
