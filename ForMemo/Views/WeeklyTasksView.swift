import SwiftUI
import SwiftData
import os

struct WeeklyTasksView: View {
    
    
    //    let iconStyle: TaskIconStyle
    
    @AppStorage("TaskWeekDays")
    private var taskWeekDays: Int = 3
    
    @Environment(\.locale) private var appLocale
    @Environment(\.modelContext) private var modelContext
    
    @State private var taskPendingDeletion: TodoTask?
    
    @Query(
        filter: #Predicate<TodoTask> { $0.isCompleted == false },
        sort: [SortDescriptor(\.deadLine, order: .forward)]
    )
    private var allTasks: [TodoTask]
    
    private var weeklyTasks: [TodoTask] {
        let calendar = Calendar.current
        
        // Inizio di oggi (00:00:00)
        let startOfToday = calendar.startOfDay(for: .now)
        
        // Fine dell'ultimo giorno del periodo (23:59:59)
        let endOfPeriod = calendar.date(byAdding: .day, value: taskWeekDays, to: startOfToday)?
            .addingTimeInterval(-1) ?? .now
        
        let filtered = allTasks.filter { task in
            guard let deadline = task.deadLine else { return false }
            // Include tutto ciò che scade da stamattina all'ultimo secondo del settimo giorno
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
    
    enum RowPosition {
        case single
        case first
        case middle
        case last
    }

    private var groupedTasksByDay: [(date: Date, tasks: [TodoTask])] {

        let calendar = Calendar.current

        let grouped = Dictionary(grouping: weeklyTasks) { task in
            calendar.startOfDay(for: task.deadLine ?? .now)
        }

        return grouped
            .map { key, value in
                (
                    date: key,
                    tasks: value.sorted {
                        ($0.deadLine ?? .distantFuture) < ($1.deadLine ?? .distantFuture)
                    }
                )
            }
            .sorted { $0.date < $1.date }
    }


    private func rowPosition(index: Int, total: Int) -> RowPosition {

        if total == 1 {
            return .single
        }

        if index == 0 {
            return .first
        }

        if index == total - 1 {
            return .last
        }

        return .middle
    }

    var body: some View {
        ZStack {
            // 1. IL GRADIENTE (Sotto a tutto)
            LinearGradient(colors: [backColor1, backColor2],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            // 2. IL MATERIAL (Effetto vetro)
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            Color.clear
                .onAppear {
                    UITableView.appearance().backgroundColor = .clear
                    UITableViewCell.appearance().backgroundColor = .clear
                    UITableViewHeaderFooterView.appearance().tintColor = .clear
                    UITableViewHeaderFooterView.appearance().backgroundView = UIView(frame: .zero)
                }
            List {
//                headerView
//                    .listRowInsets(.init(top: 0, leading: 0, bottom: 4, trailing: 0))
//                    .listRowSeparator(.hidden)
//                    .listRowBackground(Color.clear)
                
                    if weeklyTasks.isEmpty {
                        
                        AppUnavailableView.empty(
                            taskWeekDays == 1 ? String(localized:"No tasks today") : String(localized:"No tasks these days"),
                            systemImage: "ellipsis.calendar"
                        )
                        
                    } else {
                        
                        ForEach(groupedTasksByDay, id: \.date) { group in

                            Section {

                                ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in

                                    WeeklyTaskRow(
                                        taskPendingDeletion: $taskPendingDeletion,
                                        taskWeekDays: taskWeekDays,
                                        task: task,
                                        position: rowPosition(
                                            index: index,
                                            total: group.tasks.count
                                        )
                                    )
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(
                                        .init(top: 0, leading: 14, bottom: 0, trailing: 14)
                                    )
                                    .listRowBackground(Color.clear)
                                }

                            } header: {
                                EmptyView()
                            }
                            .listSectionSeparator(.hidden)
                            .listSectionSpacing(8)
                        }
                    }
            }
            .background(Color.clear)
            .listRowBackground(Color.clear)
            .listStyle(.plain)
            .animation(.smooth(duration: 0.18), value: groupedTasksByDay.count)
            .safeAreaInset(edge: .top, spacing: 0) {
                headerView
                    .padding(.top, 6)
                    .padding(.bottom, 6)
            }
            .navigationTitle(formattedDate)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: TodoTask.self) { task in
                TaskDetailView(task: task)
            }
            .scrollContentBackground(.hidden)
            .containerBackground(.clear, for: .navigation)
            // ALERT UNICO – STABILE
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
    
    // MARK: - Header
    
    private var headerView: some View {
        
        VStack {
            
            HStack {
                
                Spacer()
                
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                
                Text("Overdue in previous days: \(expiredTasks.count)")
                    .font(.body)
                    .foregroundStyle(expiredTasks.count > 0 ? .red : .primary)
                
                Spacer()
            }
            .padding(.top, -15)
            .padding(.bottom, 8)
            HStack {
                Spacer()
                Stepper("", value: $taskWeekDays, in: 1...7)
                    .labelsHidden()
                    .fixedSize()
                Text("Next \(taskWeekDays) Days")
                    .foregroundStyle(Color(UIColor.label))
                    .padding(6)
                
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .textCase(nil)
        .padding(.vertical, 8)
    }

// MARK: - Row

private struct WeeklyTaskRow: View {
    
    @AppStorage("tasklist.highlightEnabled")
    private var highlightEnabled: Bool = true

    @AppStorage("tasklist.highlightColor")
    private var highlightColorHex: String = Color.red.toHex() ?? ""

    private var highlightColor: Color {
        Color(hex: highlightColorHex) ?? .red
    }
    
    @AppStorage("confirmTaskDeletion")
    private var confirmTaskDeletion = true
    
    @AppStorage("tasklist.showTodayExpiredLabel")
    private var showTodayExpiredLabel: Bool = true
    
    @Binding var taskPendingDeletion: TodoTask?
    
    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.colorScheme) private var colorScheme
    let taskWeekDays: Int
    let task: TodoTask
    let position: WeeklyTasksView.RowPosition
    
    var body: some View {
        
        ZStack {
            
            NavigationLink(value: task) {
                EmptyView()
            }
            .opacity(0)
            
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 14) {
                    if position == .first || position == .single {
                        dayBadge
                    } else {
                        Color.clear
                            .frame(width: 44, height: 44)
                    }

                    mainColumn
                    Spacer(minLength: 6)
                }

                VStack(spacing: 4) {
                    if let priorityIcon = task.priority.systemImage {
                        Image(systemName: priorityIcon)
                            .foregroundStyle(priorityIcon == "flame" ? .red : .primary)
                    }

                    if let attachments = task.attachments, !attachments.isEmpty {
                        Image(systemName: "paperclip")
                            .foregroundStyle(.primary)
                    }

                    if task.locationName?.isEmpty == false {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.primary)
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .padding(6)

            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background {
                cardBackground
            }
        }
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
            
            // 🔁 Ricorrenza: completa e rischedula
            task.completeRecurringTask(in: modelContext)
            
        } else {
            
            task.isCompleted = true
            task.completedAt = .now
            task.snoozeUntil = nil
        }
        
        do {
            try modelContext.save()
            
            // 🔔 refresh notifiche
            NotificationManager.shared.refresh(force: true)
            
            // 🔥 forza refresh UI liste
            NotificationCenter.default.post(name: .taskDidChange, object: nil)

        } catch {
            AppLogger.persistence.fault("Failed to save completion: \(error)")
        }
    }
    
    // MARK: - Day badge
    
    private var dayBadge: some View {
        
        VStack(spacing: 2) {
            
            if let date = task.deadLine {
                
                Text(date, format: .dateTime.weekday(.abbreviated))
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                
                Text(date, format: .dateTime.day())
                    .font(.title3.weight(.bold))
                    .foregroundStyle(task.status.color)
                
            } else {
                
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
    }
    
    // MARK: - Main column
    
    private var mainColumn: some View {
        
        VStack(alignment: .leading, spacing: 6) {
            
            if showTodayExpiredLabel && !task.isCompleted {

                if isOverdue {

                    Text(String(localized:"Overdue"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)

                } else if isToday && taskWeekDays != 1 {

                    Text(String(localized:"Today"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 6) {
                
                Image(systemName: task.mainTag?.mainIcon ?? task.status.icon)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.primary ,task.mainTag?.color ?? task.status.color)
                    .shadow(color: Color.black.opacity(0.6), radius: 0.5, x: 0.5, y: 0.5)
                    .shadow(color: Color.black.opacity(0.6), radius: 0.5, x: -0.5, y: -0.5)
                
                Text(task.title)
                    .font(.headline)
                    .lineLimit(1)
                
                if task.recurrenceRule != nil {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            
            HStack(spacing: 10) {
                
                if let date = task.deadLine {
                    Image(systemName: "clock")
                    Text(date, format: .dateTime.hour().minute())
                        .foregroundStyle({
                            if let deadline = task.deadLine {
                                let now = Date()
                                let calendar = Calendar.current
                                let isToday = calendar.isDateInToday(deadline) && deadline >= now
                                let isOverdue = deadline < now
                                let isCritical = task.priority.systemImage == "flame"
                                
                                if highlightEnabled && isCritical && (isToday || isOverdue) {
                                    return highlightColor
                                } else if isToday {
                                    return Color.orange
                                } else if isOverdue {
                                    return Color.red
                                } else {
                                    return Color.secondary
                                }
                            } else {
                                return Color.secondary
                            }
                        }())
                }
                
                if let minutes = task.reminderOffsetMinutes {
                    
                    Image(systemName: "bell")
                    Text(reminderText(for: minutes))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
    
    private var isToday: Bool {
        guard let d = task.deadLine else { return false }

        let now = Date()

        return Calendar.current.isDateInToday(d) && d >= now
    }

    private var isOverdue: Bool {
        guard let d = task.deadLine else { return false }
        return d < Date()
    }
    
    
    
    // MARK: - Background
    
    private var cardBackground: some View {

        let deadline = task.deadLine ?? .distantFuture

        let isCritical = task.priority.systemImage == "flame"
        let isToday = Calendar.current.isDateInToday(deadline) && deadline >= Date()
        let isOverdue = deadline < Date()
        let shouldHighlight = highlightEnabled && isCritical && (isToday || isOverdue)

        return ZStack {
            shape
                .fill(
                    Color.white.opacity(colorScheme == .dark ? 0.02 : 0.04)
                )

            shape
                .fill(
                    Color(.systemBackground).opacity(0.3)
                )
        }
        .overlay(alignment: .leading) {

            if shouldHighlight {
                RoundedRectangle(cornerRadius: 3)
                    .fill(highlightColor)
                    .frame(width: 1.5, height: 38)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .padding(.leading, 10)
            }
        }
        .overlay(alignment: .bottom) {

            if position != .last && position != .single {

                Divider()
                    .overlay(
                        colorScheme == .dark
                        ? Color.white.opacity(0.14)
                        : Color.black.opacity(0.10)
                    )
                    .padding(.leading, 82)
                    .padding(.trailing, 24)
            }
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.10 : 0.04),
            radius: 3,
            y: 1
        )
    }


    private var shape: some InsettableShape {

        switch position {
        case .single:
            UnevenRoundedRectangle(
                topLeadingRadius: 22,
                bottomLeadingRadius: 22,
                bottomTrailingRadius: 22,
                topTrailingRadius: 22
            )

        case .first:
            UnevenRoundedRectangle(
                topLeadingRadius: 22,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 22
            )

        case .middle:
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )

        case .last:
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 22,
                bottomTrailingRadius: 22,
                topTrailingRadius: 0
            )
        }
    }
    
    // MARK: - Helpers
    private func reminderText(for minutes: Int) -> String {
        
        if minutes == 0 {
            return String(localized: "At time of event")
        }
        
        if minutes >= 1440 {
            let days = minutes / 1440
            return String(localized: "\(days) days before")
        }
        
        if minutes >= 60 {
            let hours = minutes / 60
            return String(localized: "\(hours) hours before")
        }
        
        return String(localized: "\(minutes) minutes before")
    }
}

// MARK: - Shared helper

private func isTaskToday(_ date: Date?) -> Bool {
    guard let date else { return false }
    return Calendar.current.isDateInToday(date)
}

}

