import SwiftUI
import SwiftData
import PhotosUI
import Observation

// MARK: - TaskListView
struct TaskListView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @Environment(\.scenePhase) private var scenePhase
    
    
    @Query(sort: [SortDescriptor(\TodoTask.deadLine, order: .forward)])
    private var tasks: [TodoTask]
    
    @State private var draftTask: TodoTask?
    
    //    @Query(sort: \TodoTask.deadLine, order: .forward)
    //    private var tasks: [TodoTask]
    
    @State private var path = NavigationPath()
    
    @State private var searchText = ""
    @State private var showCompleted = false
    @State private var showNewTask = false
    @State private var showQuickGuide = false
    
    @State private var selectedTagFilter: TaskMainTag? = nil
    @State private var selectedPriorityFilter: TaskPriority? = nil
    @State private var cachedFiltered: [TodoTask] = []
    @State private var lastFilterSignature: String = ""
    
    @AppStorage("TaskListStyle")
    private var listStyleChoice: TaskListStyle = .cards
    
    @State private var taskPendingDeletion: TodoTask?
    
    private var filteredTasks: [TodoTask] {
        
        let signature = computeFilterSignature()
        
        if signature == lastFilterSignature {
            return cachedFiltered
        }
        
        let result = tasks.filter { task in
            
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
        
        DispatchQueue.main.async {
            cachedFiltered = result
            lastFilterSignature = signature
        }
        
        return result
    }
    
    
    
    
    
    private var splitTasks: (todo: [TodoTask], completed: [TodoTask]) {
        
        let filtered = filteredTasks
        
        var todo: [TodoTask] = []
        var completed: [TodoTask] = []
        
        for task in filtered {
            if task.isCompleted {
                completed.append(task)
            } else {
                todo.append(task)
            }
        }
        
        todo.sort { ($0.deadLine ?? .distantFuture) < ($1.deadLine ?? .distantFuture) }
        
        completed.sort {
            ($0.deadLine ?? .distantPast) > ($1.deadLine ?? .distantPast)
        }
        
        return (todo, completed)
    }
    private var todoTasks: [TodoTask] {
        splitTasks.todo
    }
    
    private var completedTasks: [TodoTask] {
        splitTasks.completed
    }
    private static let backgroundGradient =
    LinearGradient(
        colors: [backColor1, backColor2],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    
    var body: some View {
        
        NavigationStack(path: $path)  {
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
                        
                        if tasks.isEmpty && !showNewTask {
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
                            NotificationManager.shared.refresh(force: true)
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
                }
                .navigationDestination(for: TodoTask.self) { task in
                    TaskDetailView(task: task)
                }
                .scrollDismissesKeyboard(.immediately)
                
                .searchableIf(
                    !tasks.isEmpty && !showNewTask,
                    text: $searchText,
                    prompt: "Search task"
                )
                .navigationTitle(tasks.isEmpty ? "" : String(localized:"My Tasks"))
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
                    if !tasks.isEmpty {
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
        }
    }
    
    
//    // MARK: - DEBUG BULK ACTIONS
//
//    @MainActor
//    private func createTestTasks() {
//        
//        for _ in 0..<3000 {
//            let task = TodoTask(
//                title: "ProvaProva"
//            )
//            modelContext.insert(task)
//        }
//        
//        do {
//            try modelContext.save()
//        } catch {
//            assertionFailure("Bulk create failed: \(error)")
//        }
//        
//        NotificationManager.shared.refresh(force: true)
//    }
//
//    @MainActor
//    private func deleteTestTasks() {
//        
//        let tasksToDelete = tasks.filter { $0.title == "ProvaProva" }
//        
//        for task in tasksToDelete {
//            modelContext.delete(task)
//        }
//        
//        do {
//            try modelContext.save()
//        } catch {
//            assertionFailure("Bulk delete failed: \(error)")
//        }
//        
//        NotificationManager.shared.refresh(force: true)
//    }
//    
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
    

    private func computeFilterSignature() -> String {
        tasks.map {
            "\($0.id.uuidString)-\($0.isCompleted)-\($0.deadLine?.timeIntervalSince1970 ?? 0)"
        }.joined()
        + "|\(searchText)|\(selectedTagFilter?.rawValue ?? "nil")|\(selectedPriorityFilter?.rawValue ?? -1)"
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
    
    private var badgeStyle: BadgeColorStyle {
        BadgeColorStyle(rawValue: badgeColorRaw) ?? .default
    }
    
    @AppStorage("selectedTaskRowStyle") private var selectedRowStyle: Int = 0
    
    
    var rowStyleToUse: Int {
        
        let calendar = Calendar.current
        let startOfTomorrow = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: Date())!
        )
        
        if let deadline = task.deadLine,
           deadline < startOfTomorrow && !task.isCompleted {
            
            return 100
        } else {
            return selectedRowStyle
        }
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
            statusColor: task.iconColor,
            hasValidAttachments: !attachments.isEmpty,
            hasLocation: task.locationName?.isEmpty == false,
            badgeText: task.daysRemainingBadgeText,
            prioritySystemImage: task.priority.systemImage,
            deadLine: task.deadLine,
            reminderOffsetMinutes: task.reminderOffsetMinutes,
            shouldShowBadge: shouldDisplayBadge,
            isCompleted: task.isCompleted
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
                showBadgeOnlyWithPriority: showBadgeOnlyWithPriority, rowStyle: TaskRowStyle(rawValue: rowStyleToUse) ?? .style0 )
        }
        
        .contentShape(Rectangle())
        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
        .frame(height: rowStyleToUse == 100 ? 60 : 46)//altezza ROW
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
    @AppStorage("TaskListStyle") private var listStyleChoice: TaskListStyle = .cards
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
                    Color(uiColor: .secondarySystemBackground).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(
                            isTaskOverdue(task.deadLine) || isTaskOverdueNow(task.deadLine) ? .red :
                                isTaskToday(task.deadLine) ? .orange :
                                    .secondary,
                            lineWidth:
                                (isTaskToday(task.deadLine) || isTaskOverdue(task.deadLine))
                            ? 2.5 : 0.7
                        )
                )
        }
        
        private func isTaskToday(_ date: Date?) -> Bool {
            guard let date else { return false }
            return Calendar.current.isDateInToday(date)
        }
        
        private func isTaskOverdue(_ date: Date?) -> Bool {
            guard let date else { return false }
            return date < Calendar.current.startOfDay(for: Date())
        }
        
        private func isTaskOverdueNow(_ date: Date?) -> Bool {
            guard let date = date else { return false }
            return date < Date() // Se la data del task è "minore" di adesso, è scaduta
        }
    }
    
    var body: some View {
        
        Section(String(localized:"To do (\(tasks.count))")) {
            
            ForEach(tasks) { t in
                
                TaskRow(task: t)
                    .id(t.persistentModelID)
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
                                NotificationManager.shared.refresh(force: true)
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
        
        task.isCompleted.toggle()
        
        if task.isCompleted {
            task.completedAt = .now
            task.snoozeUntil = nil
        } else {
            task.completedAt = nil
            task.snoozeUntil = nil
        }
        
        try? modelContext.save()
        
        NotificationManager.shared.refresh(force: true)
    }
}

struct CompletedSectionView: View {
    @AppStorage("TaskListStyle") private var listStyleChoice: TaskListStyle = .cards
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
                    Color(uiColor: .secondarySystemBackground).opacity(0.5))
        }
    }
    var body: some View {
        
        Section(String(localized:"Completed (\(tasks.count))")) {
            
            
            ForEach(tasks) { t in
                
                TaskRow(task: t)
                    .id(t.persistentModelID)
                //                    .opacity(0.8)
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
                                NotificationManager.shared.refresh(force: true)
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
        
        task.isCompleted.toggle()
        
        if task.isCompleted {
            task.completedAt = .now
            task.snoozeUntil = nil
        } else {
            task.completedAt = nil
            task.snoozeUntil = nil
        }
        
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save context: \(error)")
        }
        
        NotificationManager.shared.refresh(force: true)
    }
}
