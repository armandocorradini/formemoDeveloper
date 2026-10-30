import SwiftUI
import SwiftData
import os
import UIKit

struct TaskDayView: View {
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var openSwipeTaskID: String?
    @State private var selectedTaskForNavigation: TodoTask?
    @State private var foregroundRefreshDate = Date.now
    @State private var dateStripHoldTask: Task<Void, Never>?
    @State private var dateStripDidHoldEdge = false
    @State private var taskRowFrames: [String: CGRect] = [:]
    @State private var centralizedSwipeDrag: TaskDaySwipeDrag?
    @State private var centralizedSwipeAxis: TaskDaySwipeAxis?

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
            guard calendar.isDate(deadline, inSameDayAs: selectedDate) else { return false }
            return !settings.dayHideCompletedTasks || !task.isCompleted
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

    private var hasOverdueTasks: Bool {
        tasks.contains { task in
            guard let deadline = task.deadLine else { return false }
            return calendar.isDate(deadline, inSameDayAs: selectedDate)
                && deadline < .now
                && !task.isCompleted
        }
    }
    
    private var hasOverdueTasksInPreviousDays: Bool {
        let startOfSelectedDay = calendar.startOfDay(for: selectedDate)
        let now = Date.now

        return tasks.contains { task in
            guard let deadline = task.deadLine else { return false }
            return deadline < now
                && deadline < startOfSelectedDay
                && !task.isCompleted
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            dateStrip
                .padding(.bottom,20)
            Rectangle()
                .fill(hasOverdueTasksInPreviousDays ? Color.red : Color.clear)
                .frame(
                    height: UIDevice.current.userInterfaceIdiom == .pad ? 1.0 : 0.2)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)

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
                                    .frame(width: 52, height: 16, alignment: .trailing)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(format: String(localized: "Add task at %@"), String(format: "%02d:%02d", hour, minute)))

                            VStack(alignment: .leading, spacing: slotTasks.isEmpty ? 0 : 1) {
                                Button {
                                    selectTimelineSlot(slotMinutes)
                                } label: {
                                    ZStack {
                                        Rectangle().fill(Color.clear)
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.32))
                                            .frame(height: 1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 16)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(format: String(localized: "Add task at %@"), String(format: "%02d:%02d", hour, minute)))

