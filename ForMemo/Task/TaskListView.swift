import SwiftUI
import SwiftData
import PhotosUI
import Observation

import WeatherKit
import CoreLocation
import os


extension Notification.Name {
    static let taskDidChange = Notification.Name("taskDidChange")
}

// MARK: - TaskTagFilter
enum TaskTagFilter: Hashable, Identifiable {
    case all
    case none
    case tag(TaskMainTag)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .none:
            return "none"
        case .tag(let tag):
            return tag.rawValue
        }
    }
}

// MARK: - TaskListView
struct TaskListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    
    @Query(filter: #Predicate<TodoTask> { !$0.isCompleted })
    private var todoQuery: [TodoTask]


    @State private var draftTask: TodoTask?

    private struct SelectedWeatherDay: Identifiable {
        let date: Date
        var id: Date { date }
    }

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var showCompleted = false

    @State private var showNewTask = false
    @State private var showQuickGuide = false
    @State private var showWeatherForecast = false
    @State private var selectedWeatherDay: SelectedWeatherDay?

    @State private var selectedTagFilter: TaskTagFilter = .all
    @State private var selectedPriorityFilter: TaskPriority? = nil
    @State private var selectedPeriodFilter: TaskPeriodFilter? = nil


    private var listStyleChoice: TaskListStyle {
        settings.taskListStyle
    }

    private var listStyleBinding: Binding<TaskListStyle> {
        Binding(
            get: { settings.taskListStyle },
            set: { settings.taskListStyle = $0 }
        )
    }

    private var showDateEveryRow: Bool {
        settings.showDateEveryRow
    }

    private var showDateEveryRowBinding: Binding<Bool> {
        Binding(
            get: { settings.showDateEveryRow },
            set: { settings.showDateEveryRow = $0 }
        )
    }

    @State private var taskPendingDeletion: TodoTask?

    @State private var filteredTodoTasksCache: [TodoTask] = []

    private var filteredTodoTasks: [TodoTask] {

        let now = Date()

        return todoQuery
            .filter { task in

                let matchesSearch =
                    debouncedSearchText.isEmpty ||
                    task.title.localizedCaseInsensitiveContains(debouncedSearchText)

                let matchesTag: Bool = {
                    switch selectedTagFilter {
                    case .all:
                        return true
                    case .none:
                        return task.mainTag == nil
                    case .tag(let tag):
                        return task.mainTag == tag
                    }
                }()

                let matchesPriority =
                    selectedPriorityFilter == nil ||
                    task.priority == selectedPriorityFilter

                let matchesPeriod =
                    selectedPeriodFilter == nil ||
                    selectedPeriodFilter?.matches(task.deadLine) == true

                return matchesSearch &&
                       matchesTag &&
                       matchesPriority &&
                       matchesPeriod
            }
            .sorted {

                let lhs = $0.deadLine ?? .distantFuture
                let rhs = $1.deadLine ?? .distantFuture

                let lhsOverdue = lhs < now
                let rhsOverdue = rhs < now

                if lhsOverdue != rhsOverdue {
                    return lhsOverdue
                }

                if lhs != rhs {
                    return lhs < rhs
                }

                return $0.id.uuidString < $1.id.uuidString
            }
    }


    var body: some View {
        ZStack {
            let todoTasks = filteredTodoTasksCache

            AppGlassBackground()
                    
            let isEmptyState =
                todoQuery.isEmpty &&
                !showCompleted &&
                !showNewTask
            
                listWithStyle {

                    List {

                        if isEmptyState {

                            EmptySectionView(showQuickGuide: $showQuickGuide)
                        }

                        if !todoTasks.isEmpty {
                            TodoSectionView(
                                taskPendingDeletion: $taskPendingDeletion,
                                openWeatherForecast: { date in
                                    selectedWeatherDay = SelectedWeatherDay(date: date)
                                },
                                tasks: todoTasks,
                                modelContext: modelContext
                            )
                        }

                        if showCompleted {
                            CompletedTasksContainerView(
                                taskPendingDeletion: $taskPendingDeletion,
                                modelContext: modelContext,
                                searchText: searchText,
                                selectedTagFilter: selectedTagFilter,
                                selectedPriorityFilter: selectedPriorityFilter,
                                selectedPeriodFilter: selectedPeriodFilter
                            )
                        }
                        
                    }
                    
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 80)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .alert(
                        "Delete task?",
                        isPresented: Binding(
                            get: { taskPendingDeletion != nil },
                            set: { if !$0 { taskPendingDeletion = nil } }
                        )
                    ) {



                        Button("Delete", role: .destructive) {

                            guard let task = taskPendingDeletion else {
                                taskPendingDeletion = nil
                                return
                            }

                            withAnimation {
                                deleteTask(task, in: modelContext)
                            }

                            taskPendingDeletion = nil
                        }
                        Button("Cancel", role: .cancel) {
                            taskPendingDeletion = nil
                        }
                    } message: {
                        Text("This action cannot be undone.")
                    }
                    .contentMargins(
                        .horizontal,
                        listStyleChoice == .plain
                        ? 0
                        : TaskRowMetrics.groupedLeadingPadding,
                        for: .scrollContent
                    )

                    .fullScreenCover(isPresented: $showQuickGuide) {
                        AppQuickGuideView()
                    }
                    .listRowSpacing(0)
                }
                .navigationDestination(for: TodoTask.self) { task in
                    TaskDetailView(task: task)
                }
                .scrollDismissesKeyboard(.immediately)

                }

        .onChange(of: scenePhase) { _, newPhase in

            if newPhase == .inactive {

                if showCompleted {
                    showCompleted = false
                }
                return
            }

        }
                .searchableIf(
                    !todoQuery.isEmpty || showCompleted,
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search task"
                )
                .onChange(of: searchText) { _, newValue in
                    let value = newValue
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        if value == searchText {
                            debouncedSearchText = value
                        }
                    }
                }
                .onAppear {
                    filteredTodoTasksCache = filteredTodoTasks
                    debouncedSearchText = searchText
                }
                .onChange(of: debouncedSearchText) { _, _ in
                    filteredTodoTasksCache = filteredTodoTasks
                }
                .onChange(of: todoQuery.count) { _, _ in
                    filteredTodoTasksCache = filteredTodoTasks
                }
                .onChange(of: selectedTagFilter) { _, _ in
                    filteredTodoTasksCache = filteredTodoTasks
                }
                .onChange(of: selectedPriorityFilter) { _, _ in
                    filteredTodoTasksCache = filteredTodoTasks
                }
                .onChange(of: selectedPeriodFilter) { _, _ in
                    filteredTodoTasksCache = filteredTodoTasks
                }
                .onReceive(

                    NotificationCenter.default.publisher(for: .taskDidChange)

                ) { _ in

                    filteredTodoTasksCache = filteredTodoTasks

                }
        
                .onReceive(
                    NotificationCenter.default.publisher(for: .taskDidChange)
                ) { _ in
                    filteredTodoTasksCache = filteredTodoTasks
                }
                        .toolbarBackground(.hidden, for: .navigationBar)
            
                        .navigationTitle(todoQuery.isEmpty && !showCompleted ? "" : String(localized:"My Tasks"))
                .navigationBarTitleDisplayMode(.inline)
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
                .sheet(item: $draftTask) { task in
                    NewTaskSheetView(draftTask: task)
                }

                .toolbar {

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.snappy) {
                                showCompleted.toggle()
                            }
                        } label: {
                            Image(systemName: showCompleted ? "eye.slash" : "eye")
                                .foregroundStyle(.blue.opacity(0.7))
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.snappy) {
                                draftTask = TodoTask()
                            }
                        } label: {
                            Image(systemName: draftTask == nil ? "plus.circle.fill" : "minus.circle.fill")
                                .foregroundStyle(draftTask == nil ? .green : .gray)
                                .font(.title2)
                        }
                    }
                    if !(todoQuery.isEmpty && !showCompleted) {
                        ToolbarItem(placement: .topBarLeading) {
                            Menu {
                                // Sezione per rimuovere tutti i filtri
                                if selectedTagFilter != .all || selectedPriorityFilter != nil || selectedPeriodFilter != nil {
                                    Button(role: .destructive) {
                                        selectedTagFilter = .all
                                        selectedPriorityFilter = nil
                                        selectedPeriodFilter = nil
                                    } label: {
                                        Label(
                                            String(localized: "Remove Filters"),
                                            systemImage: "line.3.horizontal.decrease.circle"
                                        )
                                    }

                                    Divider()
                                }

                                // MENU FILTRO TAG
                                // Usiamo un Picker per gestire la selezione "esclusiva" in modo nativo
                                Menu {
                                    Picker("Tags", selection: $selectedTagFilter) {

                                        Text("All")
                                            .tag(TaskTagFilter.all)

                                        Label("None", systemImage: "tag.slash")
                                            .tag(TaskTagFilter.none)

                                        ForEach(TaskMainTag.localizedSortedCases) { tag in
                                            Label(tag.localizedTitle, systemImage: tag.mainIcon)
                                                .tag(TaskTagFilter.tag(tag))
                                        }
                                    }
                                } label: {
                                    Label(
                                        String(localized: "Tags"),
                                        systemImage: "tag"
                                    )
                                }

                                // MENU FILTRO PRIORITÀ
                                Menu {
                                    Picker("Priority", selection: $selectedPriorityFilter) {
                                        Text("All").tag(nil as TaskPriority?)

                                        ForEach(TaskPriority.allCases) { priority in
                                            // Utilizziamo l'icona della priorità o una stringa vuota se nil
                                            Label(priority.localizedTitle, systemImage: priority.systemImage ?? "ellipsis")
                                                .tag(priority as TaskPriority?)
                                        }
                                    }
                                } label: {
                                    Label(
                                        String(localized: "Priority"),
                                        systemImage: "exclamationmark.circle"
                                    )
                                }

                                // MENU FILTRO PERIODO
                                Section {

                                    Button {
                                        selectedPeriodFilter = nil
                                    } label: {
                                        Label(
                                            "All",
                                            systemImage: selectedPeriodFilter == nil
                                            ? "checkmark"
                                            : "circle"
                                        )
                                    }

                                    ForEach(TaskPeriodFilter.allCases) { period in

                                        Button {
                                            selectedPeriodFilter = period
                                        } label: {
                                            Label(
                                                period.localizedTitle,
                                                systemImage: selectedPeriodFilter == period
                                                ? "checkmark"
                                                : period.systemImage
                                            )
                                        }
                                    }

                                } header: {
                                    Label(
                                        String(localized: "Period"),
                                        systemImage: "calendar"
                                    )
                                }

                            } label: {
                                // Icona principale del Filtro nella Toolbar
                                // Diventa blu se almeno un filtro è attivo
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .foregroundStyle(
                                        selectedTagFilter != .all ||
                                        selectedPriorityFilter != nil ||
                                        selectedPeriodFilter != nil
                                        ? .red
                                        : .primary.opacity(0.7)
                                    )
                            }

                        }

                    }



                    ToolbarItem(placement: .topBarLeading) {
                        Menu {

                            Section("Appearance") {

                                Picker("Style", selection: listStyleBinding) {

                                    Label("Plain", systemImage: "list.bullet")
                                        .tag(TaskListStyle.plain)

                                    Label("Grouped", systemImage: "square.on.square")
                                        .tag(TaskListStyle.grouped)
                                }
                            }

                            Section() {

                                Toggle(isOn: showDateEveryRowBinding) {

                                    Label(
                                        "Show Date On Every Row",
                                        systemImage: "calendar.day.timeline.left.circle"
                                    )
                                }
                            }

                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                    }
                }
        }
    

    @ViewBuilder
    private func listWithStyle<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {

        switch listStyleChoice {
        case .plain:
            content().listStyle(.plain)
        case .grouped:
            content().listStyle(.plain)
        }
    }
}


