import SwiftUI
import SwiftData

struct Dashboard: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTask: TodoTask?
    @State private var selectedTrip: TripList?
    @State private var selectedDocument: DocumentItem?
    @State private var selectedLoyaltyCard: LoyaltyCard?
    @State private var selectedWeatherDate: Date?
    @State private var selectedNote: Note?
    @State private var recentWalletLogos: [String: Data] = [:]
    
    
    @State private var recoveryResult: AttachmentRecoveryResult?
    @State private var showRecoveryAlert = false
    
    @State private var recoveryCheck: AssetRecoveryCoordinator.RecoveryCheckResult?
    @State private var showRecoveryConfirmation = false
    
    @State private var showNoRecoveryNeededAlert = false
    
    private static let activeTasksPredicate =
        #Predicate<TodoTask> { !$0.isCompleted }

    @Query(filter: Self.activeTasksPredicate)
    private var activeTasks: [TodoTask]
    

    @Query
    private var trips: [TripList]

    @Query
    private var documents: [DocumentItem]

    @Query
    private var loyaltyCards: [LoyaltyCard]
    
    @Query
    private var notes: [Note]

    private let weatherManager = WeatherManager.shared

    private enum ContinueDestination {
        case trip(TripList)
        case document(DocumentItem)
        case loyaltyCard(LoyaltyCard)
        case note(Note)
    }

    private struct ContinueItem: Identifiable {
        let id: String
        let title: String
        let type: String
        let systemImage: String?
        let logoRelativePath: String?
        let lastOpenedAt: Date
        let destination: ContinueDestination
    }

    private var continueItems: [ContinueItem] {

        let tripItems: [ContinueItem] = trips.compactMap { trip in
            guard let lastOpenedAt = trip.lastOpenedAt else { return nil }

            return ContinueItem(
                id: "trip-\(trip.id)",
                title: trip.name,
                type: String(localized: "Trips"),
                systemImage: trip.icon,
                logoRelativePath: nil,
                lastOpenedAt: lastOpenedAt,
                destination: .trip(trip)
            )
        }

        let documentItems: [ContinueItem] = documents.compactMap { document in
            guard let lastOpenedAt = document.lastOpenedAt else { return nil }

            return ContinueItem(
                id: "document-\(document.id)",
                title: document.name,
                type: String(localized: "Documents"),
                systemImage: document.documentType.systemImage,
                logoRelativePath: nil,
                lastOpenedAt: lastOpenedAt,
                destination: .document(document)
            )
        }

        let cardItems: [ContinueItem] = loyaltyCards.compactMap { card in
            guard let lastOpenedAt = card.lastOpenedAt else { return nil }

            return ContinueItem(
                id: "card-\(card.id)",
                title: card.storeName,
                type: String(localized: "Wallet"),
                systemImage: nil,
                logoRelativePath:
                    card.logoAsset?.relativePath
                    ?? card.loyaltyLogoRelativePath,
                lastOpenedAt: lastOpenedAt,
                destination: .loyaltyCard(card)
            )
        }
        let noteItems: [ContinueItem] = notes.compactMap { note in
            guard let lastOpenedAt = note.lastOpenedAt else { return nil }

            return ContinueItem(
                id: "note-\(note.id)",
                title: note.title.isEmpty
                    ? String(localized: "Untitled")
                    : note.title,
                type: String(localized: "Notes"),
                systemImage: "note.text",
                logoRelativePath: nil,
                lastOpenedAt: lastOpenedAt,
                destination: .note(note)
            )
        }
        return Array(
            ((tripItems + documentItems + cardItems + noteItems))
                .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
                .prefix(3)
        )
    }

    private var todayTasksCount: Int {
        activeTasks.filter {
            guard let deadline = $0.deadLine else { return false }
            return Calendar.current.isDateInToday(deadline)
        }.count
    }

    private var todayTasks: [TodoTask] {
        activeTasks
            .filter {
                guard let deadline = $0.deadLine else { return false }
                return Calendar.current.isDateInToday(deadline)
            }
            .sorted {
                ($0.deadLine ?? .distantFuture) < ($1.deadLine ?? .distantFuture)
            }
    }

    private var tomorrowTasksCount: Int {
        activeTasks.filter {
            guard let deadline = $0.deadLine else { return false }
            return Calendar.current.isDateInTomorrow(deadline)
        }.count
    }

    private var tomorrowTasks: [TodoTask] {
        activeTasks
            .filter {
                guard let deadline = $0.deadLine else { return false }
                return Calendar.current.isDateInTomorrow(deadline)
            }
            .sorted {
                ($0.deadLine ?? .distantFuture) < ($1.deadLine ?? .distantFuture)
            }
    }

    private var overdueTodayCount: Int {
        activeTasks.filter {
            guard let deadline = $0.deadLine else { return false }
            return Calendar.current.isDateInToday(deadline) && deadline < .now
        }.count
    }

    private var overduePreviousDaysCount: Int {
        let startOfToday = Calendar.current.startOfDay(for: .now)

        return activeTasks.filter {
            guard let deadline = $0.deadLine else { return false }
            return deadline < startOfToday
        }.count
    }
    private func hide(_ item: ContinueItem) {
        switch item.destination {
        case .trip(let trip):
            trip.lastOpenedAt = nil
        case .document(let document):
            document.lastOpenedAt = nil
        case .loyaltyCard(let card):
            card.lastOpenedAt = nil
        case .note(let note):
            note.lastOpenedAt = nil
        }

        try? modelContext.save()
    }

    var body: some View {
        ZStack {
            AppGlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // MARK: - Oggi

                    Button {
                        NotificationCenter.default.post(
                            name: Notification.Name("DashboardOpenList"),
                            object: nil
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {

                            // Header Oggi
                            HStack(alignment: .top) {
                                Text("Today")
                                    .font(.largeTitle.bold())

                                Spacer()

                                if settings.showWeatherForecast,
                                   let weather = weatherManager.weather(for: Date()) {

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Button {
                                            selectedWeatherDate = .now
                                        } label: {
                                            Image(
                                                systemName:
                                                    weatherManager.representativeSymbol(for: Date())
                                            )
                                            .symbolRenderingMode(.multicolor)
                                            .saturation(
                                                colorScheme == .light ? 1.25 : 1.0
                                            )
                                            .brightness(
                                                colorScheme == .light ? -0.2 : 0.0
                                            )
                                            .font(.title.weight(.medium))
                                        }
                                        .buttonStyle(.plain)

                                        HStack(spacing: 4) {
                                            Text("\(weather.minTemperature)°")
                                                .foregroundStyle(
                                                    weather.minTemperature >= 35 ? .red :
                                                    weather.minTemperature >= 30 ? .orange :
                                                    weather.minTemperature <= 0
                                                        ? Color(
                                                            red: 0.65,
                                                            green: 0.88,
                                                            blue: 1.00
                                                        )
                                                        : .primary.opacity(0.75)
                                                )

                                            Text("/")
                                                .foregroundStyle(.secondary)

                                            Text("\(weather.maxTemperature)°")
                                                .foregroundStyle(
                                                    weather.maxTemperature >= 35 ? .red :
                                                    weather.maxTemperature >= 30 ? .orange :
                                                    weather.maxTemperature <= 0
                                                        ? Color(
                                                            red: 0.65,
                                                            green: 0.88,
                                                            blue: 1.00
                                                        )
                                                        : .primary
                                                )
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)

                            // Numero attività
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(todayTasksCount)")
                                    .font(.system(size: 58, weight: .bold, design: .rounded))

                                Text(todayTasksCount == 1
                                     ? "task to complete"
                                     : "tasks to complete")
                                    .font(.title3)
                                    .foregroundStyle(.primary.opacity(0.9))
                            }
                            .padding(.top, 2)

                            // Attività
                            if !todayTasks.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(
                                        todayTasks,
                                        id: \.persistentModelID
                                    ) { task in
                                        dashboardTaskRow(task)
                                    }
                                }
                                .padding(.top, 4)
                            }

                            if overduePreviousDaysCount > 0 {
                                Text(
                                    "\(overduePreviousDaysCount) overdue from previous days"
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(
                            RoundedRectangle(
                                cornerRadius: 18,
                                style: .continuous
                            )
                            .fill(.regularMaterial)
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 18,
                                style: .continuous
                            )
                            .stroke(
                                .white.opacity(0.10),
                                lineWidth: 1
                            )
                        }
                    }
                    .buttonStyle(.plain)


                    // MARK: - Domani

                    if settings.showDashboardTomorrow &&
                       tomorrowTasksCount > 0 {

                        Button {
                            NotificationCenter.default.post(
                                name: Notification.Name("DashboardOpenList"),
                                object: nil
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {

                                HStack(alignment: .firstTextBaseline) {
                                    Text("Tomorrow")
                                        .font(.title3.weight(.semibold))

                                    Spacer()

                                    if settings.showWeatherForecast,
                                       let tomorrowWeather = weatherManager.weather(
                                           for: Calendar.current.date(
                                               byAdding: .day,
                                               value: 1,
                                               to: Date()
                                           ) ?? Date()
                                       ) {

                                        HStack(spacing: 5) {
                                            Image(
                                                systemName:
                                                    weatherManager.representativeSymbol(
                                                        for: Calendar.current.date(
                                                            byAdding: .day,
                                                            value: 1,
                                                            to: Date()
                                                        ) ?? Date()
                                                    )
                                            )
                                            .symbolRenderingMode(.multicolor)
                                            .font(.subheadline)

                                            Text("\(tomorrowWeather.minTemperature)°")
                                                .foregroundStyle(.secondary)

                                            Text("/")
                                                .foregroundStyle(.secondary)

                                            Text("\(tomorrowWeather.maxTemperature)°")
                                        }
                                        .font(.caption)
                                    }
                                }

                                Text(
                                    "^[\(tomorrowTasksCount) tasks scheduled](inflect: true)"
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                                if !tomorrowTasks.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(
                                            tomorrowTasks,
                                            id: \.persistentModelID
                                        ) { task in
                                            dashboardTaskRow(task)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()
                        .overlay(.white.opacity(0.3))
                    // MARK: - Recenti

                    if settings.showDashboardContinue &&
                       !continueItems.isEmpty {

                        VStack(alignment: .leading, spacing: 12) {

                            HStack {
                                Label(
                                    "Recent",
                                    systemImage:
                                        "clock.arrow.trianglehead.clockwise.rotate.90.path.dotted"
                                )
                                .font(.headline)
                            }

                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(), spacing: 8),
                                    count: min(continueItems.count, 3)
                                ),
                                spacing: 8
                            ) {
                                ForEach(continueItems) { item in

                                    switch item.destination {

                                    case .trip(let trip):
                                        Button {
                                            selectedTrip = trip
                                        } label: {
                                            sectionCard(
                                                title: item.title,
                                                type: item.type,
                                                systemImage: item.systemImage,
                                                logoData: nil,
                                                isCompleted: isTripComplete(trip),
                                                remainingItems:
                                                    remainingTripItems(for: trip)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button {
                                                hide(item)
                                            } label: {
                                                Label(
                                                    "Hide",
                                                    systemImage: "eye.slash"
                                                )
                                            }
                                        }

                                    case .note(let note):
                                        Button {
                                            selectedNote = note
                                        } label: {
                                            sectionCard(
                                                title: item.title,
                                                type: item.type,
                                                systemImage: item.systemImage,
                                                logoData: nil,
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button {
                                                hide(item)
                                            } label: {
                                                Label(
                                                    "Hide",
                                                    systemImage: "eye.slash"
                                                )
                                            }
                                        }

                                    case .document(let document):
                                        Button {
                                            selectedDocument = document
                                        } label: {
                                            sectionCard(
                                                title: item.title,
                                                type: item.type,
                                                systemImage: item.systemImage,
                                                logoData: nil,
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button {
                                                hide(item)
                                            } label: {
                                                Label(
                                                    "Hide",
                                                    systemImage: "eye.slash"
                                                )
                                            }
                                        }

                                    case .loyaltyCard(let card):
                                        Button {
                                            selectedLoyaltyCard = card
                                        } label: {
                                            sectionCard(
                                                title: item.title,
                                                type: item.type,
                                                systemImage: item.systemImage,
                                                logoData: recentWalletLogos[item.id]
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .task(id: item.id) {
                                            guard let relativePath = item.logoRelativePath else {
                                                return
                                            }

                                            let data = WalletAssetStore.loadData(
                                                relativePath: relativePath
                                            )

                                            guard !Task.isCancelled, let data else {
                                                return
                                            }

                                            recentWalletLogos[item.id] = data
                                        }
                                        .contextMenu {
                                            Button {
                                                hide(item)
                                            } label: {
                                                Label(
                                                    "Hide",
                                                    systemImage: "eye.slash"
                                                )
                                            }
                                        }                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .alert(
            "Attachment Recovery",
            isPresented: $showNoRecoveryNeededAlert
        ) {

            Button("OK") { }

        } message: {

            Text(
                String(
                    localized:
                        "No duplicate asset folders were found."
                )
            )

        }
        .alert(
            "Attachment Recovery",
            isPresented: $showRecoveryConfirmation,
            presenting: recoveryCheck
        ) { check in

            Button(
                String(localized: "Repair")
            ) {

                recoveryResult = AssetRecoveryCoordinator.repairAll(context: modelContext)

                showRecoveryAlert = true

            }

            Button(
                String(localized: "Cancel"),
                role: .cancel
            ) {
            }

        } message: { check in

            Text(
                """
                \(check.duplicateFolders.count) duplicate asset folder(s) detected.

                Automatic recovery has been suspended because Asset Recovery Diagnostics is enabled.

                Press Repair to merge the folders.
                """
            )

        }
        
        .alert(
            "Attachment Recovery",
            isPresented: $showRecoveryAlert
        ) {

            Button("OK") { }

        } message: {

            if let result = recoveryResult {

                Text("""
                Recovery folders: \(result.folders)

                Copied: \(result.copied)
                Skipped: \(result.skipped)
                Errors: \(result.errors)
                """)

            }

        }
        .contentMargins(.bottom, 70, for: .scrollContent)
        .containerBackground(.clear, for: .navigation)
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            
            if DiagnosticsOptions.assetRecoveryDiagnostics {
                ToolbarItem(placement: .topBarTrailing) {
                    
                    Button {

                        let result = AssetRecoveryCoordinator.checkIfNeeded()

                        guard result.needsRepair else {

                            showNoRecoveryNeededAlert = true
                            return

                        }

                        recoveryCheck = result
                        showRecoveryConfirmation = true

                    } label: {

                        Image(systemName: "wrench.and.screwdriver")

                    }
                    
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Toggle("Show Tomorrow", isOn: Bindable(settings).showDashboardTomorrow)
                    Toggle("Show Recent", isOn: Bindable(settings).showDashboardContinue)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    OverviewView()
                } label: {
                    Image(systemName: "line.3.horizontal.button.angledtop.vertical.right")
                }
            }

        }
        .navigationDestination(item: $selectedTask) { task in
            TaskDetailView(task: task)
        }
        .navigationDestination(item: $selectedTrip) { trip in
            TripChecklistView(category: trip)
        }
        .navigationDestination(item: $selectedDocument) { document in
            DocumentDetailView(document: document)
        }
        .navigationDestination(item: $selectedLoyaltyCard) { card in
            LoyaltyCardDetailView(card: card)
        }
        .navigationDestination(item: $selectedNote) { note in
            NoteEditorView(note: note)
        }
        .navigationDestination(item: $selectedWeatherDate) {
            date in
            WeatherDayView(
                date: date,
                showsCloseButton: false,
                cameFromForecast: false
            )
        }

        .task {
            await weatherManager.refreshIfNeeded()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name("DashboardReset")
            )
        ) { _ in
            selectedTask = nil
            selectedTrip = nil
            selectedDocument = nil
            selectedLoyaltyCard = nil
            selectedWeatherDate = nil
        }
    }

    
    
    @ViewBuilder
    private func dashboardTaskRow(_ task: TodoTask) -> some View {
        let isOverdue = (task.deadLine ?? .now) < .now

        Button {
            selectedTask = task
        } label: {
            HStack(spacing: 8) {

                if settings.highlightEnabled,
                   task.priority == .critical {
                    RoundedRectangle(
                        cornerRadius: TaskRowTheme.highlightCornerRadius
                    )
                    .fill(
                        Color(hex: settings.highlightColorHex) ?? .red
                    )
                    .frame(
                        width: TaskRowMetrics.highlightBarWidth,
                        height: TaskRowMetrics.highlightBarHeight - 12
                    )
                } else {
                    Color.clear
                        .frame(
                            width: TaskRowMetrics.highlightBarWidth,
                            height: TaskRowMetrics.highlightBarHeight - 12
                        )
                }

                Image(
                    systemName: task.mainTag?.mainIcon ?? task.status.icon
                )
                .symbolRenderingMode(
                    settings.iconStyle == .polychrome && task.mainTag != nil
                        ? .palette
                        : .monochrome
                )
                .foregroundStyle(
                    settings.iconStyle == .polychrome
                        ? task.iconColor
                        : .primary,
                    .primary
                )
                .opacity(0.9)
                .frame(width: 18)

                if let deadline = task.deadLine {
                    Text(
                        deadline.formatted(
                            .dateTime
                                .hour()
                                .minute()
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }

                Text(task.title)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .overlay(alignment: .bottomLeading) {
                        if isOverdue {
                            Rectangle()
                                .fill(.red)
                                .frame(height: 1.5)
                                .offset(y: 2)
                        }
                    }

                if task.recurrenceRule != nil {
                    Image(
                        systemName: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func sectionCard(
        title: String,
        type: String,
        systemImage: String?,
        logoData: Data?,
        isCompleted: Bool = false,
        remainingItems: Int? = nil
    ) -> some View {

        VStack(alignment: .center, spacing: 0) {

            // Categoria
            Text(type)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 18)

            Spacer(minLength: 0)

            // Immagine / icona
            Group {
                if let logoData,
                   let uiImage = UIImage(data: logoData) {

                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 8,
                                style: .continuous
                            )
                        )

                } else if let systemImage {

                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 40, height: 40)
                }
            }
            .frame(width: 40, height: 40)

            Spacer(minLength: 0)

            // Area titolo + dettaglio
            VStack(alignment: .center, spacing: 2) {

                if let remainingItems {
                    Text(
                        "\(remainingItems) \(String(localized: "remaining"))"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Text(title)
                    .font(.footnote)
                    .foregroundStyle(
                        isCompleted ? .green : .primary
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .bottom)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 36, alignment: .bottom)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .padding(12)
        .background(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .fill(.regularMaterial)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                .white.opacity(0.10),
                lineWidth: 1
            )
        }
    }

    private func isTripComplete(_ trip: TripList) -> Bool {
        let items = trip.sections.flatMap(\.items)
        return !items.isEmpty && items.allSatisfy(\.isChecked)
    }

    private func remainingTripItems(for trip: TripList) -> Int {
        trip.sections.flatMap(\.items).filter { !$0.isChecked }.count
    }

    @ViewBuilder
    private func navigationCard(title: String, systemImage: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.primary)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
