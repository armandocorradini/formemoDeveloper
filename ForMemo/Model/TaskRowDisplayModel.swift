import SwiftUI
import SwiftData

struct TaskRowDisplayModel: Identifiable, Equatable {

    let id: AnyHashable

    let title: String
    let subtitle: String?
    let mainIcon: String
    let statusColor: Color

    let hasValidAttachments: Bool
    let hasLocation: Bool

    let badgeText: String?
    let prioritySystemImage: String?

    let deadLine: Date?
    let reminderOffsetMinutes: Int?

    let shouldShowBadge: Bool
    let isCompleted: Bool

    let recurrenceRule: String?
    let mainTag: TaskMainTag?
}
extension TaskRowDisplayModel {

    static func == (
        lhs: TaskRowDisplayModel,
        rhs: TaskRowDisplayModel
    ) -> Bool {

        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
        lhs.mainIcon == rhs.mainIcon &&
        lhs.hasValidAttachments == rhs.hasValidAttachments &&
        lhs.hasLocation == rhs.hasLocation &&
        lhs.badgeText == rhs.badgeText &&
        lhs.prioritySystemImage == rhs.prioritySystemImage &&
        lhs.deadLine == rhs.deadLine &&
        lhs.reminderOffsetMinutes == rhs.reminderOffsetMinutes &&
        lhs.shouldShowBadge == rhs.shouldShowBadge &&
        lhs.isCompleted == rhs.isCompleted &&
        lhs.recurrenceRule == rhs.recurrenceRule &&
        lhs.mainTag == rhs.mainTag
    }
}