// MARK: - EmptySectionView
struct EmptySectionView: View {

    @Binding var showQuickGuide: Bool

    var body: some View {
        Section("") {

            ContentUnavailableView {
                VStack(spacing: 12) {
                    Text(String(localized:("Welcome!")))
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                        .padding(.top, 20)

                    Image(systemName: "checkmark.circle.dotted")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.cyan, .blue)
                    // animazione continua
                        .symbolEffect(.pulse, options: .repeating.speed(0.2))
                        .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 10)

                    Text(String(localized:"No Tasks"))
                        .font(.title2.bold())
                }
            } description: {
                VStack(alignment: .center, spacing: 12) {
                    Text("Get started with a few simple taps:")
                        .font(.subheadline.bold())
                        .padding(.top, 20)
                        .padding(.bottom, 4)
                        .foregroundStyle(.blue)
                        .lineLimit(2)
                    //                                .minimumScaleFactor(0.5) // Permette di ridursi fino al 50% della dimensione originale
                }
                Group {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "ellipsis")
                                .frame(width: 30)
                                .padding(.top, 4)
                                .padding(.trailing, -6)
                                .foregroundStyle(.primary)
                            VStack(alignment: .leading){
                                Text("switch your task view.")

                            }}

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                            //                                        .frame(width: 30)
                                .foregroundStyle(.green)
                            Text("add a new task to your list.")
                        }



                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "eye")
                            //                                        .frame(width: 30)
                                .foregroundStyle(.blue)
                            Text("show or hide completed tasks.")
                        }

                        Spacer()
                        HStack{
                            Spacer()
                            Button {
                                Task { @MainActor in
                                    showQuickGuide = true
                                }
                            } label: {
                                Label("Quick Guide", systemImage: "questionmark.circle")
                            }
                            .buttonStyle(.bordered)
                            .foregroundStyle(.blue)
                            Spacer()
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 320, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                }
            }
            .padding(.top, -20)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            
        }
    }
}


