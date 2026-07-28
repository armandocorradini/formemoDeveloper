
import SwiftUI
import SwiftData
import os
import CoreLocation

struct WeeklyTasksView: View {

    @Environment(AppSettings.self)
    private var settings

    private var taskWeekDays: Int {
        settings.taskWeekDays
    }
    
    @Environment(\.locale) private var appLocale
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var weatherManager = WeatherManager.shared
    
    @State private var locationAuthorizationStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus
    
    
    @State private var taskPendingDeletion: TodoTask?
    @State private var draftTask: TodoTask?
    private struct SelectedWeatherDay: Identifiable {
        let date: Date
        var id: Date { date }
    }

    @State private var selectedWeatherDay: SelectedWeatherDay?

    private static let activeTasksPredicate =
        #Predicate<TodoTask> { !$0.isCompleted }

    private static let activeTasksSortDescriptors = [
        SortDescriptor<TodoTask>(\.deadLine, order: .forward)
    ]

    @Query(
        filter: Self.activeTasksPredicate,
        sort: Self.activeTasksSortDescriptors
    )

    private var allTasks: [TodoTask]
    
    private var weeklyTasks: [TodoTask] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let endOfPeriod = calendar.date(byAdding: .day, value: taskWeekDays, to: startOfToday)?
            .addingTimeInterval(-1) ?? .now
        let filtered = allTasks.filter { task in
            guard let deadline = task.deadLine else { return false }
            return deadline >= startOfToday && deadline <= endOfPeriod
        }
        let unique = Dictionary(grouping: filtered, by: \.id)
            .compactMap { $0.value.first }
        return unique.sorted {
            let lhs = $0.deadLine ?? .distantFuture
            let rhs = $1.deadLine ?? .distantFuture
            if lhs != rhs {
                return lhs < rhs
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    
    private var expiredTasks: [TodoTask] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        
        let filtered = allTasks.filter { task in
            guard let deadline = task.deadLine else { return false }
            return deadline < startOfToday
        }

        let unique = Dictionary(grouping: filtered, by: \.id)
            .compactMap { $0.value.first }

        return unique.sorted {
            let lhs = $0.deadLine ?? .distantFuture
            let rhs = $1.deadLine ?? .distantFuture

            if lhs != rhs {
                return lhs < rhs
            }

            return $0.id.uuidString < $1.id.uuidString
        }
    }
    private var dayTasks: [TodoTask] {
        allTasks.filter { task in
            guard let deadline = task.deadLine else { return false }
            return Calendar.current.isDateInToday(deadline)
        }
    }
    private var formattedDate: String {
        Date.now.formatted(
            .dateTime
                .locale(appLocale)
                .weekday(.wide)
                .day()
                .month(.wide)
        )
        .capitalized
    }
    

    private struct GroupedDay: Identifiable {
        let date: Date
        let tasks: [TodoTask]

        var id: Date { date }
    }

    private var groupedTasksByDay: [GroupedDay] {

        let calendar = Calendar.current

        let grouped = Dictionary(grouping: weeklyTasks) { task in
            calendar.startOfDay(for: task.deadLine ?? .now)
        }

        return grouped
            .map { key, value in
                GroupedDay(
                    date: key,
                    tasks: value.sorted {
                        ($0.deadLine ?? .distantFuture) < ($1.deadLine ?? .distantFuture)
                    }
                )
            }
            .sorted { $0.date < $1.date }
    }


    private func relativeHeaderTitle(for date: Date) -> LocalizedStringKey? {

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)

        guard let days = calendar.dateComponents([.day], from: today, to: target).day else {
            return nil
        }

        switch days {
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        case 2:
            return "Day After Tomorrow"
        default:
            return nil
        }
    }

