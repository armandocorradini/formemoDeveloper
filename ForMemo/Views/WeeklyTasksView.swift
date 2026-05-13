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

        let uniqueTasks = Array(
            Dictionary(grouping: filtered, by: \.id)
                .compactMap { $0.value.first }
        )

        return uniqueTasks.sorted {
            let firstDate = $0.deadLine ?? .distantFuture
            let secondDate = $1.deadLine ?? .distantFuture

            if firstDate != secondDate {
                return firstDate < secondDate
            }

            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
    
    
    private var expiredTasks: [TodoTask] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        
        let filtered = allTasks.filter { task in
            guard let deadline = task.deadLine else { return false }
            return deadline < startOfToday
        }

        let uniqueTasks = Array(
            Dictionary(grouping: filtered, by: \.id)
                .compactMap { $0.value.first }
        )

        return uniqueTasks.sorted {
            let firstDate = $0.deadLine ?? .distantPast
            let secondDate = $1.deadLine ?? .distantPast

            if firstDate != secondDate {
                return firstDate < secondDate
            }

            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
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
            List {
                
                Section {
                    
                    if weeklyTasks.isEmpty {
                        
                        AppUnavailableView.empty(
                            taskWeekDays == 1 ? String(localized:"No tasks today") : String(localized:"No tasks these days"),
                            systemImage: "ellipsis.calendar"
                        )
                        
                    } else {
                        
                        ForEach(weeklyTasks) { task in
                            WeeklyTaskRow(
                                taskPendingDeletion: $taskPendingDeletion,task: task
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(
                                .init(top: 4, leading: 14, bottom: 4, trailing: 14)
                            )
                            .listRowBackground(Color.clear)
                        }
                    }
                    
                } header: {
                    headerView
                }
            }
            .listStyle(.plain)
            .navigationTitle(formattedDate)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: TodoTask.self) { task in
                TaskDetailView(task: task)
            }
            .scrollContentBackground(.hidden)
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
            .padding(.top, -35)
            
            HStack {
                Spacer()
                Stepper("", value: $taskWeekDays, in: 1...7)
                    .labelsHidden()
                    .fixedSize()
                Text("Next \(taskWeekDays) Days")
                    .foregroundStyle(Color(UIColor.label))
                    .padding(3)
                
                Spacer()
            }
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
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
    
    @Binding var taskPendingDeletion: TodoTask?
    
    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.colorScheme) private var colorScheme
    
    let task: TodoTask
    
    var body: some View {
        
        ZStack {
            
            NavigationLink(value: task) {
                EmptyView()
            }
            .opacity(0)
            
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 14) {
                    dayBadge
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
            .padding(.horizontal, 14)
            .background {
                cardBackground
            }
        }
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
    
    // MARK: - Background
    
    private var cardBackground: some View {
        let deadline = task.deadLine ?? .distantFuture

        let isCritical = task.priority.systemImage == "flame"
        let isToday = Calendar.current.isDateInToday(deadline) && deadline >= Date()
        let isOverdue = deadline < Date()
        let shouldHighlight = highlightEnabled && isCritical && (isToday || isOverdue)

        return RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.clear)
            .overlay(alignment: .leading) {
                if shouldHighlight {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(highlightColor)
                        .frame(width: 1.3, height: 39)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding(.leading, 10)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isOverdue
                            ? Color.red
                            : isToday
                                ? Color.orange
                                : Color.secondary,
                        lineWidth: (isToday || isOverdue) ? 0.4 : 0.3
                    )
            )
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
