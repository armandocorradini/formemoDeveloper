import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID
    var title: String
    var content: Data
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        title: String = "",
        content: Data = Data(),
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        isPinned: Bool = false,
        isArchived: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isPinned = isPinned
        self.isArchived = isArchived
    }
}
