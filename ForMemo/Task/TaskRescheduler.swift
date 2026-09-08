import SwiftUI
import SwiftData
import os

// MARK: - Task Reschedule

enum TaskRescheduleOption: Identifiable {
    case plusOneHour, plusThreeHours, plusOneDay, plusTwoDays, plusThreeDays
    case minusOneHour, minusThreeHours, minusOneDay, minusTwoDays, minusThreeDays

    static let positive: [Self] = [.plusOneHour, .plusThreeHours, .plusOneDay, .plusTwoDays, .plusThreeDays]
    static let negative: [Self] = [.minusOneHour, .minusThreeHours, .minusOneDay, .minusTwoDays, .minusThreeDays]

    var id: Self { self }

    var value: Int {
        switch self {
        case .plusOneHour, .minusOneHour: return 1
        case .plusThreeHours, .minusThreeHours: return 3
        case .plusOneDay, .minusOneDay: return 1
        case .plusTwoDays, .minusTwoDays: return 2
        case .plusThreeDays, .minusThreeDays: return 3
        }
    }

    var component: Calendar.Component {
        switch self {
        case .plusOneHour, .plusThreeHours, .minusOneHour, .minusThreeHours: return .hour
        default: return .day
        }
    }

    var signedValue: Int {
        switch self {
        case .minusOneHour, .minusThreeHours, .minusOneDay, .minusTwoDays, .minusThreeDays:
            return -value
        default:
            return value
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .plusOneHour: return "+1 hour"
        case .plusThreeHours: return "+3 hours"
        case .plusOneDay: return "+1 day"
        case .plusTwoDays: return "+2 days"
        case .plusThreeDays: return "+3 days"
        case .minusOneHour: return "-1 hour"
        case .minusThreeHours: return "-3 hours"
        case .minusOneDay: return "-1 day"
        case .minusTwoDays: return "-2 days"
        case .minusThreeDays: return "-3 days"
        }
    }

    var systemImage: String {
        switch self {
        case .plusOneHour, .minusOneHour: return "clock.badge"
        case .plusThreeHours, .minusThreeHours: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .plusOneDay, .minusOneDay: return "sun.max"
        case .plusTwoDays, .minusTwoDays: return "calendar"
        case .plusThreeDays, .minusThreeDays: return "calendar.badge.clock"
        }
    }
}

@MainActor
enum TaskRescheduler {
    static func reschedule(_ task: TodoTask, option: TaskRescheduleOption, in modelContext: ModelContext) {
        let baseDate = task.deadLine ?? Date()
        guard let newDate = Calendar.current.date(
            byAdding: option.component,
            value: option.signedValue,
            to: baseDate
        ) else { return }

        task.deadLine = newDate

        do {
            try modelContext.save()
            modelContext.processPendingChanges()
            NotificationCenter.default.post(name: .taskDidChange, object: nil)
            NotificationCenter.default.post(name: .attachmentsShouldRefresh, object: nil)
            NotificationManager.shared.refresh(force: true)
        } catch {
            AppLogger.persistence.fault("Failed to reschedule task: \(error)")
        }
    }
}

struct TaskRescheduleMenu: View {
    let task: TodoTask
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Menu {
            ForEach(TaskRescheduleOption.positive) { option in
                button(for: option)
            }
            Divider()
            ForEach(TaskRescheduleOption.negative) { option in
                button(for: option)
            }
        } label: {
            Label("Reschedule", systemImage: "clock")
        }
    }

    @ViewBuilder
    private func button(for option: TaskRescheduleOption) -> some View {
        Button {
            TaskRescheduler.reschedule(task, option: option, in: modelContext)
        } label: {
            Label(option.title, systemImage: option.systemImage)
        }
    }
}
