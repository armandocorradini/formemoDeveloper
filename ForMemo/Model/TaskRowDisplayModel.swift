import SwiftUI
import SwiftData


struct TaskRowDisplayModel: Identifiable, Sendable {
    
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
}