                                if slotTasks.isEmpty {
                                    Color.clear
                                        .frame(height: max(0, settings.dayEmptySlotHeight - 16))
                                } else {
                                    ForEach(Array(slotTasks.enumerated()), id: \.element.id) { item in
                                        taskRow(item.element)
                                        if item.offset < slotTasks.count - 1 {
                                            Rectangle()
                                                .fill(Color.secondary.opacity(0.2))
                                                .frame(height: 1)
                                                .padding(.leading, 27)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: settings.dayEmptySlotHeight, alignment: .topLeading)
                        }
                        .anchorPreference(key: TimelineSlotBoundsKey.self, value: .bounds) {
                            [slotMinutes: $0]
                        }
                        .padding(.horizontal, 10)
                        .popover(
                            isPresented: addTaskPopoverBinding(for: slotMinutes),
                            attachmentAnchor: .point(.center),
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
            .coordinateSpace(name: "TaskDayScrollSpace")
            .onPreferenceChange(TaskDaySwipeRowBoundsKey.self) { taskRowFrames = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .named("TaskDayScrollSpace"))
                    .onChanged { value in
                        let horizontal = abs(value.translation.width)
                        let vertical = abs(value.translation.height)

                        // Lock the gesture to one axis. Vertical scrolling must not
                        // publish drag snapshots to every task row.
                        if centralizedSwipeAxis == nil {
                            guard max(horizontal, vertical) >= 14 else { return }

                            if vertical >= horizontal * 1.2 {
                                centralizedSwipeAxis = .vertical
                                return
                            }

                            guard horizontal >= vertical * 1.35 else { return }
                            centralizedSwipeAxis = .horizontal
                        }

                        guard centralizedSwipeAxis == .horizontal else { return }

                        let taskID = centralizedSwipeDrag?.isEnded == false
                            ? centralizedSwipeDrag?.taskID
                            : taskRowFrames.first(where: { $0.value.contains(value.startLocation) })?.key
                        guard let taskID else { return }

                        centralizedSwipeDrag = TaskDaySwipeDrag(
                            taskID: taskID,
                            startLocation: value.startLocation,
                            translation: value.translation,
                            isEnded: false
                        )
                    }
                    .onEnded { value in
                        defer { centralizedSwipeAxis = nil }

                        guard centralizedSwipeAxis == .horizontal,
                              let taskID = centralizedSwipeDrag?.taskID else {
                            centralizedSwipeDrag = nil
                            return
                        }

                        centralizedSwipeDrag = TaskDaySwipeDrag(
                            taskID: taskID,
                            startLocation: value.startLocation,
                            translation: value.translation,
                            isEnded: true
                        )

                        Task { @MainActor in
                            await Task.yield()
                            centralizedSwipeDrag = nil
                        }
                    }
            )
            .backgroundPreferenceValue(TimelineSlotBoundsKey.self) { anchors in
                TimelineView(.periodic(from: .now, by: 60)) { timelineContext in
                    GeometryReader { proxy in
                        currentTimeIndicator(
                            in: proxy,
                            anchors: anchors,
                            now: max(timelineContext.date, foregroundRefreshDate)
                        )
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                foregroundRefreshDate = .now
            }
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
                        Text(selectedDate.formatted(.dateTime.month(.wide).year(.twoDigits)).capitalized)
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(minWidth: 160, minHeight: 44)
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
        .navigationDestination(item: $selectedTaskForNavigation) { task in
            TaskDetailView(task: task)
        }
    }

    @ViewBuilder
    private func currentTimeIndicator(
        in proxy: GeometryProxy,
        anchors: [Int: Anchor<CGRect>],
        now: Date
    ) -> some View {
        let nowMinutes = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        let interval = normalizedTimelineInterval(settings.dayTimelineIntervalMinutes)
        let lowerSlot = (nowMinutes / interval) * interval
        let upperSlot = lowerSlot + interval
        let isToday = calendar.isDate(selectedDate, inSameDayAs: now)

        if isToday,
           nowMinutes < 24 * 60,
           let lowerAnchor = anchors[lowerSlot],
           let upperAnchor = anchors[upperSlot] {
            let lowerY = proxy[lowerAnchor].minY
            let upperY = proxy[upperAnchor].minY
            let fraction = CGFloat(nowMinutes - lowerSlot) / CGFloat(interval)
            let y = lowerY + (upperY - lowerY) * fraction

            ZStack(alignment: .leading) {
//                Rectangle()
//                    .fill(Color.red)
//                    .frame(height: 3.5)
//                    .frame(width: 54)
//                    .offset(x: 8, y: y-3.5)
                Rectangle()
                    .fill(hasOverdueTasks ? Color.red : Color.blue)
                    .frame(height: 1.5)
                    .frame(width: 54)
                    .offset(x: 8, y: y)

//                Circle()
//                    .fill(Color.blue)
//                    .frame(width: 8, height: 8)
//                    .offset(x: 4, y: y - 3)
            }
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

            let slotDate = calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: selectedDate
            ) ?? selectedDate
            let isPastDateTime = slotDate < .now

            Text(String(format: "%02d:%02d", hour, minute))
                .font(.caption)
                .foregroundStyle(isPastDateTime ? .red : .blue)

            Button {
                draftTask = makeNewTask(hour: hour, minute: minute)
                showAddTaskMenu = false
            } label: {
                Label {
                    Text(String(localized: "Add task"))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

//            Button(String(localized: "Cancel"), role: .cancel) {
//                showAddTaskMenu = false
//            }
//            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(minWidth: 160, alignment: .leading)
    }

    private func makeNewTask(hour: Int, minute: Int) -> TodoTask {
        var components = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        components.hour = hour
        components.minute = minute
        components.second = 0

        let task = TodoTask()
        task.deadLine = calendar.date(from: components) ?? selectedDate
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

            Toggle(isOn: hideCompletedTasksBinding) {
                Text(String(localized: "Hide completed tasks"))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    private var hideCompletedTasksBinding: Binding<Bool> {
        Binding(
            get: { settings.dayHideCompletedTasks },
            set: { settings.dayHideCompletedTasks = $0 }
        )
    }

    private var dateStrip: some View {
        GeometryReader { geometry in
            let dates = (-3...3).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: selectedDate)
            }

            HStack(spacing: 5) {
                ForEach(Array(dates.enumerated()), id: \.element) { _, date in
                    let dateTasks = tasks.filter { task in
                        guard let deadline = task.deadLine else { return false }
                        guard calendar.isDate(deadline, inSameDayAs: date) else { return false }
                        return !settings.dayHideCompletedTasks || !task.isCompleted
                    }
                    let isToday = calendar.isDateInToday(date)
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)

                    Button {
                        if dateStripDidHoldEdge {
                            dateStripDidHoldEdge = false
                            return
                        }
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedDate = calendar.startOfDay(for: date)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Text(date.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2)
                                .foregroundStyle(calendar.component(.weekday, from: date) == 1 ? .red : (isToday ? .primary : .secondary))
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let edgeWidth = min(54, geometry.size.width * 0.18)
                        let direction: Int
                        if value.startLocation.x <= edgeWidth {
                            direction = -1
                        } else if value.startLocation.x >= geometry.size.width - edgeWidth {
                            direction = 1
                        } else {
                            return
                        }
                        handleDateStripEdgePress(direction: direction, isPressing: true)
                    }
                    .onEnded { _ in
                        handleDateStripEdgePress(direction: 0, isPressing: false)
                    }
            )
        }
        .frame(height: 65)
        .onDisappear {
            dateStripHoldTask?.cancel()
            dateStripHoldTask = nil
        }
    }

    private func handleDateStripEdgePress(direction: Int, isPressing: Bool) {
        if isPressing {
            guard dateStripHoldTask == nil else { return }
            dateStripHoldTask = Task { @MainActor in
                do {
                    // Wait briefly so a normal tap remains a tap.
                    try await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    dateStripDidHoldEdge = true

                    while !Task.isCancelled {
                        withAnimation(.linear(duration: 0.16)) {
                            if let nextDate = calendar.date(
                                byAdding: .day,
                                value: direction,
                                to: selectedDate
                            ) {
                                selectedDate = calendar.startOfDay(for: nextDate)
                            }
                        }
                        try await Task.sleep(for: .milliseconds(240))
                    }
                } catch {
                    // Cancellation is expected when the finger is released.
                }
            }
        } else {
            dateStripHoldTask?.cancel()
            dateStripHoldTask = nil
            // Keep the flag briefly so the Button action generated by a long press
            // cannot jump the selection to the edge date after the repeated scrolling.
            if dateStripDidHoldEdge {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    dateStripDidHoldEdge = false
                }
            }
        }
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

        return TaskDaySwipeRow(
            taskID: String(describing: task.persistentModelID),
            rowHeight: max(44, settings.dayEmptySlotHeight),
            completionTitle: String(localized: task.isCompleted ? "To do" : "Complete"),
            completionIcon: task.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle",
            openRowID: $openSwipeTaskID,
            dragSnapshot: centralizedSwipeDrag,
            onComplete: { toggleCompleted(task) },
            onDelete: { requestDeletion(of: task) }
        ) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(task.priority == .critical ? criticalColor : Color.clear)
                    .frame(width: 3)
                    .padding(.vertical, 2)

                Image(systemName: task.mainTag?.mainIcon ?? task.status.icon)
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(settings.iconStyle == .monochrome ? .monochrome : .palette)
                    .foregroundStyle(
                        settings.iconStyle == .monochrome
                            ? Color.primary
                            : (task.mainTag?.color ?? task.status.color),
                        .primary
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
//                .padding(.bottom, 8)

                Spacer(minLength: 4)

                HStack(spacing: 7) {
                    if task.mainTag != nil, let priorityIcon = task.priority.systemImage {
                        Image(systemName: priorityIcon)
                            .foregroundStyle(task.priority == .critical ? Color.red : (task.mainTag?.color ?? .secondary))
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
            .contentShape(Rectangle())
            .onTapGesture {
                if openSwipeTaskID != nil {
                    openSwipeTaskID = nil
                    return
                }
                selectedTaskForNavigation = task
            }
        .contextMenu {
            Button(role: .destructive) {
                requestDeletion(of: task)
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
            
            Divider()
            
            Button {
                toggleCompleted(task)
            } label: {
                Label(
                    task.isCompleted ? String(localized: "To do") : String(localized: "Complete"),
                    systemImage: task.isCompleted
                        ? "arrow.uturn.backward.circle"
                        : "checkmark.circle"
                )
            
            }
            .tint(.green)
            
            if task.deadLine != nil {
                Button {
                    TaskSingleCalendarExport.shared.present(for: task)
                } label: {
                    Label(String(localized: "Add to Calendar Apple"), systemImage: "calendar.badge.plus")
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


private enum TaskDaySwipeAxis {
    case horizontal
    case vertical
}

private struct TaskDaySwipeDrag: Equatable {
    let taskID: String
    let startLocation: CGPoint
    let translation: CGSize
    let isEnded: Bool
}

private struct TaskDaySwipeRowBoundsKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TimelineSlotBoundsKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [Int: Anchor<CGRect>],
        nextValue: () -> [Int: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TaskDaySwipeRow<Content: View>: View {
    let taskID: String
    let rowHeight: CGFloat
    let completionTitle: String
    let completionIcon: String
    @Binding var openRowID: String?
    let dragSnapshot: TaskDaySwipeDrag?
    let onComplete: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var swipeDirection: Int = 0
    @State private var gestureStartedWithClosedRow = false
    @State private var dragStartOffset: CGFloat = 0

    private let deleteRevealWidth: CGFloat = 60
    private let actionCapsuleHeight: CGFloat = 40
    private let completionCommitRatio: CGFloat = 0.42

    private func handleCentralizedDrag(_ snapshot: TaskDaySwipeDrag, rowWidth: CGFloat) {
        let horizontal = snapshot.translation.width
        let vertical = snapshot.translation.height

        // Vertical movement is left entirely to the ScrollView.
        guard abs(horizontal) > abs(vertical) * 1.15 else {
            if snapshot.isEnded {
                swipeDirection = 0
                gestureStartedWithClosedRow = false
                dragStartOffset = 0
            }
            return
        }

        if swipeDirection == 0, abs(horizontal) > 12 {
            swipeDirection = horizontal > 0 ? 1 : -1
            dragStartOffset = openRowID == taskID ? -deleteRevealWidth : 0
            gestureStartedWithClosedRow = dragStartOffset == 0
        }

        guard swipeDirection != 0 else { return }

        if !snapshot.isEnded {
            if dragStartOffset < 0 {
                offset = min(0, max(-deleteRevealWidth, dragStartOffset + horizontal))
            } else if horizontal < 0 {
                offset = max(-deleteRevealWidth, horizontal)
            } else {
                offset = min(rowWidth, horizontal)
            }
            return
        }

        let shouldComplete = swipeDirection == 1
            && gestureStartedWithClosedRow
            && horizontal > rowWidth * completionCommitRatio

        swipeDirection = 0
        gestureStartedWithClosedRow = false
        dragStartOffset = 0

        if shouldComplete {
            withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.12)) {
                offset = 0
                openRowID = nil
            }
            onComplete()
        } else if openRowID == taskID && horizontal > 24 {
            withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.12)) {
                offset = 0
                openRowID = nil
            }
        } else if horizontal < -44 {
            withAnimation(.snappy(duration: 0.22)) {
                offset = -deleteRevealWidth
                openRowID = taskID
            }
        } else {
            withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.12)) {
                offset = openRowID == taskID ? -deleteRevealWidth : 0
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Green action is a capsule revealed progressively beneath the row.
                HStack {
                    if offset > 0 {
                        Label(completionTitle, systemImage: completionIcon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 14)
                            .frame(height: actionCapsuleHeight)
                            .frame(width: min(max(0, offset - 12), min(geometry.size.width * 0.72, 180)))
                            .background(Color.green, in: Capsule())
                            .opacity(offset >= 76 ? 1 : 0.85)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: rowHeight)

                // The row's transparent surface reveals the glass background while sliding.
                content
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)
                    .offset(x: offset)
                    .contentShape(Rectangle())


                // Keep Delete above the shifted row so the capsule remains tappable.
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            offset = 0
                            if openRowID == taskID {
                                openRowID = nil
                            }
                        }
                        onDelete()
                    } label: {
                        Label(String(localized: ""), systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 15)
                            .frame(height: actionCapsuleHeight)
                            .background(Color.red, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(width: deleteRevealWidth, height: rowHeight)
                    .opacity(offset < -8 ? 1 : 0)
                    .allowsHitTesting(offset < -8)
                }
                .frame(height: rowHeight)
            }
            .clipped()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TaskDaySwipeRowBoundsKey.self,
                        value: [taskID: proxy.frame(in: .named("TaskDayScrollSpace"))]
                    )
                }
            }
            .onChange(of: dragSnapshot) { _, snapshot in
                guard let snapshot, snapshot.taskID == taskID else { return }
                handleCentralizedDrag(snapshot, rowWidth: geometry.size.width)
            }
            .onChange(of: openRowID) { _, newValue in
                if newValue != taskID {
                    withAnimation(.snappy(duration: 0.2)) {
                        offset = 0
                    }
                }
            }
        }
        .frame(height: rowHeight)
        .clipped()
    }
}
