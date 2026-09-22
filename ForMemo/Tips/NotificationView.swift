import SwiftUI
import UserNotifications
import SwiftData

struct PendingNotificationInfo: Identifiable {
    
    let id: String
    let title: String
    let body: String
    let triggerDate: Date?
    let identifier: String
    let categoryIdentifier: String
    let taskID: UUID?
    let deadlineDate: Date?
    
    var notificationType: String {
        let lower = identifier.lowercased()
        
        if lower.contains("snooze") {
            return String(localized: "Snooze")
        }
        
        if lower.contains("deadline") {
            return String(localized: "Deadline")
        }
        
        if lower.contains("reminder") {
            return String(localized: "Reminder")
        }
        
        if lower.contains("document") {
            return String(localized: "Document")
        }
        
        if lower.contains("global") {
            return String(localized: "Global")
        }
        
        return String(localized: "Notification")
    }
    
    var notificationEmoji: String {
        let lower = identifier.lowercased()
        
        if lower.contains("snooze") {
            return "⏲️"
        }
        
        if lower.contains("deadline") {
            return "⏰"
        }
        
        if lower.contains("reminder") {
            return "🔔"
        }
        
        if lower.contains("document") {
            return "📄"
        }
        
        if lower.contains("global") {
            return "⏱️"
        }
        
        return "🔔"
    }
}

// MARK: - Notification View

struct NotificationView: View {
    
    @State private var pending: [PendingNotificationInfo] = []
    @State private var isLoading = true
    @State private var hasLoadedNotifications = false
    @Query private var documents: [DocumentItem]
    
    var body: some View {
        ZStack {
            AppGlassBackground()
            
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                } else if pending.isEmpty {
                    ContentUnavailableView {
                        Label(
                            String(localized: "No Scheduled Notifications"),
                            systemImage: "bell.slash"
                        )
                    } description: {
                        Text(
                            String(
                                localized: "There are currently no pending notifications."
                            )
                        )
                    }
                } else {
                    VStack(spacing: 0) {
                        
                        HStack {
                            Label(
                                "\(pending.count)",
                                systemImage: "bell.badge"
                            )
                            .font(.headline)
                            .padding(.leading, 24)
                            .foregroundStyle(.blue)
                            
                            Spacer()
                            
                            Button {
                                Task {
                                    await refreshAndReload()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .padding(.trailing, 24)
                        }
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        
                        List {
                            Section {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(
                                        String(localized: "Upcoming Notifications")
                                    )
                                    .font(.subheadline.bold())
                                    
                                    Text(
                                        String(
                                            localized: "These are the next notifications currently scheduled on your device. The time shown below each item indicates when the next alert will appear. Additional reminders, deadlines, and document expiration alerts will be scheduled automatically as needed."
                                        )
                                    )
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                                }
                            }
                            .listRowBackground(Color.clear)
                            
                            Section {
                                ForEach(pending) { item in
                                    NotificationRow(
                                        item: item,
                                        documents: documents
                                    )
                                }
                            }
                        }
                        .contentMargins(
                            .bottom,
                            70,
                            for: .scrollContent
                        )
                        .scrollContentBackground(.hidden)
                        .scrollEdgeEffectHidden(
                            true,
                            for: .top
                        )
                        .background(Color.clear)
                    }
                }
            }
        }
        .navigationTitle(
            String(localized: "Notifications")
        )
        .navigationBarTitleDisplayMode(.inline)
        .task {
            print("🟢 NotificationView: .task")
            
            guard !hasLoadedNotifications else {
                print("🟢 NotificationView: already loaded — skip")
                return
            }
            
            hasLoadedNotifications = true
            await loadPendingNotifications()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )
        ) { _ in
            print("🟠 NotificationView: didBecomeActive")
            Task {
                await loadPendingNotifications()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .taskDidChange
            )
        ) { _ in
            Task {
                await refreshAndReload()
            }
        }
    }
    
    // MARK: - Date Formatting
    
    private func triggerText(for date: Date?) -> String {
        guard let date else {
            return String(localized: "Unknown date")
        }
        
        let absolute = date.formatted(
            date: .complete,
            time: .shortened
        )
        
        let totalMinutes = max(
            Int(date.timeIntervalSinceNow / 60),
            0
        )
        
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        let relative: String
        
        if totalMinutes < 60 {
            relative = "\(minutes) min"
        } else if minutes == 0 {
            relative = "\(hours) h"
        } else {
            relative = "\(hours) h \(minutes) min"
        }
        
        return "\(absolute) • \(relative)"
    }
    
    private func notificationDateText(
        for date: Date?
    ) -> String {
        guard let date else {
            return String(localized: "Unknown date")
        }
        
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return date.formatted(
                date: .omitted,
                time: .shortened
            )
        }
        
        return date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .year()
                .hour()
                .minute()
        )
    }
    
    private func deadlineDateText(
        for date: Date?
    ) -> String {
        guard let date else {
            return String(localized: "Unknown date")
        }
        
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            let time = date.formatted(
                date: .omitted,
                time: .shortened
            )
            
            return String(
                localized: "Today • \(time)"
            )
        }
        
        return date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .year()
                .hour()
                .minute()
        )
    }
    
    private func notificationDateTextWithToday(
        for date: Date?
    ) -> String {
        guard let date else {
            return String(localized: "Unknown date")
        }
        
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            let time = date.formatted(
                date: .omitted,
                time: .shortened
            )
            
            return String(
                localized: "Today • \(time)"
            )
        }
        
        return date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .year()
                .hour()
                .minute()
        )
    }
    
    // MARK: - Refresh
    
    @MainActor
    private func refreshAndReload() async {
        await NotificationManager.shared.refreshAndWait(
            force: true
        )
        
        await loadPendingNotifications()
    }
    
    // MARK: - Load Pending Notifications
    
    @MainActor
    private func loadPendingNotifications() async {
        print("🔵 NotificationView: loadPendingNotifications START")
        
        isLoading = true
        
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        
        print("🔵 NotificationView: pending requests = \(requests.count)")
        
        let mapped = requests.compactMap {
            request -> PendingNotificationInfo? in
            
            let triggerDate: Date?
            
            if let calendarTrigger =
                request.trigger as? UNCalendarNotificationTrigger {
                
                triggerDate =
                    calendarTrigger.nextTriggerDate()
                
            } else if let timeTrigger =
                        request.trigger as? UNTimeIntervalNotificationTrigger {
                
                triggerDate =
                    Date().addingTimeInterval(
                        timeTrigger.timeInterval
                    )
                
            } else {
                triggerDate = nil
            }
            
            let taskID: UUID?
            
            if request.identifier
                .lowercased()
                .hasPrefix("document.") {
                
                taskID = nil
                
            } else {
                let identifierParts =
                    request.identifier.split(separator: ".")
                
                if let uuidCandidate =
                    identifierParts.first(where: {
                        UUID(uuidString: String($0)) != nil
                    }) {
                    taskID =
                        UUID(
                            uuidString: String(uuidCandidate)
                        )
                } else {
                    taskID = nil
                }
            }
            
            let matchingDocument = documents.first {
                request.identifier ==
                "document.\($0.id.uuidString)"
            }
            
            if request.identifier
                .lowercased()
                .contains("document"),
               matchingDocument == nil {
                return nil
            }
            
            return PendingNotificationInfo(
                id: request.identifier,
                title: request.content.title,
                body: request.content.body,
                triggerDate: triggerDate,
                identifier: request.identifier,
                categoryIdentifier:
                    request.content.categoryIdentifier,
                taskID: taskID,
                deadlineDate:
                    matchingDocument?.expiryDate
            )
        }
        .sorted {
            ($0.triggerDate ?? .distantFuture) <
            ($1.triggerDate ?? .distantFuture)
        }
        
        pending = mapped
        isLoading = false
        print("🔵 NotificationView: loadPendingNotifications END — pending = \(pending.count)")
    }
}

