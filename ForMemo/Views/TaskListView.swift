

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


    @AppStorage("TaskListStyle")
    private var listStyleChoice: TaskListStyle = .plain

    @State private var taskPendingDeletion: TodoTask?


    private var filteredTasks: [TodoTask] {
        let source = showCompleted ? completedQuery : todoQuery

        return source.filter { task in
            let matchesSearch =
            searchText.isEmpty ||
            task.title.localizedCaseInsensitiveContains(searchText)

            let matchesTag =
            selectedTagFilter == nil ||
            task.mainTag == selectedTagFilter

            let matchesPriority =
            selectedPriorityFilter == nil ||
            task.priority == selectedPriorityFilter

            return matchesSearch && matchesTag && matchesPriority
        }
    }
    @State private var cachedTodo: [TodoTask] = []
    @State private var cachedCompleted: [TodoTask] = []
    // 🔥 Timer per aggiornamenti automatici (Today → Overdue)
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private func recomputeSections() {
        // Sempre calcola TODO
        var todo = todoQuery.filter { task in
            let matchesSearch =
                searchText.isEmpty ||
                task.title.localizedCaseInsensitiveContains(searchText)

            let matchesTag =
                selectedTagFilter == nil ||
                task.mainTag == selectedTagFilter

            let matchesPriority =
                selectedPriorityFilter == nil ||
                task.priority == selectedPriorityFilter

            return matchesSearch && matchesTag && matchesPriority
        }

        todo.sort {
            let lhs = $0.deadLine ?? .distantFuture
            let rhs = $1.deadLine ?? .distantFuture
            let now = Date()

            let lhsOverdue = lhs < now
            let rhsOverdue = rhs < now

            if lhsOverdue != rhsOverdue {
                return lhsOverdue && !rhsOverdue
            }

            return lhs < rhs
        }
        cachedTodo = todo

        // Calcola COMPLETED solo se serve
        if showCompleted {
            var completed = completedQuery.filter { task in
                let matchesSearch =
                    searchText.isEmpty ||
                    task.title.localizedCaseInsensitiveContains(searchText)

                let matchesTag =
                    selectedTagFilter == nil ||
                    task.mainTag == selectedTagFilter

                let matchesPriority =
                    selectedPriorityFilter == nil ||
                    task.priority == selectedPriorityFilter

                return matchesSearch && matchesTag && matchesPriority
            }

            completed.sort {
                ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
            }
            cachedCompleted = completed
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

                listWithStyle {

                    List {
                        if todoQuery.isEmpty && completedQuery.isEmpty && !showNewTask {
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
                    .listRowSpacing(listStyleChoice == .plain ? 0 : 7) // spazio tra le righe
                    .transaction { $0.animation = nil }
                }
                .navigationDestination(for: TodoTask.self) { task in
                    TaskDetailView(task: task)
                }
                .scrollDismissesKeyboard(.immediately)

                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search task"
                )
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
                                .foregroundStyle(showCompleted ? .gray : .blue)
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
                                if selectedTagFilter != nil || selectedPriorityFilter != nil {
                                    Button(role: .destructive) {
                                        selectedTagFilter = nil
                                        selectedPriorityFilter = nil
                                    } label: {
                                        Label(
                                            String(localized: "Remove Filters"),
                                            systemImage: "line.3.horizontal.decrease.circle.slash"
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

                                        ForEach(TaskMainTag.allCases) { tag in
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

                            } label: {
                                // Icona principale del Filtro nella Toolbar
                                // Diventa blu se almeno un filtro è attivo
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .foregroundStyle(
                                        selectedTagFilter != nil || selectedPriorityFilter != nil
                                        ? .red
                                        : .primary
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
                        }
                    }
                }
        }
        .onAppear {
            recomputeSections()
        }
        .onChange(of: todoQuery) { _, _ in
            recomputeSections()
        }
        .onChange(of: completedQuery) { _, _ in
            recomputeSections()
        }
        .onChange(of: searchText) {
            recomputeSections()
        }
        .onChange(of: selectedTagFilter) {
            recomputeSections()
        }
        .onChange(of: selectedPriorityFilter) {
            recomputeSections()
        }
        .onChange(of: showCompleted) {
            recomputeSections()
        }
        .onReceive(timer) { _ in
            recomputeSections()
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskDidChange)) { _ in
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

    @AppStorage(TaskListAppearanceKeys.iconStyle)
    private var iconStyle: TaskIconStyle = .polychrome

    @AppStorage(TaskListAppearanceKeys.badgeColor)
    private var badgeColorRaw: String = BadgeColorStyle.default.rawValue

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
        Color(hex: highlightColorHex) ?? .blue
    }

    @AppStorage("tasklist.showTodayExpiredLabel")
    private var showTodayExpiredLabel: Bool = true

    private var badgeStyle: BadgeColorStyle {
        BadgeColorStyle(rawValue: badgeColorRaw) ?? .default
    }

    @AppStorage("selectedTaskRowStyle") private var selectedRowStyle: Int = 0


    private var isToday: Bool {
        guard let d = task.deadLine else { return false }
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)

        return d >= startOfToday && d >= now
    }

    private var isOverdue: Bool {
        guard let d = task.deadLine else { return false }
        return d < Date()
    }

    private var dynamicRowHeight: CGFloat {
        if showTodayExpiredLabel && !task.isCompleted && (isToday || isOverdue) {
            return 42
        } else {
            return 38
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
        ZStack {
            // NavigationLink trasparente per mantenere l'estetica custom
            NavigationLink(value: task) {
                EmptyView()
            }
            .opacity(0)

            TaskRowContent(
                model: model,
                iconStyle: iconStyle,
                badgeStyle: badgeStyle,
                showBadge: model.shouldShowBadge,
                showAttachments: showAttachments,
                showLocation: showLocation,
                showPriority: showPriority,
                showBadgeOnlyWithPriority: showBadgeOnlyWithPriority,
                rowStyle: TaskRowStyle(rawValue: rowStyleToUse) ?? .style0,
                highlightCriticalOverdue: highlightEnabled,
                showTodayExpiredLabel: showTodayExpiredLabel && !task.isCompleted
            )
        }

        .contentShape(Rectangle())
        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
        .frame(height: dynamicRowHeight)
        .padding(.vertical, 2)
        .buttonStyle(.plain)
        // Tint della linea di separazione basato sullo stato del task
        .listRowSeparatorTint(task.status.color.opacity(0.35))
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

    struct RowCardStyle: ViewModifier {
        @Environment(\.colorScheme) private var colorScheme
        let task: TodoTask
        let style: TaskListStyle

        @AppStorage("tasklist.showTodayExpiredLabel") private var showTodayExpiredLabel: Bool = true
        @AppStorage("tasklist.highlightEnabled") var highlightEnabled: Bool = true
        @AppStorage("tasklist.highlightColor") var highlightColorHex: String = Color.red.toHex() ?? ""

        private var highlightColor: Color {
            Color(hex: highlightColorHex) ?? .blue
        }

        func body(content: Content) -> some View {
            content
                .padding(.leading, style == .plain ? 24 : 14) // extra space for highlight bar
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
            let isToday = isTaskToday(task.deadLine)
            let isOverdue = isTaskOverdue(task.deadLine)
            let isCritical = task.priority.systemImage == "flame"

            let strokeColor: Color = {
                if isOverdue { return .red }
                if isToday { return .orange }
                return .secondary
            }()

            let lineWidth: CGFloat =
            (isToday || isOverdue) ? 0.4: 0.3

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
                            RoundedRectangle(cornerRadius: style == .plain ? 2 : 4)
                                .fill(highlightOverlay)
                                .frame(width: style == .plain ? 4 : 6,
                                       height: style == .plain ? 34 : 44)
                                .frame(maxHeight: .infinity, alignment: .center)
                                .padding(.leading, style == .plain ? 12 : 8)
                                .padding(.trailing,8)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.clear)
                    .overlay(alignment: .leading) {
                        if let highlightOverlay {
                            RoundedRectangle(cornerRadius: style == .plain ? 2 : 4)
                                .fill(highlightOverlay)
                                .frame(width: style == .plain ? 4 : 6,
                                       height: style == .plain ? 34 : 44)
                                .frame(maxHeight: .infinity, alignment: .center)
                                .padding(.leading, style == .plain ? 12 : 8)
                                .padding(.trailing, 8)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(strokeColor, lineWidth: lineWidth)
                    )
            }
        }

        private func isTaskToday(_ date: Date?) -> Bool {
            guard let date else { return false }
            let now = Date()
            return Calendar.current.isDateInToday(date) && date >= now
        }

        private func isTaskOverdue(_ date: Date?) -> Bool {
            guard let date else { return false }
            return date < Date()
        }

        private func isTaskOverdueNow(_ date: Date?) -> Bool {
            guard let date = date else { return false }
            return date < Date()
        }
    }

    var body: some View {

        Section(String(localized:"To do (\(tasks.count))")) {

            ForEach(tasks, id: \.id) { t in

                TaskRow(task: t)

                    .modifier(RowCardStyle(task: t, style: listStyleChoice))

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
                    }
            }
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

            if style == .cards {

                content
                    .listRowInsets(
                        EdgeInsets(top: 20, leading: 8, bottom: 20, trailing: 8)
                    )
                    .listRowBackground(cardBackground(for: task))

            } else {

                content
                    .listRowInsets(
                        EdgeInsets(top: 20, leading: 4, bottom: 20, trailing: 4)
                    )
                    .listRowBackground(Color.clear)
            }
        }

        private func cardBackground(for task: TodoTask) -> some View {

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    Color(uiColor: .secondarySystemBackground).opacity(0.8))
        }
    }
    var body: some View {

        Section(String(localized:"Completed (\(tasks.count))")) {


            ForEach(tasks, id: \.id) { t in

                TaskRow(task: t)

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

