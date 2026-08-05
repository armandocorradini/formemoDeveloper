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

    private let weatherManager = WeatherManager.shared

    private enum ContinueDestination {
        case trip(TripList)
        case document(DocumentItem)
        case loyaltyCard(LoyaltyCard)
    }

    private struct ContinueItem: Identifiable {
        let id: String
        let title: String
        let systemImage: String?
        let logoData: Data?
        let lastOpenedAt: Date
        let destination: ContinueDestination
    }

    private var continueItems: [ContinueItem] {

        let tripItems: [ContinueItem] = trips.compactMap { trip in
            guard let lastOpenedAt = trip.lastOpenedAt else { return nil }

            return ContinueItem(
                id: "trip-\(trip.id)",
                title: trip.name,
                systemImage: trip.icon,
                logoData: nil,
                lastOpenedAt: lastOpenedAt,
                destination: .trip(trip)
            )
        }

        let documentItems: [ContinueItem] = documents.compactMap { document in
            guard let lastOpenedAt = document.lastOpenedAt else { return nil }

            return ContinueItem(
                id: "document-\(document.id)",
                title: document.name,
                systemImage: document.documentType.systemImage,
                logoData: nil,
                lastOpenedAt: lastOpenedAt,
                destination: .document(document)
            )
        }

        let cardItems: [ContinueItem] = loyaltyCards.compactMap { card in
            guard let lastOpenedAt = card.lastOpenedAt else { return nil }

            return ContinueItem(
                id: "card-\(card.id)",
                title: card.storeName,
                systemImage: nil,
                logoData: {

                    if let relativePath = card.logoAsset?.relativePath {
                        return WalletAssetStore.loadData(
                            relativePath: relativePath
                        )
                    }

                    if let relativePath = card.loyaltyLogoRelativePath {
                        return WalletAssetStore.loadData(
                            relativePath: relativePath
                        )
                    }

                    return nil

                }(),
                lastOpenedAt: lastOpenedAt,
                destination: .loyaltyCard(card)
            )
        }

        return Array(
            (tripItems + documentItems + cardItems)
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
        }

        try? modelContext.save()
    }

    var body: some View {
        ZStack {
            AppGlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Section 1: Oggi
                    Button {
                        NotificationCenter.default.post(
                            name: Notification.Name("DashboardOpenList"),
                            object: nil
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
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
                                                systemName: weatherManager.representativeSymbol(for: Date())
                                            )
                                            .symbolRenderingMode(.multicolor)
                                            .saturation(colorScheme == .light ? 1.25 : 1.0)
                                            .brightness(colorScheme == .light ? -0.2 : 0.0)
                                            .font(.title.weight(.medium))
                                        }
                                        .buttonStyle(.plain)

                                        HStack(spacing: 4) {

                                            Text("\(weather.minTemperature)°")
                                                .foregroundStyle(
                                                    weather.minTemperature >= 35 ? .red :
                                                    weather.minTemperature >= 30 ? .orange :
                                                    weather.minTemperature <= 0 ? Color(red: 0.65, green: 0.88, blue: 1.00) :
                                                    .primary.opacity(0.75)
                                                )

                                            Text("/")
                                                .foregroundStyle(.secondary)

                                            Text("\(weather.maxTemperature)°")
                                                .foregroundStyle(
                                                    weather.maxTemperature >= 35 ? .red :
                                                    weather.maxTemperature >= 30 ? .orange :
                                                    weather.maxTemperature <= 0 ? Color(red: 0.65, green: 0.88, blue: 1.00) :
                                                    .primary
                                                )
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)

                            Text("^[\(todayTasksCount) tasks to complete](inflect: true)")
                                .font(.title3)
                                .foregroundStyle(.primary)

                            if !todayTasks.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(todayTasks.prefix(5)), id: \.persistentModelID) { task in

                                        let isOverdue = (task.deadLine ?? .now) < .now

                                        Button {
                                            selectedTask = task
                                        } label: {

                                            HStack(spacing: 8) {

                                                Group {
                                                    if settings.highlightEnabled,
                                                       task.priority == .critical {
                                                        RoundedRectangle(cornerRadius: TaskRowTheme.highlightCornerRadius)
                                                            .fill(Color(hex: settings.highlightColorHex) ?? .red)
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
                                                }

                                                Image(systemName: task.mainTag?.mainIcon ?? task.status.icon)
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
                                                    Image(systemName: "arrow.triangle.2.circlepath")
                                                        .font(.caption)
                                                        .foregroundStyle(.blue)
                                                }
                                            }
                                            .font(.subheadline)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 4)
                            }

                            if overduePreviousDaysCount > 0 {
                                Text("\(overduePreviousDaysCount) overdue from previous days")

                                    .font(.subheadline)

                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.regularMaterial)
                                .shadow(
                                    color: .black.opacity(0.10),
                                    radius: 14,
                                    y: 7
                                )
                                .shadow(
                                    color: .white.opacity(0.08),
                                    radius: 1,
                                    y: -1
                                )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.white.opacity(0.10), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)

                    // Show Tomorrow section only if enabled and there are tomorrow tasks
                    if settings.showDashboardTomorrow && tomorrowTasksCount > 0 {
                        Button {
                            NotificationCenter.default.post(
                                name: Notification.Name("DashboardOpenList"),
                                object: nil
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {

                                    Text("Tomorrow")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if settings.showWeatherForecast,
                                       let tomorrowWeather = weatherManager.weather(
                                            for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                                       ) {

                                        VStack(alignment: .trailing, spacing: 4) {

                                            Button {
                                                selectedWeatherDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                                            } label: {
                                                Image(
                                                    systemName: weatherManager.representativeSymbol(
                                                        for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                                                    )
                                                )
                                                .symbolRenderingMode(.multicolor)
                                                .saturation(colorScheme == .light ? 1.25 : 1.0)
                                                .brightness(colorScheme == .light ? -0.2 : 0.0)
                                                .font(.subheadline.weight(.medium))
                                            }
                                            .buttonStyle(.plain)

                                            HStack(spacing: 4) {

                                                Text("\(tomorrowWeather.minTemperature)°")
                                                    .foregroundStyle(
                                                        tomorrowWeather.minTemperature >= 35 ? .red :
                                                        tomorrowWeather.minTemperature >= 30 ? .orange :
                                                        tomorrowWeather.minTemperature <= 0 ? Color(red: 0.65, green: 0.88, blue: 1.00) :
                                                        .primary.opacity(0.75)
                                                    )

                                                Text("/")
                                                    .foregroundStyle(.secondary)

                                                Text("\(tomorrowWeather.maxTemperature)°")
                                                    .foregroundStyle(
                                                        tomorrowWeather.maxTemperature >= 35 ? .red :
                                                        tomorrowWeather.maxTemperature >= 30 ? .orange :
                                                        tomorrowWeather.maxTemperature <= 0 ? Color(red: 0.65, green: 0.88, blue: 1.00) :
                                                        .primary
                                                    )
                                            }
                                            .font(.caption2)
                                        }
                                    }
                                }

                                Text("^[\(tomorrowTasksCount) tasks scheduled](inflect: true)")
                                    .foregroundStyle(.primary)

                                if !tomorrowTasks.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(Array(tomorrowTasks.prefix(5)), id: \.persistentModelID) { task in
                                            Button {
                                                selectedTask = task
                                            } label: {
                                                HStack(spacing: 8) {

                                                    Group {
                                                        if settings.highlightEnabled,
                                                           task.priority == .critical {
                                                            RoundedRectangle(cornerRadius: TaskRowTheme.highlightCornerRadius)
                                                                .fill(Color(hex: settings.highlightColorHex) ?? .red)
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
                                                    }

                                                    Image(systemName: task.mainTag?.mainIcon ?? task.status.icon)
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

                                                    if task.recurrenceRule != nil {
                                                        Image(systemName: "arrow.triangle.2.circlepath")
                                                            .font(.caption)
                                                            .foregroundStyle(.blue)
                                                    }
                                                }
                                                .font(.subheadline)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.regularMaterial)
                                    .shadow(
                                        color: .black.opacity(0.10),
                                        radius: 12,
                                        y: 6
                                    )
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.white.opacity(0.10), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Show Continue section only if enabled and there are items
                    if settings.showDashboardContinue && !continueItems.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Recent", systemImage: "clock.arrow.trianglehead.clockwise.rotate.90.path.dotted")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            VStack(spacing: 8) {
                                ForEach(continueItems) { item in
                                    switch item.destination {
                                    case .trip(let trip):
                                        Button {
                                            selectedTrip = trip
                                        } label: {
                                            sectionCard(
                                                title: item.title,
                                                systemImage: item.systemImage,
                                                logoData: item.logoData,
                                                isCompleted: isTripComplete(trip),
                                                remainingItems: remainingTripItems(for: trip)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                            Button {
                                                hide(item)
                                            } label: {
                                                Label("Hide", systemImage: "eye.slash")
                                            }
                                            .tint(.gray)
                                        }
                                        .contextMenu {
                                            Button {
                                                hide(item)
                                            } label: {
                                                Label("Hide", systemImage: "eye.slash")
                                            }
                                        }
                                    case .document(let document):
                                        Button {
                                            selectedDocument = document
                                        } label: {
                                            sectionCard(
                                                title: item.title,
                                                systemImage: item.systemImage,
                                                logoData: item.logoData
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                            Button {
                                                hide(item)
                                            } label: {
                                                Label("Hide", systemImage: "eye.slash")
                                            }
                                            .tint(.gray)
                                        }
                                        .contextMenu {
                                            Button {
                                                hide(item)
                                            } label: {
                                                Label("Hide", systemImage: "eye.slash")
                                            }
                                        }
                                    case .loyaltyCard(let card):
                                        Button {
                                            selectedLoyaltyCard = card
                                        } label: {
                                            sectionCard(
                                                title: item.title,
                                                systemImage: item.systemImage,
                                                logoData: item.logoData
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                            Button {
                                                hide(item)
                                            } label: {
                                                Label("Hide", systemImage: "eye.slash")
                                            }
                                            .tint(.gray)
                                        }
                                        .contextMenu {
                                            Button {
                                                hide(item)
                                            } label: {
                                                Label("Hide", systemImage: "eye.slash")
                                            }
                                        }
                                    }
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
        .contentMargins(.bottom, 70, for: .scrollContent)
        .containerBackground(.clear, for: .navigation)
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .navigationDestination(item: $selectedWeatherDate) { date in
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
    private func sectionCard(
        title: String,
        systemImage: String?,
        logoData: Data?,
        isCompleted: Bool = false,
        remainingItems: Int? = nil
    ) -> some View {
        HStack(spacing: 16) {
            Group {
                if let logoData,
                   let uiImage = UIImage(data: logoData) {

                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 24, height: 24)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 6)
                        )

                } else if let systemImage {

                    Image(systemName: systemImage)
                        .font(.body)
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(isCompleted ? .green : .primary)

                if let remainingItems {
                    Text("\(remainingItems) \(String(localized: "remaining"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(
                    color: .black.opacity(0.10),
                    radius: 12,
                    y: 6
                )
                .shadow(
                    color: .white.opacity(0.08),
                    radius: 1,
                    y: -1
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.10), lineWidth: 1)
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
