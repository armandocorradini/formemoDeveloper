import SwiftUI
import SwiftData
import os

struct TaskDayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Query(sort: \TodoTask.deadLine) private var tasks: [TodoTask]

    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var taskPendingDeletion: TodoTask?
    @State private var showDeleteConfirmation = false
    @State private var showAddTaskMenu = false
    @State private var selectedSlotMinutes = 8 * 60
    @State private var draftTask: TodoTask?
    @State private var showDayOptions = false
    @State private var showCalendarPicker = false
    @State private var isDeletingRecurrence = false

    private let calendar = Calendar.current
    private var timelineSlots: [Int] {
        let interval = normalizedTimelineInterval(settings.dayTimelineIntervalMinutes)
        let slots = Array(stride(from: 0, to: 24 * 60, by: interval))

        guard settings.dayHideEmptyNightHours else { return slots }

        let hasNightTasks = timedTasks.contains { task in
            guard let deadline = task.deadLine else { return false }
            return calendar.component(.hour, from: deadline) < 6
        }

        return hasNightTasks ? slots : slots.filter { $0 >= 6 * 60 }
    }

    private var dayTasks: [TodoTask] {
        tasks.filter { task in
            guard let deadline = task.deadLine else { return false }
            return calendar.isDate(deadline, inSameDayAs: selectedDate)
        }
        .sorted {
            guard let first = $0.deadLine, let second = $1.deadLine else { return false }
            return first < second
        }
    }

    private var allDayTasks: [TodoTask] {
        dayTasks.filter { task in
            guard let deadline = task.deadLine else { return false }
            let components = calendar.dateComponents([.hour, .minute], from: deadline)
            return components.hour == 0 && components.minute == 0
        }
    }

    private var timedTasks: [TodoTask] {
        dayTasks.filter { task in
            guard let deadline = task.deadLine else { return false }
            let components = calendar.dateComponents([.hour, .minute], from: deadline)
            return !(components.hour == 0 && components.minute == 0)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            dateStrip
                .padding(.bottom,5)
            Divider()
                .padding(.bottom, 15)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if !allDayTasks.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Text(String(localized: "All day"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .trailing)
                                .padding(.top, 8)
                            VStack(spacing: 6) {
                                ForEach(allDayTasks) { task in
                                    taskRow(task)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        Divider()
                    }

                    ForEach(timelineSlots, id: \.self) { slotMinutes in
                        let hour = slotMinutes / 60
                        let minute = slotMinutes % 60
                        let slotTasks = tasks(in: hour, minute: minute)

                        HStack(alignment: .top, spacing: 8) {
                            Button {
                                selectTimelineSlot(slotMinutes)
                            } label: {
                                Text(String(format: "%02d:%02d", hour, minute))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 52, height: slotTasks.isEmpty ? settings.dayEmptySlotHeight : 16, alignment: .topTrailing)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(format: String(localized: "Add task at %@"), String(format: "%02d:%02d", hour, minute)))

                            VStack(alignment: .leading, spacing: slotTasks.isEmpty ? 0 : 1) {
                                Button {
                                    selectTimelineSlot(slotMinutes)
                                } label: {
                                    ZStack(alignment: .top) {
                                        Rectangle().fill(Color.clear)
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.22))
                                            .frame(height: 1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: slotTasks.isEmpty ? settings.dayEmptySlotHeight : 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(format: String(localized: "Add task at %@"), String(format: "%02d:%02d", hour, minute)))

                                ForEach(Array(slotTasks.enumerated()), id: \.element.id) { item in
                                    taskRow(item.element)
                                    if item.offset < slotTasks.count - 1 {
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.16))
                                            .frame(height: 0.5)
                                            .padding(.leading, 27)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: slotTasks.isEmpty ? 24 : nil, alignment: .topLeading)
                        }
                        .padding(.horizontal, 10)
                        .popover(
                            isPresented: addTaskPopoverBinding(for: slotMinutes),
                            attachmentAnchor: .rect(.bounds),
                            arrowEdge: .top
                        ) {
                            addTaskPopoverContent
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .contentMargins(.bottom, 70, for: .scrollContent)
        }
        .background(AppGlassBackground())
        .overlay {
            if isDeletingRecurrence {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(String(localized: "Deleting occurrences…"))
                            .font(.subheadline)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .transition(.opacity)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    showCalendarPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Text(selectedDate.formatted(.dateTime.month(.wide).year(.twoDigits)))
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Choose date"))
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(String(localized: "Today")) {
                    selectedDate = calendar.startOfDay(for: .now)
                }
                .font(.subheadline)
                .foregroundColor(.blue)

                Button {
                    draftTask = makeNewTask(hour: 8, minute: 0)
                } label: {
                    Image(systemName: draftTask == nil ? "plus.circle.fill" : "minus.circle.fill")
                        .foregroundStyle(draftTask == nil ? .green : .gray)
                        .font(.title2)
                }
                .accessibilityLabel(String(localized: "New task"))
            }

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showDayOptions = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(String(localized: "Day view options"))
                .popover(isPresented: $showDayOptions, arrowEdge: .top) {
                    dayOptionsPopover
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
        .sheet(item: $draftTask) { task in
            NewTaskSheetView(draftTask: task)
        }
        .sheet(isPresented: $showCalendarPicker) {
            NavigationStack {
                VStack {
                    DatePicker(
                        String(localized: "Choose date"),
                        selection: $selectedDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                    Spacer(minLength: 0)
                }
                .navigationTitle(String(localized: "Choose date"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) {
                            selectedDate = calendar.startOfDay(for: selectedDate)
                            showCalendarPicker = false
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) {
                            showCalendarPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert(
            String(localized: "Delete task?"),
            isPresented: Binding(
                get: { taskPendingDeletion != nil },
                set: { if !$0 { taskPendingDeletion = nil } }
            )
        ) {
            if let task = taskPendingDeletion,
               !task.isCompleted,
               task.recurrenceID != nil,
               hasFutureOccurrenceForDeletion(task) {
                Button(String(localized: "Delete This Occurrence"), role: .destructive) {
                    deleteTaskAndRefresh(task)
                    taskPendingDeletion = nil
                }

                Button(String(localized: "Delete This & Future Occurrences"), role: .destructive) {
                    taskPendingDeletion = nil
                    isDeletingRecurrence = true

                    Task { @MainActor in
                        await Task.yield()
                        await deleteRecurringTaskAndFutureOccurrences(task, in: modelContext)
                        modelContext.processPendingChanges()
                        NotificationCenter.default.post(name: .taskDidChange, object: nil)
                        isDeletingRecurrence = false
                    }
                }
            } else {
                Button(String(localized: "Delete"), role: .destructive) {
                    guard let task = taskPendingDeletion else {
                        taskPendingDeletion = nil
                        return
                    }
                    deleteTaskAndRefresh(task)
                    taskPendingDeletion = nil
                }
            }

            Button(String(localized: "Cancel"), role: .cancel) {
                taskPendingDeletion = nil
            }
        } message: {
            Text(String(localized: "This action cannot be undone."))
        }
        .navigationDestination(for: TodoTask.self) { task in
            TaskDetailView(task: task)
        }
    }

    private func selectTimelineSlot(_ minutes: Int) {
        selectedSlotMinutes = minutes
        showAddTaskMenu = true
    }

    private func addTaskPopoverBinding(for slotMinutes: Int) -> Binding<Bool> {
        Binding(
            get: { showAddTaskMenu && selectedSlotMinutes == slotMinutes },
            set: { isPresented in
                if !isPresented {
                    showAddTaskMenu = false
                }
            }
        )
    }

    private var addTaskPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            let hour = selectedSlotMinutes / 60
            let minute = selectedSlotMinutes % 60

            Text(String(format: "%02d:%02d", hour, minute))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                draftTask = makeNewTask(hour: hour, minute: minute)
                showAddTaskMenu = false
            } label: {
                Label(String(localized: "Add task"), systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(String(localized: "Cancel"), role: .cancel) {
                showAddTaskMenu = false
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(minWidth: 160, alignment: .leading)
    }

    private func makeNewTask(hour: Int, minute: Int) -> TodoTask {
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        let task = TodoTask()
        task.deadLine = calendar.date(from: components) ?? now
        return task
    }

    private var dayOptionsPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Timeline interval"))
                    .font(.subheadline.weight(.medium))

                Picker(
                    String(localized: "Timeline interval"),
                    selection: timelineIntervalBinding
                ) {
                    Text(String(localized: "30 minutes")).tag(30)
                    Text(String(localized: "1 hour")).tag(60)
                    Text(String(localized: "2 hours")).tag(120)
                }
                .pickerStyle(.menu)
            }
            
            Divider()
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "Row height"))
                    Spacer()
                    Text("\(Int(settings.dayEmptySlotHeight)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: emptySlotHeightBinding, in: 44...80, step: 2)
                    .accessibilityLabel(String(localized: "Row height"))
            }
            Divider()
            
            Toggle(isOn: hideNightHoursBinding) {
                Text(String(localized: "Hide empty night hours (00:00–06:00)"))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(minWidth: 260, alignment: .leading)
    }

    private func normalizedTimelineInterval(_ value: Int) -> Int {
        switch value {
        case 120: return 120
        case 60: return 60
        default: return 30
        }
    }

    private var emptySlotHeightBinding: Binding<Double> {
        Binding(
            get: { max(44, settings.dayEmptySlotHeight) },
            set: { settings.dayEmptySlotHeight = $0 }
        )
    }

    private var timelineIntervalBinding: Binding<Int> {
        Binding(
            get: { settings.dayTimelineIntervalMinutes },
            set: { settings.dayTimelineIntervalMinutes = $0 }
        )
    }

    private var hideNightHoursBinding: Binding<Bool> {
        Binding(
            get: { settings.dayHideEmptyNightHours },
            set: { settings.dayHideEmptyNightHours = $0 }
        )
    }

    private var dateStrip: some View {
        let dates = (-3...3).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: selectedDate)
        }

        return HStack(spacing: 5) {
            ForEach(dates, id: \.self) { date in
                let dateTasks = tasks.filter { task in
                    guard let deadline = task.deadLine else { return false }
                    return calendar.isDate(deadline, inSameDayAs: date)
                }
                let isToday = calendar.isDateInToday(date)
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)

                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedDate = calendar.startOfDay(for: date)
                    }
                } label: {
                    VStack(spacing: 5) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(isToday ? .primary : .secondary)
                        Text(date.formatted(.dateTime.day()))
                            .font(.body.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isToday ? .white : .primary)
                            .frame(width: 34, height: 34)
                            .background {
                                if isToday {
                                    Circle().fill(Color.blue)
                                } else if isSelected {
                                    Circle().stroke(Color.primary, lineWidth: 1.5)
                                }
                            }
                        Circle()
                            .fill(dayIndicatorColor(for: dateTasks))
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    let horizontal = value.translation.width
                    guard abs(horizontal) > 35 else { return }
                    let velocity = abs(value.predictedEndTranslation.width - horizontal)
                    let baseDays = max(1, Int(abs(horizontal) / 80))
                    let acceleratedDays = min(31, baseDays + Int(velocity / 180))
                    let dayDelta = horizontal < 0 ? acceleratedDays : -acceleratedDays
                    guard let newDate = calendar.date(byAdding: .day, value: dayDelta, to: selectedDate) else { return }
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedDate = calendar.startOfDay(for: newDate)
                    }
                }
        )
    }

    private func tasks(in hour: Int, minute: Int) -> [TodoTask] {
        timedTasks.filter { task in
            guard let deadline = task.deadLine else { return false }
            let components = calendar.dateComponents([.hour, .minute], from: deadline)
            guard let taskHour = components.hour, let taskMinute = components.minute else { return false }
            let interval = normalizedTimelineInterval(settings.dayTimelineIntervalMinutes)
            let taskSlot = ((taskHour * 60 + taskMinute) / interval) * interval
            return taskSlot == hour * 60 + minute
        }
    }

    private func taskRow(_ task: TodoTask) -> some View {
        let isOverdue = !task.isCompleted && (task.deadLine.map { $0 < .now } ?? false)
        let criticalColor = Color(hex: settings.highlightColorHex) ?? .red

        return NavigationLink(value: task) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(task.priority == .critical ? criticalColor : Color.clear)
                    .frame(width: 3)
                    .padding(.vertical, 2)

                Image(systemName: task.mainTag?.mainIcon ??  task.status.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(
                        settings.iconStyle == .monochrome
                            ? Color.primary
                            : (task.mainTag?.color ?? task.status.color)
                    )
                    .frame(width: 20, height: 20, alignment: .center)
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    if let deadline = task.deadLine {
                        HStack(spacing: 10) {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundStyle(isOverdue ? Color.red : Color.blue)
                            Text(deadline.formatted(.dateTime.hour().minute()))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(isOverdue ? Color.red : Color.blue)

                            if let reminderMinutes = task.reminderOffsetMinutes, reminderMinutes > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "bell")
                                    Text(formattedReminderOffset(for: reminderMinutes))
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(
                                    String(localized: "Reminder") + ": " + formattedReminderOffset(for: reminderMinutes)
                                )
                            }
                        }
                    }

                    Text(task.title.isEmpty ? String(localized: "Untitled task") : task.title)
                        .font(.subheadline)
                        .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
                        .underline(isOverdue, color: .red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.bottom, 8)

                Spacer(minLength: 4)

                HStack(spacing: 7) {
                    if task.mainTag != nil, let priorityIcon = task.priority.systemImage {
                        Image(systemName: priorityIcon)
                            .foregroundStyle(task.mainTag?.color ?? .secondary)
                            .accessibilityLabel(String(localized: "Priority"))
                    }

                    if task.hasVisibleTaskAttachments {
                        Image(systemName: "paperclip")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(String(localized: "Attachments"))
                    }

                    if task.locationName != nil || task.locationCoordinate != nil {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(String(localized: "Location"))
                    }

                }
                .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .frame(height: max(44, settings.dayEmptySlotHeight), alignment: .center)
            .contentShape(Rectangle())
            .opacity(task.isCompleted ? 0.55 : 1)
            .strikethrough(task.isCompleted, color: .secondary)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                requestDeletion(of: task)
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
            Button {
                toggleCompleted(task)
            } label: {
                Label(task.isCompleted ? String(localized: "To do") : String(localized: "Complete"), systemImage: task.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
            }
            if task.deadLine != nil {
                Button {
                    TaskSingleCalendarExport.shared.present(for: task)
                } label: {
                    Label(String(localized: "Add to Calendar"), systemImage: "calendar.badge.plus")
                }
            }
            TaskRescheduleMenu(task: task)
            if let deadline = task.deadLine, deadline < .now {
                Menu {
                    snoozeButton(task, minutes: 5, title: String(localized: "5 minutes"), icon: "5.arrow.trianglehead.clockwise")
                    snoozeButton(task, minutes: 15, title: String(localized: "15 minutes"), icon: "15.arrow.trianglehead.clockwise")
                    snoozeButton(task, minutes: 30, title: String(localized: "30 minutes"), icon: "30.arrow.trianglehead.clockwise")
                    snoozeButton(task, minutes: 60, title: String(localized: "1 hour"), icon: "60.arrow.trianglehead.clockwise")
                    snoozeButton(task, minutes: 180, title: String(localized: "3 hours"), icon: "plus.arrow.trianglehead.clockwise")
                } label: {
                    Label(String(localized: "Snooze"), systemImage: "timer")
                }
            }
            Menu {
                duplicateButton(task, includingAttachments: false, title: String(localized: "Task"), icon: "text.badge.checkmark")
                if task.hasVisibleTaskAttachments {
                    duplicateButton(task, includingAttachments: true, title: String(localized: "Task & Attachments"), icon: "rectangle.and.paperclip")
                }
            } label: {
                Label(String(localized: "Duplicate"), systemImage: "plus.square.on.square")
            }
        }
    }
    private func formattedReminderOffset(for minutes: Int) -> String {
        if minutes < 60 {
            return String(localized: "\(minutes) minutes before")
        }

        if minutes < 1440 {
            let hours = minutes / 60
            return String(localized: "\(hours) hours before")
        }

        let days = minutes / 1440
        let hours = (minutes % 1440) / 60

        if hours > 0 {
            return String(localized: "\(days) days and \(hours) hours before")
        }

        return String(localized: "\(days) days before")
    }

    @MainActor
    private func hasFutureOccurrenceForDeletion(_ task: TodoTask) -> Bool {
        guard !task.isCompleted else { return false }
        do {
            return try RecurrenceEngine.hasFutureOccurrence(for: task, in: modelContext)
        } catch {
            AppLogger.persistence.error(
                "TaskDay future occurrence check failed: \\(error.localizedDescription)"
            )
            return false
        }
    }

    @MainActor
    private func deleteTaskAndRefresh(_ task: TodoTask) {
        deleteTask(task, in: modelContext)
        modelContext.processPendingChanges()
        NotificationCenter.default.post(name: .taskDidChange, object: nil)
    }

    @MainActor
    private func requestDeletion(of task: TodoTask) {
        let hasFutureOccurrence = task.recurrenceID != nil && hasFutureOccurrenceForDeletion(task)
        if hasFutureOccurrence || settings.confirmTaskDeletion {
            taskPendingDeletion = task
            showDeleteConfirmation = true
        } else {
            deleteTaskAndRefresh(task)
        }
    }

    private func toggleCompleted(_ task: TodoTask) {
        setCompletion(task, isCompleted: !task.isCompleted)
    }

    private func setCompletion(_ task: TodoTask, isCompleted: Bool) {
        guard task.isCompleted != isCompleted else { return }

        let wasCompleted = task.isCompleted

        if task.recurrenceRule != nil {
            guard task.occurrenceIndex != nil else {
                NotificationCenter.default.post(name: Notification.Name("DashboardOpenList"), object: nil)
                return
            }

            if isCompleted {
                task.completeRecurringTask()
            } else {
                // Reopening an occurrence must reverse its completion state;
                // calling completeRecurringTask() again would not reopen it.
                task.isCompleted = false
                task.completedAt = nil
            }
        } else {
            task.isCompleted = isCompleted
            task.completedAt = isCompleted ? .now : nil
            if isCompleted { task.snoozeUntil = nil }
        }

        modelContext.processPendingChanges()
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .taskDidChange, object: nil)
            RecurrenceCompletionNotice.postIfNeeded(for: task, wasCompleted: wasCompleted)
            Task { @MainActor in _ = await ForMemoAlarmManager.shared.synchronize(task: task) }
            NotificationManager.shared.refresh(force: false)
        } catch {
            AppLogger.persistence.error("Day view task update failed: \(error.localizedDescription)")
        }
    }

    private func snoozeButton(_ task: TodoTask, minutes: Int, title: String, icon: String) -> some View {
        Button {
            NotificationActionProcessor.shared.applyManualSnooze(to: task, interval: TimeInterval(minutes * 60), using: modelContext)
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private func duplicateButton(_ task: TodoTask, includingAttachments: Bool, title: String, icon: String) -> some View {
        Button {
            do {
                _ = try TaskDuplicationService.duplicate(task, using: modelContext, includingAttachments: includingAttachments)
                NotificationCenter.default.post(name: .taskDidChange, object: nil)
            } catch {
                AppLogger.persistence.error("Day view task duplication failed: \(error.localizedDescription)")
            }
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private func dayIndicatorColor(for tasks: [TodoTask]) -> Color {
        guard !tasks.isEmpty else { return .clear }

        let now = Date()
        let hasOverdueTasks = tasks.contains {
            !$0.isCompleted && (($0.deadLine ?? .distantFuture) < now)
        }
        if hasOverdueTasks { return .red }

        if tasks.allSatisfy(\.isCompleted) { return .green }
        if tasks.contains(where: { !$0.isCompleted }) { return .blue }
        return .clear
    }
}