// MARK: - Notification Row

private struct NotificationRow: View {
    
    let item: PendingNotificationInfo
    let documents: [DocumentItem]
    
    private var destination: some View {
        Group {
            if let taskID = item.taskID {
                NotificationTaskDestination(
                    taskID: taskID
                )
            } else if
                item.identifier
                    .lowercased()
                    .contains("document"),
                let document = documents.first(where: {
                    item.identifier ==
                    "document.\($0.id.uuidString)"
                }) {
                
                DocumentDetailView(
                    document: document
                )
                
            } else {
                ContentUnavailableView(
                    String(localized: "Notification Not Found"),
                    systemImage: "bell"
                )
            }
        }
    }
    
    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                
                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    
                    HStack(alignment: .center) {
                        Text(item.body)
                            .font(
                                .headline
                                    .weight(.semibold)
                            )
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        
                        Spacer(minLength: 12)
                        
                        Text(item.notificationEmoji)
                            .font(.title3)
                    }
                    
                    HStack(spacing: 4) {
                        Text(
                            item.identifier
                                .lowercased()
                                .contains("document")
                            ? String(
                                localized: "Document Expiry:"
                            )
                            : String(
                                localized: "Deadline:"
                            )
                        )
                        .foregroundStyle(.secondary)
                        
                        Text(
                            deadlineDateText(
                                for: item.deadlineDate
                            )
                        )
                        .foregroundStyle(.primary)
                        
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline)
                    
                    HStack(spacing: 4) {
                        Text(
                            String(
                                localized: "Next notification:"
                            )
                        )
                        .foregroundStyle(.secondary)
                        
                        Text(item.notificationType)
                            .foregroundStyle(.blue)
                        
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                    
                    Text(
                        notificationDateTextWithToday(
                            for: item.triggerDate
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                }
            }
        }
        .padding(.vertical, 8)
        .listRowSeparatorTint(
            .blue.opacity(0.25)
        )
        .buttonStyle(.plain)
    }
    
    private func deadlineDateText(
        for date: Date?
    ) -> String {
        guard let date else {
            return String(localized: "Unknown date")
        }
        
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            let time = date.formatted(
                date: .omitted,
                time: .shortened
            )
            
            return String(
                localized: "Today • \(time)"
            )
        }
        
        return date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .year()
                .hour()
                .minute()
        )
    }
    
    private func notificationDateTextWithToday(
        for date: Date?
    ) -> String {
        guard let date else {
            return String(localized: "Unknown date")
        }
        
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            let time = date.formatted(
                date: .omitted,
                time: .shortened
            )
            
            return String(
                localized: "Today • \(time)"
            )
        }
        
        return date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .year()
                .hour()
                .minute()
        )
    }
}

// MARK: - Task Destination

private struct NotificationTaskDestination: View {
    
    let taskID: UUID
    
    @Query private var tasks: [TodoTask]
    
    init(taskID: UUID) {
        self.taskID = taskID
        
        _tasks = Query(
            filter: #Predicate<TodoTask> { task in
                task.id == taskID
            }
        )
    }
    
    var body: some View {
        if let task = tasks.first {
            TaskDetailView(task: task)
        } else {
            ContentUnavailableView(
                String(localized: "Task Not Found"),
                systemImage: "checklist"
            )
        }
    }
}
