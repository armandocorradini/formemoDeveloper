import SwiftUI
import SwiftData
import PhotosUI
import Observation
import os


extension Notification.Name {
    static let taskDidChange = Notification.Name("taskDidChange")
}

// MARK: - TaskListView
struct TaskListView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<TodoTask> { !$0.isCompleted })
    private var todoQuery: [TodoTask]

    @Query(filter: #Predicate<TodoTask> { $0.isCompleted })
    private var completedQuery: [TodoTask]

    @State private var draftTask: TodoTask?

    @State private var searchText = ""
    @State private var showCompleted = false
    @State private var showNewTask = false
    @State private var showQuickGuide = false



    @State private var selectedTagFilter: TaskMainTag? = nil
    @State private var selectedPriorityFilter: TaskPriority? = nil
    @State private var selectedPeriodFilter: TaskPeriodFilter? = nil


    @AppStorage("TaskListStyle")
    private var listStyleChoice: TaskListStyle = .plain
    
    @AppStorage("TaskListShowDateEveryRow")
    private var showDateEveryRow = false

    @State private var taskPendingDeletion: TodoTask?

    private var todoTasks: [TodoTask] {

        let now = Date()

        return todoQuery
            .filter { task in

                let matchesSearch =
                searchText.isEmpty ||
                task.title.localizedCaseInsensitiveContains(searchText)

                let matchesTag =
                selectedTagFilter == nil ||
                task.mainTag == selectedTagFilter

                let matchesPriority =
                selectedPriorityFilter == nil ||
                task.priority == selectedPriorityFilter

                let matchesPeriod =
                selectedPeriodFilter == nil ||
                selectedPeriodFilter?.matches(task.deadLine) == true

                return matchesSearch && matchesTag && matchesPriority && matchesPeriod
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

    private var completedTasks: [TodoTask] {

        guard showCompleted else {
            return []
        }

        return completedQuery
            .filter { task in

                let matchesSearch =
                searchText.isEmpty ||
                task.title.localizedCaseInsensitiveContains(searchText)

                let matchesTag =
                selectedTagFilter == nil ||
                task.mainTag == selectedTagFilter

                let matchesPriority =
                selectedPriorityFilter == nil ||
                task.priority == selectedPriorityFilter

                let matchesPeriod =
                selectedPeriodFilter == nil ||
                selectedPeriodFilter?.matches(task.deadLine) == true

                return matchesSearch && matchesTag && matchesPriority && matchesPeriod
            }
            .sorted {
                ($0.completedAt ?? .distantPast) >
                ($1.completedAt ?? .distantPast)
            }
    }
    private static let backgroundGradient =
    LinearGradient(
        colors: [backColor1, backColor2],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )


    var body: some View {
        ZStack {
                // 1. IL GRADIENTE (Sotto a tutto)
                Self.backgroundGradient
                    .ignoresSafeArea()

                // 2. IL MATERIAL (Effetto vetro)
                Rectangle()
                .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    
            let isEmptyState =
                todoQuery.isEmpty &&
                completedQuery.isEmpty &&
                !showNewTask
            
                listWithStyle {

                    List {

                        if isEmptyState {

                            EmptySectionView(showQuickGuide: $showQuickGuide)
                        }

                        if !todoTasks.isEmpty {
                            TodoSectionView( taskPendingDeletion: $taskPendingDeletion,
                                             tasks: todoTasks,
                                             modelContext: modelContext

                            )
                        }

                        if showCompleted && !completedTasks.isEmpty {
                            CompletedSectionView( taskPendingDeletion: $taskPendingDeletion,
                                                  tasks: completedTasks,
                                                  modelContext: modelContext
                            )

                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 80)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .listRowInsets(
                        listStyleChoice == .plain
                        ? EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)
                        : EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
                    )
                    .alert(
                        "Delete task?",
                        isPresented: Binding(
                            get: { taskPendingDeletion != nil },
                            set: { if !$0 { taskPendingDeletion = nil } }
                        )
                    ) {



                        Button("Delete", role: .destructive) {
                            guard let task = taskPendingDeletion else { return }

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
                        listStyleChoice == .plain ? 0 : 14,
                        for: .scrollContent
                    )

                    .fullScreenCover(isPresented: $showQuickGuide) {
                        AppQuickGuideView()
                    }
                    .listRowSpacing(listStyleChoice == .plain ? 0 : 0) // spazio tra le righe
                }
                .navigationDestination(for: TodoTask.self) { task in
                    TaskDetailView(task: task)
                }
                .scrollDismissesKeyboard(.immediately)

                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search task")
                        .toolbarBackground(.hidden, for: .navigationBar)
            
                .navigationTitle((todoQuery.isEmpty && completedQuery.isEmpty) ? "" : String(localized:"My Tasks"))
                .navigationBarTitleDisplayMode(.inline)
                .sheet(item: $draftTask) { task in
                    NewTaskSheetView(draftTask: task)
                }
                //            .animation(.snappy, value: showCompleted)
                //            .animation(.snappy, value: searchText)


                .toolbar {

                    ToolbarItem(placement: .topBarTrailing) {

//                        Button {
//                            withAnimation(.snappy) {
//
//                                let testTasks = tasks.filter { $0.title == "ProvaProva" }
//
//                                if testTasks.isEmpty {
//                                    createTestTasks()
//                                } else {
//                                    deleteTestTasks()
//                                }
//                            }
//                        } label: {
//                            Image(systemName: "plus.circle.fill")
//                                .foregroundStyle(.green)
//                                .font(.title2)
//                        }
//
//



                        Button {
                            withAnimation(.snappy) {
                                showCompleted.toggle()
                            }
                        } label: {
                            Image(systemName: showCompleted ? "eye.slash" : "eye")
                                .foregroundStyle(showCompleted ? .gray.opacity(0.7) : .blue.opacity(0.7))
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
                    if !(todoQuery.isEmpty && completedQuery.isEmpty) {
                        ToolbarItem(placement: .topBarLeading) {
                            Menu {
                                // Sezione per rimuovere tutti i filtri
                                if selectedTagFilter != nil || selectedPriorityFilter != nil || selectedPeriodFilter != nil {
                                    Button(role: .destructive) {
                                        selectedTagFilter = nil
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
                                        // Opzione per deselezionare (All)
                                        // Usiamo Optional(nil) per far combaciare il tipo con selectedTagFilter
                                        Text("All").tag(nil as TaskMainTag?)

                                        ForEach(TaskMainTag.localizedSortedCases) { tag in
                                            Label(tag.localizedTitle, systemImage: tag.mainIcon)
                                                .tag(tag as TaskMainTag?)
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
                                        selectedTagFilter != nil ||
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

                                Picker("Style", selection: $listStyleChoice) {

                                    Label("Plain", systemImage: "list.bullet")
                                        .tag(TaskListStyle.plain)

                                    Label("Grouped", systemImage: "square.on.square")
                                        .tag(TaskListStyle.grouped)
                                }
                            }

                            Section() {

                                Toggle(isOn: $showDateEveryRow) {

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
    }

    @ViewBuilder
    private func listWithStyle<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {

        switch listStyleChoice {
        case .plain:
            content().listStyle(.plain)
        case .grouped:
            content().listStyle(.insetGrouped)
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
                    //                                .multilineTextAlignment(.leading)
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
                                Text("switch your list view.")

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
@MainActor
struct TaskRow: View {
    // Riceviamo il task direttamente. SwiftData gestisce la relazione in modo efficiente.
    let task: TodoTask
    let showDateColumn: Bool
    
    @AppStorage(TaskListAppearanceKeys.iconStyle)
    private var iconStyle: TaskIconStyle = .polychrome


    @AppStorage(TaskListAppearanceKeys.showBadge)
    private var showBadge = true

    @AppStorage(TaskListAppearanceKeys.showAttachments)
    private var showAttachments = true

    @AppStorage(TaskListAppearanceKeys.showLocation)
    private var showLocation = true

    @AppStorage(TaskListAppearanceKeys.showPriority)
    private var showPriority = true

    @AppStorage(TaskListAppearanceKeys.showBadgeOnlyWithPriority)
    private var showBadgeOnlyWithPriority = true

    @AppStorage("tasklist.highlightEnabled")
    private var highlightEnabled: Bool = true

    @AppStorage("tasklist.highlightColor")
    private var highlightColorHex: String = Color.red.toHex() ?? ""

    private var highlightColor: Color {
        Color(hex: highlightColorHex) ?? .red
    }

    @AppStorage("tasklist.showTodayExpiredLabel")
    private var showTodayExpiredLabel: Bool = true


    @AppStorage("selectedTaskRowStyle") private var selectedRowStyle: Int = 0
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
        74
    }
    // --- END PATCH ---

    var rowStyleToUse: Int {
        return selectedRowStyle
    }

    private var model: TaskRowDisplayModel {
        let shouldDisplayBadge =
            showBadge && (!showBadgeOnlyWithPriority || task.priority != .none)

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
            .frame(height: dynamicRowHeight)

            .buttonStyle(.plain)
    }

    private var rowContent: some View {
        ZStack {
            navigationLink
            content
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
            iconStyle: iconStyle,
            showBadge: model.shouldShowBadge,
            showAttachments: showAttachments,
            showLocation: showLocation,
            showPriority: showPriority,
            showBadgeOnlyWithPriority: showBadgeOnlyWithPriority,
            rowStyle: TaskRowStyle(rawValue: rowStyleToUse) ?? .style0,
            showDateColumn: showDateColumn,
            highlightCriticalOverdue: highlightEnabled,
            showTodayExpiredLabel: showTodayExpiredLabel
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, rowStyleToUse == 0 ? 14 : 10)
    }
}

// MARK: - Period Filter

enum TaskPeriodFilter: String, CaseIterable, Identifiable {

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
    func searchableIf(_ condition: Bool, text: Binding<String>, prompt: LocalizedStringKey = "Search task") -> some View {
        if condition {
            self.searchable(text: text, prompt: prompt)
        } else {
            self
        }
    }
}
struct TodoSectionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder
    private func groupedHeaderView(for group: (date: Date, tasks: [TodoTask])) -> some View {

        if let title = relativeHeaderTitle(for: group.date) {

            let isTodayGroup = Calendar.current.isDateInToday(group.date)

            let headerFillColor: Color = isTodayGroup
                ? Color.blue.opacity(colorScheme == .dark ? 0.14 : 0.06)
                : Color.white.opacity(colorScheme == .dark ? 0.035 : 0.045)

            let headerStrokeColor: Color = Color.white.opacity(0.12)

            let badgeFillColor: Color = isTodayGroup
                ? Color.blue.opacity(colorScheme == .dark ? 0.18 : 0.10)
                : Color.white.opacity(colorScheme == .dark ? 0.06 : 0.08)

            HStack(spacing: 10) {

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.82))

                Text("\(group.tasks.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary.opacity(0.82))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(badgeFillColor)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, isTodayGroup ? 12 : 9)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(headerFillColor)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.16 : 0.24),
                                        Color.white.opacity(colorScheme == .dark ? 0.03 : 0.05),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                isTodayGroup
                                ? LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.42 : 0.70),
                                        Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [
                                        headerStrokeColor,
                                        headerStrokeColor
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isTodayGroup ? 1.15 : 1
                            )
                    )
                    .shadow(
                        color: isTodayGroup
                            ? Color.blue.opacity(colorScheme == .dark ? 0.18 : 0.06)
                            : Color.white.opacity(colorScheme == .dark ? 0.05 : 0.03),
                        radius: isTodayGroup ? 18 : 12,
                        y: 6
                    )
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.20 : 0.06),
                        radius: 12,
                        y: 6
                    )
            )
            .padding(.horizontal, 16)
            .padding(.top, isTodayGroup ? 18 : (group.date == groupedTasksByDay.first?.date ? 6 : 14))
            .padding(.bottom, isTodayGroup ? 8 : 2)
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
    @AppStorage("TaskListStyle") private var listStyleChoice: TaskListStyle = .plain
    @AppStorage("confirmTaskDeletion")
    private var confirmTaskDeletion = true
    @Binding var taskPendingDeletion: TodoTask?

    let tasks: [TodoTask]
    let modelContext: ModelContext

    private var groupedTasksByDay: [(date: Date, tasks: [TodoTask])] {

        let calendar = Calendar.current

        let grouped = Dictionary(grouping: tasks) { task in
            calendar.startOfDay(for: task.deadLine ?? .distantFuture)
        }

        return grouped
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
    }

    enum DayRowPosition {
        case single
        case first
        case middle
        case last
    }

    private func rowPosition(index: Int, total: Int) -> DayRowPosition {

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

    struct RowCardStyle: ViewModifier {
        @Environment(\.colorScheme) private var colorScheme
        let task: TodoTask
        let style: TaskListStyle
        let position: DayRowPosition
        let showBottomSeparator: Bool

        @AppStorage("tasklist.showTodayExpiredLabel") private var showTodayExpiredLabel: Bool = true
        @AppStorage("tasklist.highlightEnabled") private var highlightEnabled: Bool = true
        @AppStorage("tasklist.highlightColor")  private var highlightColorHex: String = Color.red.toHex() ?? ""

        private var highlightColor: Color {
            Color(hex: highlightColorHex) ?? .red
        }

        func body(content: Content) -> some View {
            content
                .padding(.leading, style == .plain ? 16 : 10) // reduced spacing from highlight bar
                .padding(.trailing, style == .plain ? 12 : 0)
                .listRowInsets(
                    style == .grouped
                    ? EdgeInsets(
                        top: position == .first || position == .single ? 8 : 1,
                        leading: 14,
                        bottom: position == .last || position == .single ? 8 : 1,
                        trailing: 14
                    )
                    : EdgeInsets(
                        top: 10,
                        leading: 6,
                        bottom: 10,
                        trailing: 0
                    )
                )
                .listRowBackground(cardBackground(for: task))
        }

        @ViewBuilder
        private func cardBackground(for task: TodoTask) -> some View {
            let isToday = isTaskToday(task.deadLine)
            let isOverdue = isTaskOverdue(task.deadLine)
            let isCritical = task.priority.systemImage == "flame"

            let highlightOverlay: Color? = {
                guard highlightEnabled, isCritical, (isOverdue || isToday) else {
                    return nil
                }
                return highlightColor
            }()

            if style == .plain {

                ZStack {

                    RoundedRectangle(cornerRadius: 0, style: .continuous)
                        .fill(
                            Color(.systemBackground).opacity(
                                isToday
                                ? 0.50
                                : (colorScheme == .dark ? 0.22 : 0.26)
                            )
                        )
                }
                .overlay(alignment: .leading) {

                    if let highlightOverlay {

                        RoundedRectangle(cornerRadius: 1.3)
                            .fill(highlightOverlay)
                            .frame(width: 1.3, height: 50)
                            .frame(maxHeight: .infinity, alignment: .center)
                            .padding(.leading, 12)
                    }
                }
                .overlay(alignment: .bottomLeading) {

                    if showBottomSeparator {

                        Rectangle()
                            .fill(
                                colorScheme == .dark
                                ? Color.white.opacity(0.09)
                                : Color.black.opacity(0.06)
                            )
                            .frame(height: 0.35)
                            .padding(.leading, 76)
                            .padding(.trailing, 24)
                    }
                }
                .shadow(
                    color: .black.opacity(
                        colorScheme == .dark ? 0.22 : 0.08
                    ),
                    radius: 8,
                    y: 3
                )

            } else {

                ZStack {

                    AnyShape(shape)
                        .fill(
                            Color.white.opacity(
                                colorScheme == .dark ? 0.02 : 0.04
                            )
                        )
                        .padding(.top,
                                 style == .grouped &&
                            (position == .first || position == .single)
                            ? 8
                            : 0
                        )

                    AnyShape(shape)
                        .fill(
                            Color(.systemBackground).opacity(
                                isToday
                                ? 0.50
                                : (colorScheme == .dark ? 0.22 : 0.26)
                            )
                        )
                        .padding(.top,
                                 style == .grouped &&
                            (position == .first || position == .single)
                            ? 8
                            : 0
                        )
                }
                .overlay(alignment: .leading) {
                    if let highlightOverlay {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(highlightOverlay)
                            .frame(width: 1.5, height: 38)
                            .frame(maxHeight: .infinity, alignment: .center)
                            .padding(.leading, 10)
                    }
                }
                // PATCH: Add bottom separator overlay for grouped style (updated)
                .overlay(alignment: .bottomLeading) {

                    if position != .last &&
                        position != .single {

                        Rectangle()
                            .fill(
                                colorScheme == .dark
                                ? Color.white.opacity(0.09)
                                : Color.black.opacity(0.06)
                            )
                            .frame(height: 0.35)
                            .padding(.leading, 76)
                            .padding(.trailing, 24)
                    }
                }
                // PATCH: Add subtle shadow for grouped style (updated)
                .shadow(
                    color: .black.opacity(
                        colorScheme == .dark ? 0.22 : 0.08
                    ),
                    radius: 8,
                    y: 3
                )
            }
        }
        
        private struct AnyShape: Shape, @unchecked Sendable {

            private let pathBuilder: (CGRect) -> Path

            init<S: Shape>(_ shape: S) {
                self.pathBuilder = { rect in
                    shape.path(in: rect)
                }
            }

            func path(in rect: CGRect) -> Path {
                pathBuilder(rect)
            }
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

        private func isTaskToday(_ date: Date?) -> Bool {
            guard let date else { return false }
            return Calendar.current.isDateInToday(date)
        }

        private func isTaskOverdue(_ date: Date?) -> Bool {
            guard let date else { return false }
            return date < Date()
        }
    }
    
    @AppStorage("TaskListShowDateEveryRow")
    private var showDateEveryRow = false

    var body: some View {

        if listStyleChoice == .grouped {

            Section {

                HStack {
                    Text(String(localized: "To do (\(tasks.count))"))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 18)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                ForEach(groupedTasksByDay, id: \.date) { group in
                    groupedHeaderView(for: group)

                    ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, t in
                        taskRow(
                            for: t,
                            position: rowPosition(
                                index: index,
                                total: group.tasks.count
                            )
                        )
                    }
                }
            }
            .listSectionSeparator(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .animation(.snappy(duration: 0.22), value: groupedTasksByDay.map(\.date))

        } else {

            Section(String(localized:"To do (\(tasks.count))")) {

                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, t in

                    let currentDay = Calendar.current.startOfDay(
                        for: t.deadLine ?? .distantFuture
                    )

                    let previousDay: Date? = {

                        guard index > 0 else { return nil }

                        return Calendar.current.startOfDay(
                            for: tasks[index - 1].deadLine ?? .distantFuture
                        )
                    }()

                    let isFirstOfDay = previousDay != currentDay

                    taskRow(
                        for: t,
                        position: isFirstOfDay ? .first : .middle
                    )
                }
            }
        }
    }
    @ViewBuilder
    private func taskRow(for t: TodoTask, position: DayRowPosition) -> some View {

        TaskRow(
            task: t,
            showDateColumn:
                showDateEveryRow
                ? true
                : (position == .first || position == .single)
        )

        .modifier(
            RowCardStyle(
                task: t,
                style: listStyleChoice,
                position: position,
                showBottomSeparator:
                    listStyleChoice == .plain
                    ? position != .last && position != .single
                    : true
            )
        )

        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
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
                    withAnimation(.easeOut(duration: 0.12)) {
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
                    withAnimation {
                        deleteTask(t, in: modelContext)
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

        do {
            try modelContext.save()
            modelContext.processPendingChanges()
            NotificationCenter.default.post(name: .taskDidChange, object: nil)
        } catch {
            AppLogger.persistence.fault("Failed to postpone task: \(error)")
        }

        NotificationManager.shared.refresh(force: false)
    }

    @MainActor
    private func toggleCompleted(_ task: TodoTask) {

        // 🔥 RICORRENZA: intercetta PRIMA di cambiare stato
        if task.recurrenceRule != nil {

            // 🔁 Ricorrenza: completa e rischedula
            task.completeRecurringTask(in: modelContext)


            modelContext.processPendingChanges()
            NotificationCenter.default.post(name: .taskDidChange, object: nil)

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

        try? modelContext.save()
        modelContext.processPendingChanges()
        NotificationCenter.default.post(name: .taskDidChange, object: nil)

        NotificationManager.shared.refresh(force: false)
    }
}

struct CompletedSectionView: View {
    @AppStorage("TaskListStyle") private var listStyleChoice: TaskListStyle = .plain
    @AppStorage("confirmTaskDeletion")
    private var confirmTaskDeletion = true


    @Binding var taskPendingDeletion: TodoTask?
    let tasks: [TodoTask]
    let modelContext: ModelContext

    struct RowCardStyle: ViewModifier {
        let task: TodoTask
        let style: TaskListStyle
        let position: TodoSectionView.DayRowPosition

        func body(content: Content) -> some View {
            content
                .padding(.leading, style == .plain ? 16 : 10)
                .padding(.trailing, style == .plain ? 12 : 0)
                .listRowInsets(
                    style == .grouped
                    ? EdgeInsets(
                        top: position == .first || position == .single ? 8 : 1,
                        leading: 14,
                        bottom: position == .last || position == .single ? 8 : 1,
                        trailing: 14
                    )
                    : EdgeInsets(
                        top: 10,
                        leading: 6,
                        bottom: 10,
                        trailing: 0
                    )
                )
                .listRowBackground(cardBackground())
        }

        @ViewBuilder
        private func cardBackground() -> some View {

            if style == .plain {

                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(Color.clear)

            } else {

                ZStack {

                    AnyShape(shape)
                    .fill(Color(.systemBackground).opacity(0.3))
                }
                .overlay(alignment: .bottomLeading) {

                    if style == .grouped &&
                        position != .last &&
                        position != .single {

                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(height: 0.5)
                            .padding(.leading, 76)
                            .padding(.trailing, 24)
                    }
                }
            }
        }

        private struct AnyShape: Shape, @unchecked Sendable {

            private let pathBuilder: (CGRect) -> Path

            init<S: Shape>(_ shape: S) {
                self.pathBuilder = { rect in
                    shape.path(in: rect)
                }
            }

            func path(in rect: CGRect) -> Path {
                pathBuilder(rect)
            }
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
    }
    var body: some View {

        Section(String(localized:"Completed (\(tasks.count))")) {

            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, t in

                TaskRow(
                    task: t,
                    showDateColumn: true
                )

                    .modifier(
                        RowCardStyle(
                            task: t,
                            style: listStyleChoice,
                            position: {
                                if tasks.count == 1 {
                                    return .single
                                } else if index == 0 {
                                    return .first
                                } else if index == tasks.count - 1 {
                                    return .last
                                } else {
                                    return .middle
                                }
                            }()
                        )
                    )

                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
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

                                withAnimation(.easeOut(duration: 0.12)) {
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
                                withAnimation {
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
            }
        }
    }

    
    @MainActor
    private func toggleCompleted(_ task: TodoTask) {

        // 🔥 RICORRENZA: se riattivi un task ricorrente NON ha senso tenerlo completato
        if task.recurrenceRule != nil {

            // 🔁 Ricorrenza: completa e rischedula
            task.completeRecurringTask(in: modelContext)


            modelContext.processPendingChanges()
            NotificationCenter.default.post(name: .taskDidChange, object: nil)

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

        do {
            try modelContext.save()
            modelContext.processPendingChanges()
            NotificationCenter.default.post(name: .taskDidChange, object: nil)
        } catch {
            AppLogger.persistence.fault("Failed to save context: \(error)")
        }

        NotificationManager.shared.refresh(force: false)
    }
}