// MARK: - TaskRow

struct TaskRowAppearance {
    let iconStyle: TaskIconStyle

    let showBadge: Bool
    let showAttachments: Bool
    let showLocation: Bool
    let showPriority: Bool
    let showBadgeOnlyWithPriority: Bool

    let highlightEnabled: Bool
    let showTodayExpiredLabel: Bool

    let selectedRowStyle: Int
    let dueIconEffect: DueIconEffect
}

@MainActor
struct TaskRow: View {
    // Riceviamo il task direttamente. SwiftData gestisce la relazione in modo efficiente.
    let task: TodoTask
    let showDateColumn: Bool
    let appearance: TaskRowAppearance
    @Environment(AppSettings.self) private var settings
    private let now = Date()

    private var isToday: Bool {
        guard let d = task.deadLine else { return false }
        return Calendar.current.isDateInToday(d)
    }

    private var isOverdue: Bool {
        guard let d = task.deadLine else { return false }
        return d < now
    }

    private var isOverdueToday: Bool {
        guard let d = task.deadLine else { return false }
        return d < now && Calendar.current.isDateInToday(d)
    }

    private var dynamicRowHeight: CGFloat {
        max(
            1,
            TaskRowMetrics.rowHeight + CGFloat(settings.taskRowVerticalPadding)
        )
    }

