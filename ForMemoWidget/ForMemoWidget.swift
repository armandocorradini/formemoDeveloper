import WidgetKit
import SwiftUI
import UIKit

private func forMemoWidgetTimeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

struct ForMemoWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TaskWidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ForMemoWidgetEntry {
        ForMemoWidgetEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (ForMemoWidgetEntry) -> Void
    ) {
        completion(ForMemoWidgetEntry(date: .now, snapshot: TaskWidgetSnapshotStore.load()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<ForMemoWidgetEntry>) -> Void
    ) {
        let now = Date()
        let snapshot = TaskWidgetSnapshotStore.load()
        let calendar = Calendar.current
        var entryDates: Set<Date> = [now]

        // Keep the timeline bounded even when many recurring tasks have deadlines.
        // Daily entries update day grouping and overdue styling without creating
        // thousands of entries for frequent recurrences.
        for offset in 1...7 {
            if let day = calendar.date(
                byAdding: .day,
                value: offset,
                to: calendar.startOfDay(for: now)
            ) {
                entryDates.insert(day)
            }
        }

        let entries = entryDates.sorted().map { ForMemoWidgetEntry(date: $0, snapshot: snapshot) }
        // Refresh at the next local day boundary so date-relative labels
        // (Today/Tomorrow) do not remain stale after midnight.
        let nextRefresh = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }
}

