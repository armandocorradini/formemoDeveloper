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

        if lower.contains("global") {
            return "⏱️"
        }

        return "🔔"
    }
}

struct NotificationView: View {

    @State private var pending: [PendingNotificationInfo] = []
    @State private var isLoading = true
    @Query private var tasks: [TodoTask]

    private let gradient = LinearGradient(
        colors: [backColor1, backColor2],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {

        ZStack {

            gradient
                .ignoresSafeArea()

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

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
                            String(localized: "There are currently no pending notifications.")
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

                                    Text(String(localized:"Upcoming Notifications"))
                                        .font(.subheadline.bold())

                                    Text(String(localized:"These are the next notifications currently scheduled on your device. The time shown below each task indicates when the notification will appear. Any additional notifications will be scheduled automatically afterwards."))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.top, -2)
                                .padding(.bottom, 2)

                            }
                            .listRowBackground(Color.clear)

                            Section {

                                ForEach(pending) { item in

                                    VStack(alignment: .leading, spacing: 8) {

                                        VStack(alignment: .leading, spacing: 6) {

                                            HStack(alignment: .top) {

                                                Text(item.body)
                                                    .font(.headline.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(2)

                                                Spacer(minLength: 12)

                                                Text(item.notificationEmoji)
                                                    .font(.title3)
                                            }

                                            HStack(spacing: 4) {

                                                Text(String(localized:"Deadline:"))
                                                    .foregroundStyle(.secondary)

                                                Text(deadlineDateText(for: item.deadlineDate))
                                                    .foregroundStyle(.primary)

                                                Spacer(minLength: 0)
                                            }
                                            .font(.subheadline)


                                            HStack(spacing: 4) {

                                                Text(String(localized:"Next notification:"))
                                                    .foregroundStyle(.secondary)


                                                Text(item.notificationType)
                                                    .foregroundStyle(.blue)

                                                Spacer(minLength: 0)
                                            }
                                            .font(.subheadline)



                                            Text(notificationDateTextWithToday(for: item.triggerDate))
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .listRowSeparatorTint(.blue.opacity(0.25))
                                }

                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "Notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshAndReload()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )
        ) { _ in

            Task {
                await refreshAndReload()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .taskDidChange)
        ) { _ in

            Task {
                await refreshAndReload()
            }
        }
    }

    private func triggerText(for date: Date?) -> String {

        guard let date else {
            return String(localized: "Unknown date")
        }

        let absolute = date.formatted(
            date: .abbreviated,
            time: .shortened
        )

        let totalMinutes = max(Int(date.timeIntervalSinceNow / 60), 0)

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

    private func notificationDateText(for date: Date?) -> String {

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
                .hour()
                .minute()
        )
    }

    private func deadlineDateText(for date: Date?) -> String {

        guard let date else {
            return String(localized: "Unknown date")
        }

        let calendar = Calendar.current

        if calendar.isDateInToday(date) {

            let time = date.formatted(
                date: .omitted,
                time: .shortened
            )

            return String(localized:"Today • \(time)")
        }

        return date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .hour()
                .minute()
        )
    }

    private func notificationDateTextWithToday(for date: Date?) -> String {

        guard let date else {
            return String(localized: "Unknown date")
        }

        let calendar = Calendar.current

        if calendar.isDateInToday(date) {

            let time = date.formatted(
                date: .omitted,
                time: .shortened
            )

            return String(localized:"Today • \(time)")
        }

        return date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .hour()
                .minute()
        )
    }

    @MainActor
    private func refreshAndReload() async {

        NotificationManager.shared.refresh(force: true)

        // Allow UNUserNotificationCenter to commit
        // the rebuilt pending requests.
        try? await Task.sleep(for: .milliseconds(900))

        await loadPendingNotifications()
    }

    @MainActor
    private func loadPendingNotifications() async {

        isLoading = true

        let center = UNUserNotificationCenter.current()

        let requests = await center.pendingNotificationRequests()

        let mapped = requests.map { request -> PendingNotificationInfo in

            let triggerDate: Date?

            if let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger {
                triggerDate = calendarTrigger.nextTriggerDate()
            } else if let timeTrigger = request.trigger as? UNTimeIntervalNotificationTrigger {
                triggerDate = Date().addingTimeInterval(timeTrigger.timeInterval)
            } else {
                triggerDate = nil
            }

            let taskID: UUID?

            let identifierParts = request.identifier
                .split(separator: ".")

            if let uuidCandidate = identifierParts.first(where: {
                UUID(uuidString: String($0)) != nil
            }) {

                taskID = UUID(uuidString: String(uuidCandidate))

            } else {
                taskID = nil
            }

            let matchingTask = tasks.first {
                $0.id == taskID
            }

            return PendingNotificationInfo(
                id: request.identifier,
                title: request.content.title,
                body: request.content.body,
                triggerDate: triggerDate,
                identifier: request.identifier,
                categoryIdentifier: request.content.categoryIdentifier,
                taskID: taskID,
                deadlineDate: matchingTask?.deadLine
            )
        }
        .sorted {
            ($0.triggerDate ?? .distantFuture) <
            ($1.triggerDate ?? .distantFuture)
        }

        pending = mapped

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        NotificationView()
    }
}