    var rowStyleToUse: Int {
        appearance.selectedRowStyle
    }

    private var model: TaskRowDisplayModel {
        let shouldDisplayBadge =
            appearance.showBadge && (!appearance.showBadgeOnlyWithPriority || task.priority != .none)

        let attachments = task.attachments ?? []

        return TaskRowDisplayModel(
            id: task.persistentModelID,
            title: task.title,
            subtitle: task.taskDescription,
            mainIcon: task.mainTag?.mainIcon ?? task.status.icon,
            statusColor: task.status.color,
            hasValidAttachments: !attachments.isEmpty,
            hasLocation: task.locationName?.isEmpty == false,
            badgeText: task.daysRemainingBadgeText,
            prioritySystemImage: task.priority.systemImage,
            deadLine: task.deadLine,
            reminderOffsetMinutes: task.reminderOffsetMinutes,
            shouldShowBadge: shouldDisplayBadge,
            isCompleted: task.isCompleted,
            recurrenceRule: task.recurrenceRule, mainTag: task.mainTag
        )
    }

    var body: some View {
        rowContent
            .contentShape(Rectangle())
            .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
            .frame(minHeight: dynamicRowHeight)

            .buttonStyle(.plain)
    }

    private var rowContent: some View {
        content
            .background {
                navigationLink
            }
    }

    private var navigationLink: some View {
        NavigationLink(value: task) {
            EmptyView()
        }
        .opacity(0)
    }

    private var content: some View {
        TaskRowContent(
            model: model,
            iconStyle: appearance.iconStyle,
            showBadge: model.shouldShowBadge,
            showAttachments: appearance.showAttachments,
            showLocation: appearance.showLocation,
            showPriority: appearance.showPriority,
            showBadgeOnlyWithPriority: appearance.showBadgeOnlyWithPriority,
            rowStyle: TaskRowStyle(rawValue: rowStyleToUse) ?? .style0,
            showDateColumn: showDateColumn,
            highlightCriticalOverdue: appearance.highlightEnabled,
            showTodayExpiredLabel: appearance.showTodayExpiredLabel,
            dueIconEffect: appearance.dueIconEffect
        )
        .equatable()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(
            .trailing,
            rowStyleToUse == 0
            ? TaskRowMetrics.style0TrailingContentPadding
            : TaskRowMetrics.rowTrailingContentPadding
        )
    }
}

// MARK: - Period Filter

enum TaskPeriodFilter: String, CaseIterable, Identifiable {

    case noDeadline
    case today
    case tomorrow
    case dayAfterTomorrow
    case thisWeekend
    case nextWeekend
    case thisWeek
    case nextWeek
    case thisMonth

    var id: String { rawValue }

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .noDeadline:
            return "No Deadline"
        case .today:
            return "Today"
        case .tomorrow:
            return "Tomorrow"
        case .dayAfterTomorrow:
            return "Day After Tomorrow"
        case .thisWeekend:
            return "This Weekend"
        case .nextWeekend:
            return "Next Weekend"
        case .thisWeek:
            return "This Week"
        case .nextWeek:
            return "Next Week"
        case .thisMonth:
            return "This Month"
        }
    }

    var systemImage: String {
        switch self {
        case .noDeadline:
            return "clock.badge.questionmark"
        case .today:
            return "sun.max"
        case .tomorrow:
            return "sunrise"
        case .dayAfterTomorrow:
            return "calendar.badge.clock"
        case .thisWeekend:
            return "beach.umbrella"
        case .nextWeekend:
            return "calendar.badge.plus"
        case .thisWeek:
            return "calendar.badge"
        case .nextWeek:
            return "calendar.circle"
        case .thisMonth:
            return "calendar"
        }
    }

    func matches(_ date: Date?) -> Bool {

        if self == .noDeadline {
            return date == nil
        }

        guard let date else { return false }

        let calendar = Calendar.current
        let now = Date()

        switch self {

        case .today:
            return calendar.isDateInToday(date)

        case .tomorrow:
            return calendar.isDateInTomorrow(date)

        case .dayAfterTomorrow:

            guard let target = calendar.date(byAdding: .day, value: 2, to: now) else {
                return false
            }

            return calendar.isDate(date, inSameDayAs: target)

        case .thisWeekend:

            guard let weekend = calendar.nextWeekend(startingAfter: now) else {
                return false
            }

            return date >= weekend.start && date < weekend.end

        case .nextWeekend:

            guard let firstWeekend = calendar.nextWeekend(startingAfter: now),
                  let secondWeekend = calendar.nextWeekend(startingAfter: firstWeekend.end)
            else {
                return false
            }

            return date >= secondWeekend.start && date < secondWeekend.end

        case .thisWeek:

            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else {
                return false
            }

            return interval.contains(date)

        case .nextWeek:

            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: nextWeek)
            else {
                return false
            }

            return interval.contains(date)

        case .thisMonth:

            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .noDeadline:
            return false // already handled above, but required for completeness
        }
    }
}

