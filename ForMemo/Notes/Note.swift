import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    var content: Data = Data()
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var isPinned: Bool = false
    var isArchived: Bool = false
    var archivedAt: Date? = nil
    var lastOpenedAt: Date?

    init(
        id: UUID = UUID(),
        title: String = "",
        content: Data = Data(),
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        isPinned: Bool = false,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.lastOpenedAt = lastOpenedAt
    }
}
