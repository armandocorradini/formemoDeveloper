import Foundation

struct CSVTask: Identifiable, Hashable {
    
    let id = UUID()
    
    let title: String
    let description: String
    
    let deadline: Date?
    let reminder: Int?
    
    let tag: String?
    
    let latitude: Double?
    let longitude: Double?
    let location: String?
    
    let recurrenceRule: String?
    let recurrenceInterval: Int?

    let locationReminderEnabled: Bool?

    let isCompleted: Bool?

    let createdAt: Date?
    let completedAt: Date?
    let snoozeUntil: Date?
    
    let priority: Int
}
