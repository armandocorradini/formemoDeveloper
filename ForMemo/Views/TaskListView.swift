

import SwiftUI
import SwiftData
import PhotosUI
import Observation
import os
import Combine

extension Notification.Name {
    static let taskDidChange = Notification.Name("taskDidChange")
}

// MARK: - TaskListView
struct TaskListView: View {

    @Environment(\.modelContext) private var modelContext

    @Environment(\.scenePhase) private var scenePhase


    @Query(filter: #Predicate<TodoTask> { !$0.isCompleted })
    private var todoQuery: [TodoTask]

    @Query(filter: #Predicate<TodoTask> { $0.isCompleted })
    private var completedQuery: [TodoTask]

    @State private var draftTask: TodoTask?

    //    @Query(sort: \TodoTask.deadLine, order: .forward)
    //    private var tasks: [TodoTask]


    @State private var searchText = ""
    @State private var showCompleted = false
    @State private var showNewTask = false
    @State private var showQuickGuide = false

    @State private var selectedTagFilter: TaskMainTag? = nil
    @State private var selectedPriorityFilter: TaskPriority? = nil
    @State private var selectedPeriodFilter: TaskPeriodFilter? = nil


    @AppStorage("TaskListStyle")
    private var listStyleChoice: TaskListStyle = .plain

    @State private var taskPendingDeletion: TodoTask?


//    private var filteredTasks: [TodoTask] {
//        let source = showCompleted ? completedQuery : todoQuery
//
//        return source.filter { task in
//
//            let matchesSearch =
//            searchText.isEmpty ||
//            task.title.localizedCaseInsensitiveContains(searchText)
//
//            let matchesTag =
//            selectedTagFilter == nil ||
//            task.mainTag == selectedTagFilter
//
//            let matchesPriority =
//            selectedPriorityFilter == nil ||
//            task.priority == selectedPriorityFilter
//
//            let matchesPeriod =
//            selectedPeriodFilter == nil ||
//            selectedPeriodFilter?.matches(task.deadLine) == true
//
//            return matchesSearch && matchesTag && matchesPriority && matchesPeriod
//        }
//    }
    @State private var cachedTodo: [TodoTask] = []
    @State private var cachedCompleted: [TodoTask] = []
    @State private var timerTask: Task<Void, Never>?

    private var nextDeadline: Date? {
        let now = Date()
        return todoQuery
            .compactMap { $0.deadLine }
            .filter { $0 > now }
            .min()
    }


    private func startTimerIfNeeded() {
        guard timerTask == nil else { return }

        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000) // ogni 30 sec
                await MainActor.run {
                    recomputeSections()
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
    private var dependencyHash: Int {
        var hasher = Hasher()
        hasher.combine(todoQuery.count)
        hasher.combine(completedQuery.count)
        hasher.combine(searchText)
        hasher.combine(selectedTagFilter)
        hasher.combine(selectedPriorityFilter)
        hasher.combine(selectedPeriodFilter)
        hasher.combine(showCompleted)
        return hasher.finalize()
    }

    private func recomputeSections() {
      
        func matches(_ task: TodoTask) -> Bool {
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

        let todo = todoQuery.lazy.filter { matches($0) }

        cachedTodo = todo.sorted {
            let lhs = $0.deadLine ?? .distantFuture
            let rhs = $1.deadLine ?? .distantFuture

            let lhsOverdue = lhs < Date()
            let rhsOverdue = rhs < Date()

            if lhsOverdue != rhsOverdue {
                return lhsOverdue
            }

            if lhs != rhs {
                return lhs < rhs
            }

            return $0.id.uuidString < $1.id.uuidString
        }

        if showCompleted {
            let sortedCompleted = completedQuery.lazy
                .filter { matches($0) }
                .sorted {
                    ($0.completedAt ?? .distantPast) >
                    ($1.completedAt ?? .distantPast)
                }

            cachedCompleted = sortedCompleted
        } else {
            cachedCompleted = []
        }
    }

    private var todoTasks: [TodoTask] { cachedTodo }
    private var completedTasks: [TodoTask] { cachedCompleted }
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
                    .id(listStyleChoice)
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
                            NotificationManager.shared.refresh()
                            taskPendingDeletion = nil
                        }
                        Button("Cancel", role: .cancel) {
                            taskPendingDeletion = nil
                        }
                    } message: {
                        Text("This action cannot be undone.")
                    }
                    .contentMargins(.horizontal, listStyleChoice == .plain ? 0 : 10, for: .scrollContent)

                    .fullScreenCover(isPresented: $showQuickGuide) {
                        AppQuickGuideView()
                    }
                    .listRowSpacing(listStyleChoice == .plain ? 0 : 0) // spazio tra le righe
                    .transaction { $0.animation = nil }
                    .transaction {
                        $0.disablesAnimations = true
                    }
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

                            Section {
                                Picker("List Style", selection: $listStyleChoice) {
                                    ForEach(TaskListStyle.allCases, id: \.self) { style in
                                        Label(style.localizedName,
                                              systemImage: style.iconName)
                                        .tag(style)
                                    }
                                }
                                .pickerStyle(.inline)
                            } header: {
                                Text("List Style")
                            }

                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                    }
                }
        }
        .onAppear {
            recomputeSections()
            startTimerIfNeeded()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: dependencyHash) {
            recomputeSections()
            stopTimer()
            startTimerIfNeeded()
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                recomputeSections()
                startTimerIfNeeded()
            default:
                stopTimer()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
        ) { _ in
            recomputeSections()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .taskDidChange)
                .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        ) { _ in
            recomputeSections()
        }
        .onReceive(

            NotificationCenter.default.publisher(for: .attachmentsShouldRefresh)
                .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        ) { _ in

            recomputeSections()

        }
    }

    @ViewBuilder
    private func listWithStyle<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {

        switch listStyleChoice {
        case .plain:
            content().listStyle(.plain)
        case .cards:
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
                    .frame(maxWidth: .infinity, alignment: .leading) // Espande il contenitore a tutto schermo a sx
                    // .padding(.horizontal) // Distanzia il blocco dai bordi dello schermo
                }
            }
            .listRowSeparator(.hidden)
            
        }
    }
}