    @ViewBuilder
    private func groupedHeaderView(for group: GroupedDay) -> some View {
        if let title = relativeHeaderTitle(for: group.date) {
            let _ = weatherManager.refreshID

            let isTodayGroup = Calendar.current.isDateInToday(group.date)

            HStack(spacing: TaskRowLayout.dateToContentSpacing) {

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.82))

                Text("\(group.tasks.count)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.clear)
                            .glassEffect(.clear)
                    }

                Spacer(minLength: 0)

                if (locationAuthorizationStatus == .authorizedAlways
                    || locationAuthorizationStatus == .authorizedWhenInUse),
                   let weather = weatherManager.weather(for: group.date) {

                    Button {
                        selectedWeatherDay = SelectedWeatherDay(date: group.date)
                    } label: {

                        HStack(spacing: 7) {

                            Image(
                                systemName:
                                    isTodayGroup
                                    ? weatherManager.representativeSymbol(for: group.date)
                                    : weather.symbolName
                            )
                            .symbolRenderingMode(.multicolor)
                            .saturation(colorScheme == .light ? 1.25 : 1.0)
                            .brightness(colorScheme == .light ? -0.2 : 0.0)
                            .font(.subheadline.weight(.medium))

                            Text("\(weather.minTemperature)°")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(
                                    weather.minTemperature >= 35 ? .red :
                                    weather.minTemperature >= 30 ? .orange :
                                    weather.minTemperature <= 0 ? Color(red: 0.65, green: 0.88, blue: 1.00) :
                                    .primary.opacity(0.55)
                                )
                                .monospacedDigit()

                            Text("/")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary.opacity(0.6))

                            Text("\(weather.maxTemperature)°")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    weather.maxTemperature >= 35 ? .red :
                                    weather.maxTemperature >= 30 ? .orange :
                                    weather.maxTemperature <= 0 ? Color(red: 0.65, green: 0.88, blue: 1.00) :
                                    .primary.opacity(0.90)
                                )
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TaskRowMetrics.groupedLeadingPadding)
            .padding(.vertical, isTodayGroup ? 12 : 9)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                Capsule(style: .continuous)
                    .fill(.clear)
                    .glassEffect(.clear)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                isTodayGroup
                                ? Color.accentColor.opacity(0.06)
                                : Color.white.opacity(0.015)
                            )
                    }
                    .clipShape(
                        Capsule(style: .continuous)
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        .white.opacity(0.12),
                        lineWidth: 0.8
                    )
            }
