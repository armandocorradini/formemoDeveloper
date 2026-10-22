import WidgetKit
import SwiftUI
import UIKit

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
        let nextRefresh = calendar.date(byAdding: .hour, value: 24, to: now)
            ?? now.addingTimeInterval(86_400)
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
                        Text(deadline.formatted(date: .omitted, time: .shortened))
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


// MARK: - Agenda Widget

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
        var entryDates: Set<Date> = [now]

        // Keep the timeline bounded. With many recurring tasks, one entry per
        // deadline can create thousands of entries and prevent WidgetKit from
        // rendering the Agenda. Refresh at day boundaries instead.
        for offset in 1...7 {
            if let day = calendar.date(
                byAdding: .day,
                value: offset,
                to: calendar.startOfDay(for: now)
            ) {
                entryDates.insert(day)
            }
        }

        let entries = entryDates.sorted().map { ForMemoAgendaEntry(date: $0, snapshot: snapshot) }
        let refresh = calendar.date(byAdding: .hour, value: 24, to: now)
            ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

private struct ForMemoAgendaDay: Identifiable {
    let date: Date
    let tasks: [TaskWidgetItem]
    // Set only when the final visible day must be compacted to fit the widget.
    var visibleTaskCount: Int? = nil
    var id: Date { date }
}