import SwiftUI
import SwiftData

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
        let startOfToday = Calendar.current.startOfDay(for: now)

        return d >= startOfToday && d >= now
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

        let hasStatusLabel =
            showTodayExpiredLabel &&
            !task.isCompleted &&
            (isToday || isOverdue)

        if hasStatusLabel {
            return showDateColumn ? 74 : 80
        } else {
            return 66
        }
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
            showTodayExpiredLabel:
                showTodayExpiredLabel &&
                !task.isCompleted &&
                (isToday || isOverdue)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 14)
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
    case plain, cards
    var localizedName: LocalizedStringKey {
        switch self {
        case .plain: return "Plain"
        case .cards: return "Inset Grouped"
        }
    }
    var iconName: String {
        switch self {
        case .plain: return "list.bullet"
        case .cards: return "rectangle.grid.1x3"
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

        @AppStorage("tasklist.showTodayExpiredLabel") private var showTodayExpiredLabel: Bool = true
        @AppStorage("tasklist.highlightEnabled") private var highlightEnabled: Bool = true
        @AppStorage("tasklist.highlightColor")  private var highlightColorHex: String = Color.red.toHex() ?? ""
        private let now = Date()

        private var highlightColor: Color {
            Color(hex: highlightColorHex) ?? .red
        }

        func body(content: Content) -> some View {
            content
                .padding(.leading, style == .plain ? 16 : 10) // reduced spacing from highlight bar
                .padding(.trailing, style == .plain ? 12 : 0)
                .listRowInsets(
                    style == .cards
                    ? EdgeInsets(
                        top: position == .first || position == .single ? 14 : 1,
                        leading: 14,
                        bottom: position == .first ? 6 : (position == .last || position == .single ? 4 : 1),
                        trailing: 14
                    )
                    : EdgeInsets(top: 10, leading: 6, bottom: 10, trailing: 0)
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
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(Color.clear)
                    .overlay(alignment: .leading) {
                        if let highlightOverlay {
                            RoundedRectangle(cornerRadius: style == .plain ? 1.3 : 1.3)
                                .fill(highlightOverlay)
                                .frame(width: style == .plain ? 1.3 : 1.3,
                                       height: style == .plain ? 50 : 50)
                                .frame(maxHeight: .infinity, alignment: .center)
                                .padding(.leading, style == .plain ? 12 : 8)
                                .padding(.trailing,8)
                        }
                    }
            } else {

                ZStack {

                    shape
                        .fill(
                            Color.white.opacity(
                                colorScheme == .dark ? 0.02 : 0.04
                            )
                        )

                    shape
                        .fill(
                            Color(.systemBackground).opacity(0.3)
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
                .overlay(alignment: .bottomLeading) {

                    if position != .last && position != .single {

                        Rectangle()
                            .fill(
                                colorScheme == .dark
                                ? Color.white.opacity(0.14)
                                : Color.black.opacity(0.10)
                            )
                            .frame(height: 0.5)
                            .padding(.leading, 76)
                            .padding(.trailing, 24)
                    }
                }
                .shadow(
                    color: .black.opacity(
                        colorScheme == .dark ? 0.10 : 0.04
                    ),
                    radius: 3,
                    y: 1
                )
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
            return Calendar.current.isDateInToday(date) && date >= now
        }

        private func isTaskOverdue(_ date: Date?) -> Bool {
            guard let date else { return false }
            return date < now
        }
    }

    var body: some View {

        if listStyleChoice == .cards {

            ForEach(groupedTasksByDay, id: \.date) { group in

                Section {

                    ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, t in

                        taskRow(
                            for: t,
                            position: rowPosition(
                                index: index,
                                total: group.tasks.count
                            )
                        )
                    }

                } header: {

                    EmptyView()
                }
                .listSectionSeparator(.hidden)
                .listSectionSpacing(8)
            }

        } else {

            Section(String(localized:"To do (\(tasks.count))")) {

                ForEach(tasks, id: \.id) { t in

                    taskRow(for: t, position: .single)
                }
            }
        }
    }
    @ViewBuilder
    private func taskRow(for t: TodoTask, position: DayRowPosition) -> some View {

        TaskRow(
            task: t,
            showDateColumn: position == .first || position == .single
        )

        .modifier(
            RowCardStyle(
                task: t,
                style: listStyleChoice,
                position: position
            )
        )

        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                toggleCompleted(t)
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
                    withAnimation {
                        deleteTask(t, in: modelContext)
                    }
                    NotificationManager.shared.refresh()
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
                    postpone(t, byHours: 1)
                } label: {
                    Label("+1 hour", systemImage: "clock.badge")
                }

                Button {
                    postpone(t, byHours: 3)
                } label: {
                    Label("+3 hours", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }

                Button {
                    postpone(t, byDays: 1)
                } label: {
                    Label("+1 day", systemImage: "sun.max")
                }

                Button {
                    postpone(t, byDays: 2)
                } label: {
                    Label("+2 days", systemImage: "calendar")
                }

                Button {
                    postpone(t, byDays: 3)
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationManager.shared.refresh(force: true)
        }
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

        // 🔴 Fix swipe crash: delay refresh to let swipe close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationManager.shared.refresh(force: true)
        }
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

        func body(content: Content) -> some View {
            content
                .padding(.leading, style == .plain ? 16 : 10)
                .padding(.trailing, style == .plain ? 12 : 0)
                .listRowInsets(
                    style == .cards
                    ? EdgeInsets(top: 20, leading: 8, bottom: 20, trailing: 8)
                    : EdgeInsets(top: 20, leading: 6, bottom: 20, trailing: 0)
                )
                .listRowBackground(cardBackground(for: task))
        }

        @ViewBuilder
        private func cardBackground(for task: TodoTask) -> some View {

            if style == .plain {
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(Color.clear)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(.secondary.opacity(0.3), lineWidth: 0.3)
                    )
            }
        }
    }
    var body: some View {

        Section(String(localized:"Completed (\(tasks.count))")) {


            ForEach(tasks, id: \.id) { t in

                TaskRow(
                    task: t,
                    showDateColumn: true
                )

                    .modifier(RowCardStyle( task: t, style: listStyleChoice))

                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            toggleCompleted(t)
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

                                withAnimation {
                                    deleteTask(t, in: modelContext)
                                }
                                NotificationManager.shared.refresh()
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

        // 🔴 Fix swipe crash
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationManager.shared.refresh(force: true)
        }
    }
}