//posizione capsula giorno (oggi, domani, ieri, ....
            .padding(.top, -8)
            .padding(.leading, TaskRowMetrics.groupedLeadingPadding - 24)

            .padding(.bottom, -(TaskRowMetrics.weeklyVerticalPadding / 7))
        }
    }
    var body: some View {
        ZStack {
            AppGlassBackground()
            Color.clear
            List {
                if weeklyTasks.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text(
                                taskWeekDays == 1
                                ? String(localized: "No tasks today")
                                : String(localized: "No tasks these days")
                            )
                            .font(.subheadline)
                        } icon: {
                            Image(systemName: "tray")
                                .resizable()
                                .frame(width: 30, height: 30)
                                .foregroundStyle(.secondary)
                        }
                    } description: {
                        Text("Tap the green button to add a task.")
                            .font(.subheadline)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(groupedTasksByDay.enumerated()), id: \.element.id) { groupIndex, group in

                        let shouldShowUpcomingCapsule = {

                            guard groupIndex > 0 else {
                                return false
                            }

                            let previousDate = groupedTasksByDay[groupIndex - 1].date

                            return relativeHeaderTitle(for: previousDate) != nil
                                && relativeHeaderTitle(for: group.date) == nil
                        }()

                        if shouldShowUpcomingCapsule {

                            let upcomingTasksCount = groupedTasksByDay[groupIndex...]
                                .reduce(0) { partialResult, group in
                                    partialResult + group.tasks.count
                                }

                            HStack(spacing: TaskRowLayout.dateToContentSpacing) {
                                Text(String(localized: "Upcoming"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.primary.opacity(0.82))

                                Text("\(upcomingTasksCount)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.primary.opacity(0.95))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background {
                                        Capsule(style: .continuous)
                                            .fill(.clear)
                                            .glassEffect(.clear)
                                    }
                            }
                            .padding(.horizontal, TaskRowMetrics.groupedLeadingPadding)
                            .padding(.vertical, 9)
                            .fixedSize(horizontal: true, vertical: false)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(.clear)
                                    .glassEffect(.clear)
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .fill(Color.white.opacity(0.015))
                                    }
                                    .clipShape(
                                        Capsule(style: .continuous)
                                    )
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        .white.opacity(0.12),
                                        lineWidth: 0.8
                                    )
                            }
                            .padding(.top, -16)
                            .padding(.leading, TaskRowMetrics.groupedLeadingPadding - 7)
                            .padding(.bottom, -(TaskRowMetrics.weeklyVerticalPadding * 3))
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }

                        groupedSection(for: group)
                    }
                }
            }
            .contentMargins(.bottom, 70, for: .scrollContent)
            .contentMargins(
                .horizontal,
                TaskRowMetrics.groupedLeadingPadding,
                for: .scrollContent
            )
            .background(Color.clear)
            .listRowBackground(Color.clear)
            .listStyle(.plain)
            .animation(.smooth(duration: 0.18), value: groupedTasksByDay.count)
            .task {
                await weatherManager.refreshIfNeeded()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .locationPermissionChanged
                )
            ) { _ in
                locationAuthorizationStatus = CLLocationManager().authorizationStatus
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                headerView
                    .padding(.top, 2)
                    .padding(.bottom, 2)
            }
            .navigationTitle(formattedDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draftTask = TodoTask()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                            .padding(.trailing, 5)
                    }
                }
            }
            .navigationDestination(for: TodoTask.self) { task in
                TaskDetailView(task: task)
            }
            .sheet(item: $draftTask) { task in
                NewTaskSheetView(draftTask: task)
            }
            .sheet(item: $selectedWeatherDay) { selectedDay in
                NavigationStack {
                    WeatherDayView(
                        date: selectedDay.date,
                        showsCloseButton: true,
                        closeAction: {
                            selectedWeatherDay = nil
                        }
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .containerBackground(.clear, for: .navigation)
            // Shared delete confirmation alert
            .alert(
                "Delete task?",
                isPresented: Binding(
                    get: { taskPendingDeletion != nil },
                    set: { if !$0 { taskPendingDeletion = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let task = taskPendingDeletion {
                        withAnimation {
                            deleteTask(task, in: modelContext)
                        }
                        taskPendingDeletion = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    taskPendingDeletion = nil
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }
    
    @ViewBuilder
    private func groupedSection(for group: GroupedDay) -> some View {

        Section {

            ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in

                WeeklyTaskRow(
                    taskPendingDeletion: $taskPendingDeletion,
                    taskWeekDays: taskWeekDays,
                    task: task,
                    position:     TaskRowPosition.position(
                        index: index,
                        total: group.tasks.count
                    )
                )
                .listRowSeparator(.hidden)
            
            }

        } header: {
            groupedHeaderView(for: group)
        }
        .listSectionSeparator(.hidden)
        .listSectionSpacing(TaskRowMetrics.weeklyVerticalPadding / 2)
    }

    // MARK: - Header
    
    private var headerView: some View {
        
        VStack {
            
            if expiredTasks.count > 0 {
                HStack {

                    Spacer()

                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)

                    Text("Overdue in previous days: \(expiredTasks.count)")
                        .font(.body)
                        .foregroundStyle(.red)

                    Spacer()
                }
            }

            HStack {
                Spacer()
                Stepper(
                    "",
                    value: Binding(
                        get: { settings.taskWeekDays },
                        set: { settings.taskWeekDays = $0 }
                    ),
                    in: 1...7
                )
                .labelsHidden()
                .fixedSize()
                Text("Next \(taskWeekDays) Days")
                    .foregroundStyle(Color(UIColor.label))

                
                Spacer()
            }
            .padding(.top, 8)
        }
        .textCase(nil)
  
    }

    // MARK: - Row

private struct WeeklyTaskRow: View {
    
    @Environment(AppSettings.self)
    private var settings

    private var confirmTaskDeletion: Bool {
        settings.confirmTaskDeletion
    }

    private var showTodayExpiredLabel: Bool {
        settings.showTodayExpiredLabel
    }


    private var showDateEveryRow: Bool {
        settings.showDateEveryRow
    }

    
    @Binding var taskPendingDeletion: TodoTask?
    
    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.colorScheme) private var colorScheme
    let taskWeekDays: Int
    let task: TodoTask
    let position: TaskRowPosition

    private var hasAttachments: Bool {
        !(task.attachments ?? []).isEmpty
    }

    private var hasLocation: Bool {
        task.locationName?.isEmpty == false
    }

    private var priorityIconName: String? {
        task.priority.systemImage
    }

    
    var body: some View {
        TaskRow(
            task: task,
            showDateColumn:
                showDateEveryRow
                ? true
                : (position == .first || position == .single),
            appearance: .current(from: settings)
        )
        
        .frame(
            minHeight: max(
                1,
                TaskRowMetrics.rowHeight + CGFloat(settings.taskRowVerticalPadding)
            ),
            alignment: .leading
        )
        .modifier(
            RowCardStyle(
                task: task,
                style: .grouped,
                position: position,
                opacity: 1
            )
        )
        .contentShape(Rectangle())

        .animation(nil, value: task.deadLine)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            completeAction
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {

            Button(role: .destructive) {

                if confirmTaskDeletion {
                    taskPendingDeletion = task
                } else {
                    withAnimation {
                        deleteTask(task, in: modelContext)
                    }
                }

            } label: {
                Label("Delete", systemImage: "trash")
            }
        }

        .contextMenu {
            Button(role: .destructive) {
                if confirmTaskDeletion {
                    taskPendingDeletion = task
                } else {
                    withAnimation {
                        deleteTask(task, in: modelContext)
                    }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                completeTask()
            } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }

   
            Menu {
                Button {
                    postpone(task, byHours: 1)
                } label: {
                    Label("+1 hour", systemImage: "clock.badge")
                }

                Button {
                    postpone(task, byHours: 3)
                } label: {
                    Label("+3 hours", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }

                Button {
                    postpone(task, byDays: 1)
                } label: {
                    Label("+1 day", systemImage: "sun.max")
                }

                Button {
                    postpone(task, byDays: 2)
                } label: {
                    Label("+2 days", systemImage: "calendar")
                }

                Button {
                    postpone(task, byDays: 3)
                } label: {
                    Label("+3 days", systemImage: "calendar.badge.clock")
                }
            } label: {
                Label("Reschedule", systemImage: "clock")
            }
            
            if let deadline = task.deadLine,

                deadline < Date() {
                Menu {
                    Button {
                        NotificationActionProcessor.shared.applyManualSnooze(
                            to: task,
                            interval: 5 * 60,
                            using: modelContext
                        )
                    } label: {
                        Label("5 minutes", systemImage: "5.arrow.trianglehead.clockwise")
                    }
                    
                    Button {
                        NotificationActionProcessor.shared.applyManualSnooze(
                            to: task,
                            interval: 15 * 60,
                            using: modelContext
                        )
                    } label: {
                        Label("15 minutes", systemImage: "15.arrow.trianglehead.clockwise")
                    }
                    
                    Button {
                        NotificationActionProcessor.shared.applyManualSnooze(
                            to: task,
                            interval: 30 * 60,
                            using: modelContext
                        )
                    } label: {
                        Label("30 minutes", systemImage: "30.arrow.trianglehead.clockwise")
                    }
                    
                    Button {
                        NotificationActionProcessor.shared.applyManualSnooze(
                            to: task,
                            interval: 60 * 60,
                            using: modelContext
                        )
                    } label: {
                        Label("1 hour", systemImage: "60.arrow.trianglehead.clockwise")
                    }
                    
                    Button {
                        NotificationActionProcessor.shared.applyManualSnooze(
                            to: task,
                            interval: 3 * 60 * 60,
                            using: modelContext
                        )
                    } label: {
                        Label("3 hours", systemImage: "plus.arrow.trianglehead.clockwise")
                    }
                } label: {
                    Label("Snooze", systemImage: "timer")
                }
            }

        }
    }
    
    // MARK: - Actions
    
    private var completeAction: some View {
        
        Button {
            completeTask()
        } label: {
            Label("Complete", systemImage: "checkmark")
        }
        .tint(.green)
    }
    
    @MainActor
    private func postpone(_ task: TodoTask, byHours hours: Int) {

        let baseDate = task.deadLine ?? Date()
        let newDate = Calendar.current.date(byAdding: .hour, value: hours, to: baseDate) ?? baseDate

        postpone(task, to: newDate)
    }

    @MainActor
    private func postpone(_ task: TodoTask, byDays days: Int) {

        let baseDate = task.deadLine ?? Date()
        let newDate = Calendar.current.date(byAdding: .day, value: days, to: baseDate) ?? baseDate

        postpone(task, to: newDate)
    }

    @MainActor
    private func postpone(_ task: TodoTask, to newDate: Date) {

        task.deadLine = newDate

        do {
            try modelContext.save()
            modelContext.processPendingChanges()

            NotificationManager.shared.refresh(force: true)
            NotificationCenter.default.post(name: .taskDidChange, object: nil)

        } catch {
            AppLogger.persistence.fault("Failed to postpone task: \(error)")
        }
    }

    @MainActor
    private func completeTask() {
        guard task.isCompleted == false else { return }
        if task.recurrenceRule != nil {
            // Complete(se scelto da utente) and reschedule recurring task
            task.completeRecurringTask(
                in: modelContext,
                options: settings.recurringTaskOptions
            )
        } else {
            task.isCompleted = true
            task.completedAt = .now
            task.snoozeUntil = nil
        }
        do {
            try modelContext.save()
            // Refresh notifications
            NotificationManager.shared.refresh(force: true)
            // Trigger list refresh
            NotificationCenter.default.post(name: .taskDidChange, object: nil)
        } catch {
            AppLogger.persistence.fault("Failed to save completion: \(error)")
        }
    }
    
}

}