// MARK: - List Style Enum
enum TaskListStyle: String, CaseIterable {
    case plain
    case grouped
    
    var localizedName: LocalizedStringKey {
        switch self {
        case .plain:
            return "Plain"
        case .grouped:
            return "Grouped"
        }
    }
    var iconName: String {
        switch self {
        case .plain:
            return "list.bullet"
        case .grouped:
            return "square.on.square"
        }
    }
}
extension View {
    @ViewBuilder
    func searchableIf(
        _ condition: Bool,
        text: Binding<String>,
        placement: SearchFieldPlacement = .navigationBarDrawer(displayMode: .automatic),
        prompt: LocalizedStringKey = "Search task"
    ) -> some View {
        if condition {
            self.searchable(
                text: text,
                placement: placement,
                prompt: prompt
            )
        } else {
            self
        }
    }
}
struct TodoSectionView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @State private var weatherManager = WeatherManager.shared
    @State private var locationAuthorizationStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus

    @ViewBuilder
    private func weatherCapsuleView(
        weather: DailyWeatherInfo,
        isTodayGroup: Bool
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: isTodayGroup
                  ? weatherManager.representativeSymbol(for: weather.date)
                  : weather.symbolName)
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
    
    @ViewBuilder
    private func groupedHeaderView(
        for group: GroupedSection
    ) -> some View {
        if let title = group.relativeTitle {
            let _ = weatherManager.refreshID
            let isTodayGroup = Calendar.current.isDateInToday(group.date)

            HStack(spacing: 10) {

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.82))

                Text("\(group.tasks.count)")
                    .font(.footnote.weight(.heavy))
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
                        openWeatherForecast(group.date)
                    } label: {
                        // Patch: use representative symbol for today, else weather.symbolName
                        weatherCapsuleView(
                            weather: weather,
                            isTodayGroup: isTodayGroup
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
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
            .padding(.horizontal, TaskRowMetrics.groupedLeadingPadding+4)
            .padding(.top, group.date == groupedTasksByDay.first?.date ? 4 : 8)
            .padding(.bottom, TaskRowMetrics.weeklyVerticalPadding - 4) //questo alza o abbssa l'intestazione capsula (oggi, domani, ....) rispetto alla row sottostante
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
    private func relativeHeaderTitle(for date: Date) -> LocalizedStringKey? {

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)

        guard let days = calendar.dateComponents([.day], from: today, to: target).day else {
            return nil
        }

        switch days {
        case -2:
            return "Day Before Yesterday"
        case -1:
            return "Yesterday"
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
    private var listStyleChoice: TaskListStyle {
        settings.taskListStyle
    }
    private var confirmTaskDeletion: Bool {
        settings.confirmTaskDeletion
    }
    @Binding var taskPendingDeletion: TodoTask?
    let openWeatherForecast: (Date) -> Void

    let tasks: [TodoTask]
    let modelContext: ModelContext

    private struct GroupedSection: Identifiable, Equatable {
        let date: Date
        let tasks: [TodoTask]
        let relativeTitle: LocalizedStringKey?
        let isUpcomingBoundary: Bool
        let upcomingTasksCount: Int

        var id: Date { date }
    }

    @State private var groupedTasksCache: [GroupedSection] = []
    
    @State private var visibleLimit = 100

    private var visibleGroups: [GroupedSection] {

        guard visibleLimit > 0 else { return [] }

        var renderedRows = 0
        var result: [GroupedSection] = []

        for group in groupedTasksCache {

            if renderedRows >= visibleLimit {
                break
            }

            let remaining = visibleLimit - renderedRows
            let visibleTasks = Array(group.tasks.prefix(remaining))

            guard !visibleTasks.isEmpty else { continue }

            result.append(
                GroupedSection(
                    date: group.date,
                    tasks: visibleTasks,
                    relativeTitle: group.relativeTitle,
                    isUpcomingBoundary: group.isUpcomingBoundary,
                    upcomingTasksCount: group.upcomingTasksCount
                )
            )

            renderedRows += visibleTasks.count
        }

        return result
    }
    
    
    private func rebuildGroups() {
        let calendar = Calendar.current

        let grouped = Dictionary(grouping: tasks) { task in
            calendar.startOfDay(for: task.deadLine ?? .distantFuture)
        }

        let sortedGroups = grouped
            .map { key, value in
                (
                    date: key,
                    tasks: value.sorted {
                        let lhs = $0.deadLine ?? .distantFuture
                        let rhs = $1.deadLine ?? .distantFuture

                        if lhs != rhs {
                            return lhs < rhs
                        }

                        return $0.id.uuidString < $1.id.uuidString
                    }
                )
            }
            .sorted { $0.date < $1.date }

        var result: [GroupedSection] = []

        for index in sortedGroups.indices {

            let group = sortedGroups[index]

            let relativeTitle = relativeHeaderTitle(for: group.date)

            let isUpcomingBoundary: Bool = {

                guard index > 0 else {
                    return false
                }

                let previousRelativeTitle =
                    relativeHeaderTitle(
                        for: sortedGroups[index - 1].date
                    )

                return previousRelativeTitle != nil &&
                       relativeTitle == nil

            }()

            let upcomingTasksCount: Int = {

                guard isUpcomingBoundary else {
                    return 0
                }

                return sortedGroups[index...]
                    .reduce(0) { $0 + $1.tasks.count }

            }()

            result.append(
                GroupedSection(
                    date: group.date,
                    tasks: group.tasks,
                    relativeTitle: relativeTitle,
                    isUpcomingBoundary: isUpcomingBoundary,
                    upcomingTasksCount: upcomingTasksCount
                )
            )
        }
        groupedTasksCache = result

    }

    private var groupedTasksByDay: [GroupedSection] {

        if tasks.count <= visibleLimit {
            return groupedTasksCache
        }

        return visibleGroups
    }

    private var showDateEveryRow: Bool {
        settings.showDateEveryRow
    }


    var body: some View {

        Group {

            if listStyleChoice == .grouped {

            HStack {

                Text(String(localized: "To do (\(tasks.count))"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.9))

                Spacer()
            }
            .padding(.horizontal, TaskRowMetrics.groupedLeadingPadding + 4)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

                ForEach(Array(groupedTasksByDay.enumerated()), id: \.element.date) { groupIndex, group in

                    if group.isUpcomingBoundary {
                        let upcomingTasksCount = group.upcomingTasksCount

                    HStack(spacing: 10) {

                        Text(String(localized: "Upcoming"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary.opacity(0.82))

                        Text("\(upcomingTasksCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.primary.opacity(0.82))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(.clear)
                                    .glassEffect(.clear)
                            }
                    }
                    .padding(.horizontal, 14)
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
                    .padding(.leading, TaskRowMetrics.groupedLeadingPadding - 7)
                    .padding(.top, group.date == groupedTasksByDay.first?.date ? 4 : 8)
                    .padding(.bottom, TaskRowMetrics.weeklyVerticalPadding - 10)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, t in
                        let isLastVisibleRow =
                            group.date == groupedTasksByDay.last?.date &&
                            index == group.tasks.indices.last

                        taskRow(
                            for: t,
                            position: TaskRowPosition.position(
                                index: index,
                                total: group.tasks.count
                            )
                        )
                        .onAppear {
                            guard isLastVisibleRow else { return }
                            guard visibleLimit < tasks.count else { return }

                            visibleLimit = min(
                                visibleLimit + 100,
                                tasks.count
                            )
                        }
                    }

                } header: {

                    groupedHeaderView(for: group)

                }
                .listSectionSeparator(.hidden)
                .listSectionSpacing(TaskRowMetrics.weeklyVerticalPadding / 2)  //anche questo per lo spazio tra le row
            }
            .environment(\.defaultMinListRowHeight, 1)


        } else {

            Section(String(localized:"To do (\(tasks.count))")) {

                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, t in

                    let previousTaskDate = index > 0
                        ? Calendar.current.startOfDay(
                            for: tasks[index - 1].deadLine ?? .distantFuture
                        )
                        : nil

                    let currentTaskDate = Calendar.current.startOfDay(
                        for: t.deadLine ?? .distantFuture
                    )

                    let startsNewDayGroup = previousTaskDate != currentTaskDate

                    taskRow(
                        for: t,
                        position: startsNewDayGroup ? .first : .middle
                    )
                }
            }
        }
        }
        .task {

            rebuildGroups()

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 15
            ) {

                Task {
                    await weatherManager.refreshIfNeeded()
                }
            }
        }
        .onChange(of: tasks.count) { _, _ in

            rebuildGroups()

            if tasks.count < visibleLimit {
                visibleLimit = max(100, tasks.count)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .taskDidChange
            )
        ) { _ in

            rebuildGroups()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .locationPermissionChanged
            )
        ) { _ in
            locationAuthorizationStatus = CLLocationManager().authorizationStatus
        }
       
    }
    @ViewBuilder
    private func taskRow(for t: TodoTask, position: TaskRowPosition) -> some View {

        TaskRow(
            task: t,
            showDateColumn:
                showDateEveryRow
                ? true
                : (position == .first || position == .single),
            appearance: .current(from: settings)
        )

        .modifier(
            RowCardStyle(
                task: t,
                style: listStyleChoice,
                position: position,
                opacity: 1
            )
        )

        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                withAnimation(.snappy(duration: 0.30, extraBounce: 0.02)) {
                    toggleCompleted(t)
                }
            } label: {
                Label("Completed", systemImage: "checkmark.circle")
            }
            .tint(.green)
        }

        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                if confirmTaskDeletion {
                    taskPendingDeletion = t
                } else {
                    withAnimation(.snappy(duration: 0.26, extraBounce: 0.01)) {
                        deleteTask(t, in: modelContext)
                    }

                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                if confirmTaskDeletion {
                    DispatchQueue.main.async {
                        taskPendingDeletion = t
                    }
                } else {
                    withAnimation {
                        deleteTask(t, in: modelContext)
                        NotificationCenter.default.post(
                            name: .taskDidChange,
                            object: nil
                        )
                    }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                toggleCompleted(t)
            } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
            Menu {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        postpone(t, byHours: 1)
                    }
                } label: {
                    Label("+1 hour", systemImage: "clock.badge")
                }

                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        postpone(t, byHours: 3)
                    }
                } label: {
                    Label("+3 hours", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }

                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        postpone(t, byDays: 1)
                    }
                } label: {
                    Label("+1 day", systemImage: "sun.max")
                }

                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        postpone(t, byDays: 2)
                    }
                } label: {
                    Label("+2 days", systemImage: "calendar")
                }

                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        postpone(t, byDays: 3)
                    }
                } label: {
                    Label("+3 days", systemImage: "calendar.badge.clock")
                }
            } label: {
                Label("Reschedule", systemImage: "clock")
            }
            if let deadline = t.deadLine,

                deadline < Date() {
                Menu {
                    Button {
                        NotificationActionProcessor.shared.applyManualSnooze(
                            to: t,
                            interval: 5 * 60,
                            using: modelContext
                        )
                    } label: {
                        Label("5 minutes", systemImage: "5.arrow.trianglehead.clockwise")
                    }
                    
                    Button {
                        NotificationActionProcessor.shared.applyManualSnooze(
                            to: t,
                            interval: 15 * 60,
                            using: modelContext
                        )
                    } label: {
                        Label("15 minutes", systemImage: "15.arrow.trianglehead.clockwise")
                    }
                    
                    Button {
                        NotificationActionProcessor.shared.applyManualSnooze(
                            to: t,
                            interval: 30 * 60,
                            using: modelContext
                        )
                    } label: {
                        Label("30 minutes", systemImage: "30.arrow.trianglehead.clockwise")
                    }
                    
                    Button {
                        NotificationActionProcessor.shared.applyManualSnooze(
                            to: t,
                            interval: 60 * 60,
                            using: modelContext
                        )
                    } label: {
                        Label("1 hour", systemImage: "60.arrow.trianglehead.clockwise")
                    }
                    
                    Button {
                        NotificationActionProcessor.shared.applyManualSnooze(
                            to: t,
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
                            t,
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

                Button {
                    do {
                        _ = try TaskDuplicationService.duplicate(
                            t,
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
                    Label("Task & Attachments", systemImage: "rectangle.and.paperclip")
                }
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            
        }
    }

    @MainActor
    private func persistChanges() {
        do {
            try modelContext.save()
            modelContext.processPendingChanges()
            NotificationCenter.default.post(name: .taskDidChange, object: nil)
        } catch {
            AppLogger.persistence.fault("Failed to save context: \(error)")
        }
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

        persistChanges()

        NotificationManager.shared.refresh(force: false)
    }

    @MainActor
    private func toggleCompleted(_ task: TodoTask) {

        // 🔥 RICORRENZA: intercetta PRIMA di cambiare stato
        if task.recurrenceRule != nil {

            // 🔁 Ricorrenza: completa(se scelto dall'utente)  e rischedula
            task.completeRecurringTask(
                in: modelContext,
                options: settings.recurringTaskOptions
            )

            modelContext.processPendingChanges()

        } else {

            let newValue = !task.isCompleted
            task.isCompleted = newValue

            if newValue {
                task.completedAt = .now
                task.snoozeUntil = nil
            } else {
                task.completedAt = nil
                task.snoozeUntil = nil
            }
        }

        persistChanges()

        NotificationManager.shared.refresh(force: false)
    }
}


struct CompletedTasksContainerView: View {

    @Binding var taskPendingDeletion: TodoTask?
    let modelContext: ModelContext
    let searchText: String
    let selectedTagFilter: TaskTagFilter
    let selectedPriorityFilter: TaskPriority?
    let selectedPeriodFilter: TaskPeriodFilter?
    
    private var filteredCompleted: [TodoTask] {

        completedQuery.filter { task in

            let matchesSearch =
                searchText.isEmpty ||
                task.title.localizedCaseInsensitiveContains(searchText)

            let matchesTag: Bool = {
                switch selectedTagFilter {
                case .all:
                    return true
                case .none:
                    return task.mainTag == nil
                case .tag(let tag):
                    return task.mainTag == tag
                }
            }()

            let matchesPriority =
                selectedPriorityFilter == nil ||
                task.priority == selectedPriorityFilter

            let matchesPeriod =
                selectedPeriodFilter == nil ||
                selectedPeriodFilter?.matches(task.deadLine) == true

            return matchesSearch &&
                   matchesTag &&
                   matchesPriority &&
                   matchesPeriod
        }
    }
    @Query(
        filter: #Predicate<TodoTask> { $0.isCompleted },
        sort: \TodoTask.completedAt,
        order: .reverse
    )
    private var completedQuery: [TodoTask]

    var body: some View {
        CompletedSectionView(
            taskPendingDeletion: $taskPendingDeletion,
            tasks: filteredCompleted,
            modelContext: modelContext
        )
    }
}
struct CompletedSectionView: View {
    @Environment(AppSettings.self) private var settings
    private var listStyleChoice: TaskListStyle {
        settings.taskListStyle
    }
    private var confirmTaskDeletion: Bool {
        settings.confirmTaskDeletion
    }


    @Binding var taskPendingDeletion: TodoTask?
    let tasks: [TodoTask]
    let modelContext: ModelContext
    @State private var visibleCompletedCount = 100
    private var visibleTasks: [TodoTask] {

        Array(tasks.prefix(visibleCompletedCount))

    }
    

    var body: some View {
        Section(String(localized:"Completed (\(tasks.count))")) {

            ForEach(Array(visibleTasks.enumerated()), id: \.element.id) { index, t in

                TaskRow(
                    task: t,
                    showDateColumn: true,
                    appearance: .current(from: settings)
                )
                .frame(minHeight: TaskRowMetrics.rowHeight)
                .modifier(
                    RowCardStyle(
                        task: t,
                        style: listStyleChoice,
                        position: TaskRowPosition.position(
                            index: index,
                            total: visibleTasks.count
                        ),
                        opacity: listStyleChoice == .grouped ? 0.72 : 0.52
                    )
                )
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            withAnimation(.snappy(duration: 0.30, extraBounce: 0.02)) {
                                toggleCompleted(t)
                            }
                        } label: {
                            Label("To do", systemImage: "arrow.uturn.left")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if confirmTaskDeletion {
                                taskPendingDeletion = t
                            } else {
                                withAnimation(.snappy(duration: 0.26, extraBounce: 0.01)) {
                                    deleteTask(t, in: modelContext)
                                }
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            if confirmTaskDeletion {
                                taskPendingDeletion = t
                            } else {
                                withAnimation(.snappy(duration: 0.26, extraBounce: 0.01)) {
                                    deleteTask(t, in: modelContext)
                                }
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            toggleCompleted(t)
                        } label: {
                            Label("To do" , systemImage: "arrow.uturn.left"
                            )
                        }
                    }
                    .onAppear {

                        guard index == visibleTasks.count - 1 else {
                            return
                        }

                        guard visibleCompletedCount < tasks.count else {
                            return
                        }

                        visibleCompletedCount = min(
                            visibleCompletedCount + 100,
                            tasks.count
                        )
                    }
            }
        }
        .onChange(of: tasks.count) { _, _ in

            if visibleCompletedCount > tasks.count {

                visibleCompletedCount = max(
                    100,
                    tasks.count
                )
            }
        }
    }

    
    @MainActor
    private func persistChanges() {
        do {
            try modelContext.save()
            modelContext.processPendingChanges()
            NotificationCenter.default.post(name: .taskDidChange, object: nil)
        } catch {
            AppLogger.persistence.fault("Failed to save context: \(error)")
        }
    }

    @MainActor
    private func toggleCompleted(_ task: TodoTask) {

        // 🔥 RICORRENZA: se riattivi un task ricorrente NON ha senso tenerlo completato
        if task.recurrenceRule != nil {

            // 🔁 Ricorrenza: completa(se scelto da utente) e rischedula
            task.completeRecurringTask(
                in: modelContext,
                options: settings.recurringTaskOptions
            )

            modelContext.processPendingChanges()

        } else {

            let newValue = !task.isCompleted
            task.isCompleted = newValue
      
            if newValue {
                task.completedAt = .now
                task.snoozeUntil = nil
            } else {
                task.completedAt = nil
                task.snoozeUntil = nil
            }
        }

        persistChanges()

        NotificationManager.shared.refresh(force: false)
    }
}