struct ForMemoAgendaEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ForMemoAgendaEntry

    private var dayCount: Int {
        family == .systemMedium ? 3 : 5
    }

    private var days: [ForMemoAgendaDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        guard let snapshot = entry.snapshot else { return [] }
        return (0..<dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let tasks = snapshot.tasks
                .filter { task in
                    guard let deadline = task.deadline, !task.isCompleted else { return false }
                    return deadline >= day && deadline < nextDay
                }
                .sorted { first, second in
                    guard let a = first.deadline, let b = second.deadline else { return first.deadline != nil }
                    if a != b { return a < b }
                    return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
                }
            return ForMemoAgendaDay(date: day, tasks: tasks)
        }
    }

    private var hasOverdueTasks: Bool {
        guard let snapshot = entry.snapshot else { return false }
        let startOfDisplayedDay = Calendar.current.startOfDay(for: entry.date)
        return snapshot.tasks.contains { task in
            guard !task.isCompleted, let deadline = task.deadline else { return false }
            return deadline < startOfDisplayedDay
        }
    }

    private var todayTaskLimit: Int {
        family == .systemMedium ? 2 : 4
    }

    private func taskLimit(for day: ForMemoAgendaDay) -> Int {
        Calendar.current.isDateInToday(day.date) ? todayTaskLimit : (family == .systemMedium ? 1 : 2)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: entry.date).capitalized
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: family == .systemMedium ? 5 : 6) {
                // The month/year header has its own fixed-height band.
                // Agenda rows are constrained to the remaining widget area.
                Text(monthTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
                    .layoutPriority(10)

                Rectangle()
                    .fill(hasOverdueTasks ? Color.red.opacity(0.85) : Color.primary.opacity(0.16))
                    .frame(height: 1)

                agendaRows(
                    availableHeight: max(
                        0,
                        geometry.size.height
                            - 8
                            - (family == .systemMedium ? 8 : 12)
                            - 22
                            - 1
                            - ((family == .systemMedium ? 5 : 6) * 2)
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
            .padding(.top, 8)
            .padding(.horizontal, family == .systemMedium ? 10 : 12)
            .padding(.bottom, family == .systemMedium ? 8 : 12)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
        }
        .containerBackground(for: .widget) {
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? .black : .white
            })
        }
    }

    private func visibleDays(availableHeight: CGFloat) -> [ForMemoAgendaDay] {
        let rowSpacing: CGFloat = family == .systemMedium ? 3 : 4
        var usedHeight: CGFloat = 0
        var result: [ForMemoAgendaDay] = []

        for day in days {
            let taskCount = min(day.tasks.count, taskLimit(for: day))
            let hasMoreLabel = day.tasks.count > taskLimit(for: day)
            let estimatedHeight: CGFloat

            if day.tasks.isEmpty {
                estimatedHeight = 14
            } else {
                let taskRowsHeight = CGFloat(taskCount) * 21
                    + CGFloat(max(0, taskCount - 1)) * 3
                let moreHeight: CGFloat = hasMoreLabel ? 14 : 0
                let moreSpacing: CGFloat = hasMoreLabel ? 3 : 0
                estimatedHeight = max(28, taskRowsHeight + moreHeight + moreSpacing)
            }

            let dividerHeight: CGFloat = result.isEmpty ? 0 : rowSpacing + 0.5
            if usedHeight + dividerHeight + estimatedHeight > availableHeight {
                // If a complete day does not fit, use the remaining space for
                // one task and a "+N more" label rather than leaving the whole
                // remainder empty. Never add a partial day without room for
                // both the task row and its remainder label.
                let remainingHeight = availableHeight - usedHeight - dividerHeight
                let canShowCompactDay = !day.tasks.isEmpty
                    && day.tasks.count > 1
                    && remainingHeight >= 40

                if canShowCompactDay {
                    result.append(
                        ForMemoAgendaDay(
                            date: day.date,
                            tasks: day.tasks,
                            visibleTaskCount: 1
                        )
                    )
                }
                break
            }

            usedHeight += dividerHeight + estimatedHeight
            result.append(day)
        }

        return result
    }

    @ViewBuilder
    private func agendaRows(availableHeight: CGFloat) -> some View {
        let visible = visibleDays(availableHeight: availableHeight)

        if entry.snapshot == nil {
            Text(String(localized: "Open ForMemo to refresh your tasks."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if days.allSatisfy({ $0.tasks.isEmpty }) {
            Text(String(localized: "Nothing scheduled"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: family == .systemMedium ? 3 : 4) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, day in
                    let shownTaskLimit = day.visibleTaskCount ?? taskLimit(for: day)
                    if day.tasks.isEmpty {
                        HStack(spacing: 6) {
                            Text(day.date.formatted(.dateTime.day()))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Color.accentColor : Color.primary)
                            Text(day.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 14, alignment: .leading)
                    } else {
                        HStack(alignment: .top, spacing: 9) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(day.date.formatted(.dateTime.day()))
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Color.accentColor : Color.primary)
                                Text(day.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 37, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(day.tasks.prefix(shownTaskLimit))) { task in
                                    agendaTask(task)
                                }
                                if day.tasks.count > shownTaskLimit {
                                    Text(String(localized: "+\(day.tasks.count - shownTaskLimit) more"))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    if index < visible.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.10))
                            .frame(height: 0.5)
                            .padding(.leading, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func agendaTask(_ task: TaskWidgetItem) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(priorityColor(task.priorityRaw))
                .frame(width: 3)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let deadline = task.deadline {
                    Text(deadline.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(
                            Calendar.current.isDateInToday(entry.date) && deadline < entry.date
                                ? Color.red
                                : Color.secondary
                        )
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(task.title)
                    .font(.system(size: family == .systemSmall ? 10 : 13, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(priorityColor(task.priorityRaw).opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func priorityColor(_ rawValue: Int) -> Color {
        switch rawValue {
//        case 1: return .blue
//        case 2: return .yellow
//        case 3: return .orange
        case 4: return .red
        default: return .clear//.gray
        }
    }
}

struct ForMemoAgendaWidget: Widget {
    let kind: String = "ForMemoAgendaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ForMemoAgendaProvider()) { entry in
            ForMemoAgendaEntryView(entry: entry)
        }
        .configurationDisplayName("ForMemo — Agenda")
        .description("Shows upcoming tasks grouped by day.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemMedium) {
    ForMemoAgendaWidget()
} timeline: {
    ForMemoAgendaEntry(date: .now, snapshot: nil)
}