struct ForMemoWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    let entry: Provider.Entry

    private var tasks: [TaskWidgetItem] {
        guard let snapshot = entry.snapshot else { return [] }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: entry.date)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }
        return snapshot.tasks
            .filter { task in
                guard let deadline = task.deadline, !task.isCompleted else { return false }
                return deadline >= dayStart && deadline < nextDay
            }
            .sorted { first, second in
                guard let firstDate = first.deadline, let secondDate = second.deadline else {
                    return first.deadline != nil
                }
                if firstDate != secondDate { return firstDate < secondDate }
                return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
            }
    }

    private var overdueCount: Int {
        guard let snapshot = entry.snapshot else { return 0 }
        let dayStart = Calendar.current.startOfDay(for: entry.date)
        return snapshot.tasks.reduce(into: 0) { count, task in
            guard let deadline = task.deadline,
                  !task.isCompleted,
                  deadline < dayStart else { return }
            count += 1
        }
    }

    private var visibleTaskLimit: Int {
        switch family {
        case .systemSmall:
            return 3
        case .systemMedium:
            return 3
        case .systemLarge:
            return 8
        default:
            return 2
        }
    }

    private var compactLayout: Bool {
        family == .systemSmall || family == .systemMedium
    }

    private var weatherAvailable: Bool {
        guard let snapshot = entry.snapshot else { return false }
        return snapshot.weatherSymbolName != nil
            && snapshot.weatherMinTemperature != nil
            && snapshot.weatherMaxTemperature != nil
    }

    var body: some View {
        widgetContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(family == .systemSmall ? 9 : (family == .systemMedium ? 12 : 16))
            .containerBackground(for: .widget) {
                Color(uiColor: UIColor { traits in
                    traits.userInterfaceStyle == .dark ? .black : .white
                })
            }
    }

    private var widgetContent: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 3 : (family == .systemMedium ? 4 : 7)) {
            header
            separator

            if entry.snapshot == nil {
                Text(String(localized: "Open ForMemo to refresh your tasks."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if tasks.isEmpty {
                    Text(overdueCount > 0 ? String(localized: "No tasks for today") : String(localized: "Nothing scheduled"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : (family == .systemMedium ? 5 : 9)) {
                        ForEach(Array(tasks.prefix(visibleTaskLimit))) { task in
                            taskRow(task)
                        }
                    }
                    if tasks.count > visibleTaskLimit {
                        Text(String(localized: "+\(tasks.count - visibleTaskLimit) more"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            if family == .systemMedium || family == .systemSmall {
                HStack(alignment: .firstTextBaseline, spacing: family == .systemSmall ? 5 : 7) {
                    Text(formattedDayNumber)
                        .font(.system(
                            size: family == .systemSmall ? 22 : 32,
                            weight: .bold,
                            design: .rounded
                        ))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(formattedWeekday)
                        .font(.system(
                            size: family == .systemSmall ? 9 : 11,
                            weight: .semibold,
                            design: .rounded
                        ))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(formattedDayNumber)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(formattedWeekday)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 2)

            if weatherAvailable,
               let symbol = entry.snapshot?.weatherSymbolName,
               let minimum = entry.snapshot?.weatherMinTemperature,
               let maximum = entry.snapshot?.weatherMaxTemperature {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: family == .systemSmall ? 17 : 20))

                    HStack(spacing: 3) {
                        Text("\(minimum)°")
                            .foregroundStyle(.secondary)
                        Text("/")
                            .foregroundStyle(.tertiary)
                        Text("\(maximum)°")
                            .foregroundStyle(.primary)
                    }
                    .font(.system(size: family == .systemSmall ? 9 : 10, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formattedWeekday: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = family == .systemSmall ? "EEE" : "EEEE"
        return formatter.string(from: entry.date).uppercased()
    }

    private var formattedDayNumber: String {
        String(Calendar.current.component(.day, from: entry.date))
    }

    private var separator: some View {
        Rectangle()
            .fill(overdueCount > 0 ? Color.red.opacity(0.85) : Color.primary.opacity(0.16))
            .frame(height: 1)
            .padding(.vertical, family == .systemLarge ? 1 : 0)
    }

    private func taskRow(_ task: TaskWidgetItem) -> some View {
        HStack(alignment: .top, spacing: family == .systemSmall ? 5 : 6) {
            Image(systemName: "circle")
                .font(.system(size: family == .systemSmall ? 6 : 13, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: family == .systemSmall ? 0 : 1) {
                if let deadline = task.deadline {
                    HStack(alignment: .firstTextBaseline, spacing: family == .systemSmall ? 5 : 6) {
                        Text(forMemoWidgetTimeString(deadline))
                            .font(.system(size: family == .systemSmall ? 10 : 13, weight: .medium))
                            .foregroundStyle(deadline < entry.date ? .red : .secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Text(task.title)
                            .font(.system(size: family == .systemSmall ? 10 : 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text(task.title)
                        .font(.system(size: family == .systemSmall ? 10 : 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

}

struct ForMemoWidget: Widget {
    let kind: String = "ForMemoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ForMemoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today’s Tasks")
        .description("Shows today’s tasks and overdue tasks from previous days.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    ForMemoWidget()
} timeline: {
    ForMemoWidgetEntry(date: .now, snapshot: nil)
}


// MARK: - Upcoming Activities Widget

struct ForMemoAgendaEntry: TimelineEntry {
    let date: Date
    let snapshot: TaskWidgetSnapshot?
}

struct ForMemoAgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> ForMemoAgendaEntry {
        ForMemoAgendaEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ForMemoAgendaEntry) -> Void) {
        completion(ForMemoAgendaEntry(date: .now, snapshot: TaskWidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ForMemoAgendaEntry>) -> Void) {
        let now = Date()
        let snapshot = TaskWidgetSnapshotStore.load()
        let calendar = Calendar.current
        var dates: Set<Date> = [now]

        for offset in 1...7 {
            if let day = calendar.date(
                byAdding: .day,
                value: offset,
                to: calendar.startOfDay(for: now)
            ) {
                dates.insert(day)
            }
        }

        let entries = dates.sorted().map { ForMemoAgendaEntry(date: $0, snapshot: snapshot) }
        // Refresh at the next local day boundary so date-relative labels
        // (Today/Tomorrow) do not remain stale after midnight.
        let refresh = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

private struct ForMemoUpcomingDay: Identifiable {
    let date: Date
    let tasks: [TaskWidgetItem]
    var id: Date { date }
}

private struct ForMemoVisibleUpcomingDay: Identifiable {
    let day: ForMemoUpcomingDay
    let taskLimit: Int
    var id: Date { day.date }
}

struct ForMemoAgendaEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ForMemoAgendaEntry

    private var calendar: Calendar { Calendar.current }

    private var days: [ForMemoUpcomingDay] {
        guard let snapshot = entry.snapshot else { return [] }
        let today = calendar.startOfDay(for: entry.date)
        let dayLimit = family == .systemLarge ? 7 : 4

        return (0..<dayLimit).compactMap { offset in
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: today),
                let nextDay = calendar.date(byAdding: .day, value: 1, to: day)
            else { return nil }

            let tasks = snapshot.tasks
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

            return ForMemoUpcomingDay(date: day, tasks: tasks)
        }
    }

    private var visibleDays: [ForMemoUpcomingDay] {
        let nonEmptyDays = days.filter { !$0.tasks.isEmpty }
        return Array(nonEmptyDays.prefix(family == .systemLarge ? 7 : 3))
    }

    // The Small widget spends its limited vertical space on today's tasks first.
    // Each day heading uses one row; remaining rows are filled with tasks in date order.
    private var smallVisibleDays: [ForMemoVisibleUpcomingDay] {
        var remainingRows = 6
        var result: [ForMemoVisibleUpcomingDay] = []

        for day in days where !day.tasks.isEmpty {
            guard remainingRows >= 2 else { break }
            remainingRows -= 1 // Day heading
            let taskLimit = min(day.tasks.count, remainingRows)
            guard taskLimit > 0 else { break }
            result.append(ForMemoVisibleUpcomingDay(day: day, taskLimit: taskLimit))
            remainingRows -= taskLimit
        }

        return result
    }

    private var hasOverdueTasksFromPreviousDays: Bool {
        guard let snapshot = entry.snapshot else { return false }
        let todayStart = calendar.startOfDay(for: entry.date)
        return snapshot.tasks.contains { task in
            guard !task.isCompleted, let deadline = task.deadline else { return false }
            return deadline < todayStart
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Upcoming Activities"))
                .font(.system(size: family == .systemSmall ? 15 : (family == .systemLarge ? 17 : 15), weight: .bold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .padding(.bottom, family == .systemSmall ? 7 : 8)

            Rectangle()
                .fill(hasOverdueTasksFromPreviousDays ? Color.red.opacity(0.85) : Color.primary.opacity(0.14))
                .frame(height: 1)
                .padding(.bottom, family == .systemSmall ? 6 : 7)

            if entry.snapshot == nil {
                Text(String(localized: "Open ForMemo to refresh activities."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if ((family == .systemSmall || family == .systemMedium) ? smallVisibleDays.isEmpty : visibleDays.isEmpty) {
                Text(String(localized: "No activities due in the coming days"))
                    .font(family == .systemSmall ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: family == .systemLarge ? 6 : 3) {
                    if family == .systemSmall || family == .systemMedium {
                        ForEach(smallVisibleDays) { section in
                            daySection(
                                section.day,
                                isLast: section.id == smallVisibleDays.last?.id,
                                taskLimitOverride: section.taskLimit
                            )
                        }
                    } else {
                        ForEach(Array(visibleDays.enumerated()), id: \.element.id) { index, day in
                            daySection(day, isLast: index == visibleDays.count - 1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Spacer(minLength: 0)
        }
        .padding(family == .systemLarge ? 16 : (family == .systemSmall ? 11 : 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? .black : .white
            })
        }
    }

    @ViewBuilder
    private func daySection(_ day: ForMemoUpcomingDay, isLast: Bool, taskLimitOverride: Int? = nil) -> some View {
        let taskLimit = taskLimitOverride ?? taskLimitPerDay
        VStack(alignment: .leading, spacing: family == .systemLarge ? 4 : (family == .systemSmall ? 3 : 3)) {
            Text(dayHeading(day.date))
                .font(.system(size: family == .systemSmall ? 11 : (family == .systemLarge ? 12 : 11), weight: .bold, design: .rounded))
                .foregroundStyle(isToday(day.date) ? Color.accentColor : Color.secondary)
                .textCase(.uppercase)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(day.tasks.prefix(taskLimit).enumerated()), id: \.element.id) { index, task in
                    HStack(alignment: .top, spacing: family == .systemSmall ? 4 : 7) {
                        VStack(spacing: 0.5) {
                            Circle()
                                .fill(timelineColor(for: task))
                                .frame(width: family == .systemSmall ? 6 : 8, height: family == .systemSmall ? 6 : 8)
                                .padding(.top, family == .systemSmall ? 4 : 4)

                            if index < min(day.tasks.count, taskLimit) - 1 {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.50))//colore linea tra i pallini
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: family == .systemSmall ? 5 : 6)

                        if let deadline = task.deadline {
                            Text(forMemoWidgetTimeString(deadline))
                                .font(.system(size: family == .systemSmall ? 11 : (family == .systemLarge ? 12 : 11), weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(deadline < entry.date ? Color.red : Color.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: family == .systemLarge ? 42 : (family == .systemSmall ? 39 : 38), alignment: .leading)
                        }

                        Text(task.title)
                            .font(.system(size: family == .systemSmall ? 11 : (family == .systemLarge ? 13 : 11), weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, -2)
                }

                if family != .systemSmall && day.tasks.count > taskLimit {
                    Text("+\(day.tasks.count - taskLimit) more")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 13)
                }
            }
        }
    }

    private var taskLimitPerDay: Int {
        family == .systemLarge ? 4 : 2
    }

    private func dayHeading(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Tomorrow") }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date).capitalized
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    private func timelineColor(for task: TaskWidgetItem) -> Color {
        task.priorityRaw == 4 ? .red : Color.accentColor
    }
}

struct ForMemoAgendaWidget: Widget {
    let kind: String = "ForMemoAgendaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ForMemoAgendaProvider()) { entry in
            ForMemoAgendaEntryView(entry: entry)
        }
        .configurationDisplayName("Upcoming Activities")
        .description("Activities grouped by day with time and timeline.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemMedium) {
    ForMemoAgendaWidget()
} timeline: {
    ForMemoAgendaEntry(date: .now, snapshot: nil)
}


// MARK: - AlarmKit Snooze Live Activity

import AlarmKit
import ActivityKit

// Keep this metadata type identical to the one used by the app target.
struct ForMemoAlarmMetadata: AlarmMetadata {}

struct ForMemoAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<ForMemoAlarmMetadata>.self) { context in
            HStack(alignment: .center, spacing: 12) {
//                Text("ForMemo")
//                    .font(.headline.weight(.bold))
//                    .foregroundStyle(.blue)
//                    .lineLimit(1)

                Text("⏰ \(context.attributes.presentation.alert.title)")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
//                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(0)

                switch context.state.mode {
                case .countdown(let countdown):
                    Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
                        .font(.system(size: 48, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                        .frame(width: 150, alignment: .trailing)
                        .layoutPriority(1)
                    
                case .paused:
                    Text(String(localized: "Paused"))
                        .font(.title2.weight(.semibold))
                case .alert:
                    Text(String(localized: "Alarm"))
                        .font(.title2.weight(.semibold))
                @unknown default:
                    Text(String(localized: "Alarm"))
                }
            }
            .padding()
            .activityBackgroundTint(Color.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if case .countdown(let countdown) = context.state.mode {
                        Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
                            .monospacedDigit()
                    } else {
                        Text(String(localized: "ForMemo Alarm"))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("⏰ \(context.attributes.presentation.alert.title)")
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
            } compactTrailing: {
                if case .countdown(let countdown) = context.state.mode {
                    Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
                        .monospacedDigit()
                } else {
                    Image(systemName: "alarm.fill")
                }
            } minimal: {
                Image(systemName: "alarm.fill")
            }
        }
    }
}
