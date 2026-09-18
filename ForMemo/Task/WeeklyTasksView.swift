
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

    
    @State private var weeklyTasks: [TodoTask] = []
    @State private var expiredTaskCount = 0
    
    @MainActor
    private func fetchWeeklyTasks() {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)

        guard let endOfPeriod = calendar.date(
            byAdding: .day,
            value: taskWeekDays,
            to: startOfToday
        ) else {
            weeklyTasks = []
            expiredTaskCount = 0
            return
        }

        let weeklyPredicate = #Predicate<TodoTask> { task in
            !task.isCompleted &&
            task.deadLine != nil &&
            task.deadLine! >= startOfToday &&
            task.deadLine! < endOfPeriod
        }

        let weeklyDescriptor = FetchDescriptor<TodoTask>(
            predicate: weeklyPredicate,
            sortBy: [
                SortDescriptor(\TodoTask.deadLine, order: .forward)
            ]
        )

        let expiredPredicate = #Predicate<TodoTask> { task in
            !task.isCompleted &&
            task.deadLine != nil &&
            task.deadLine! < startOfToday
        }

        let expiredDescriptor = FetchDescriptor<TodoTask>(
            predicate: expiredPredicate
        )

        do {
            weeklyTasks = try modelContext.fetch(weeklyDescriptor)
        } catch {
            AppLogger.persistence.error(
                "Weekly tasks fetch failed: \(error.localizedDescription)"
            )
            weeklyTasks = []
        }

        do {
            expiredTaskCount = try modelContext.fetchCount(expiredDescriptor)
        } catch {
            AppLogger.persistence.error(
                "Expired tasks count failed: \(error.localizedDescription)"
            )
            expiredTaskCount = 0
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
                fetchWeeklyTasks()
                await weatherManager.refreshIfNeeded()
            }
            .onChange(of: taskWeekDays) {
                fetchWeeklyTasks()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .taskDidChange)
            ) { _ in
                fetchWeeklyTasks()
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
            .scrollEdgeEffectHidden(true, for: .top)
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
            
            if expiredTaskCount > 0 {
                HStack {

                    Spacer()

                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)

                    Text("Overdue in previous days: \(expiredTaskCount)")
                        .font(.body)
                        .foregroundStyle(.red)

                    Spacer()
                }
            }

            HStack {
//                Spacer()
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
            .padding(.leading, 70)
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

            if task.deadLine != nil {
                Button {
                    TaskSingleCalendarExport.shared.present(for: task)
                } label: {
                    Label(
                        "Add to Calendar",
                        systemImage: "calendar.badge.plus"
                    )
                }
            }
            TaskRescheduleMenu(task: task)
            
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
            Menu {

                Button {
                    do {
                        _ = try TaskDuplicationService.duplicate(
                            task,
                            using: modelContext,
                            includingAttachments: false
                        )
                        NotificationCenter.default.post(
                            name: .taskDidChange,
                            object: nil
                        )
                    } catch {
                        AppLogger.persistence.error(
                            "Task duplication failed: \(error.localizedDescription)"
                        )
                    }
                } label: {
                    Label("Task", systemImage: "text.badge.checkmark")
                }

                if !(task.attachments?.isEmpty ?? true) {
                    Button {
                        do {
                            _ = try TaskDuplicationService.duplicate(
                                task,
                                using: modelContext,
                                includingAttachments: true
                            )
                            NotificationCenter.default.post(
                                name: .taskDidChange,
                                object: nil
                            )
                        } catch {
                            AppLogger.persistence.error(
                                "Task duplication failed: \(error.localizedDescription)"
                            )
                        }
                    } label: {
                        Label(
                            "Task & Attachments",
                            systemImage: "rectangle.and.paperclip"
                        )
                    }
                }

            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
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

