import SwiftUI
import SwiftData

// MARK: - Main Persistent Model

@Model
final class TripList {
    
    var id: UUID = UUID()
    
    var name: String = ""
    var icon: String = "suitcase.rolling"
    
    var colorHex: String = ""
    var notes: String = ""
    
    var systemTemplate: String = ""
    
    var sortOrder: Int = 0
    
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastOpenedAt: Date?
    
    // Raw persisted JSON payload.
    @Attribute(.externalStorage)
    private var sectionsData: Data?
    
    // Computed embedded sections.
    var sections: [TripSectionData] {
        get {
            guard
                let sectionsData,
                let decoded = try? JSONDecoder().decode(
                    [TripSectionData].self,
                    from: sectionsData
                )
            else {
                return []
            }
            
            return decoded
        }
        set {
            sectionsData = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }
    
    init(
        name: String,
        icon: String,
        colorHex: String = "",
        notes: String = "",
        systemTemplate: String = "",
        sortOrder: Int = 0,
        sections: [TripSectionData] = []
    ) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.notes = notes
        self.systemTemplate = systemTemplate
        self.sortOrder = sortOrder
        self.sectionsData = try? JSONEncoder().encode(sections)
    }
}

extension TripList {

    @MainActor
    static func createDeletedTripRecord(
        from trip: TripList,
        in context: ModelContext
    ) {

        let item = DeletedItem(type: "trip")

        item.tripID = trip.id

        item.tripName = trip.name
        item.tripIcon = trip.icon

        item.tripColorHex = trip.colorHex
        item.tripNotes = trip.notes

        item.tripSystemTemplate = trip.systemTemplate
        item.tripSortOrder = trip.sortOrder

        item.tripSectionsData = try? JSONEncoder().encode(
            trip.sections
        )

        context.insert(item)
    }
}

// MARK: - Embedded Section

struct TripSectionData: Codable, Identifiable, Hashable {
    
    var id: UUID = UUID()
    
    var title: String = ""
    
    var isCollapsed: Bool = false
    
    var icon: String = ""
    
    var notes: String = ""
    
    var sortOrder: Int = 0
    
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    var items: [TripItemData] = []
    
    init(
        title: String,
        isCollapsed: Bool = false,
        icon: String = "",
        notes: String = "",
        sortOrder: Int = 0,
        items: [TripItemData] = []
    ) {
        self.title = title
        self.isCollapsed = isCollapsed
        self.icon = icon
        self.notes = notes
        self.sortOrder = sortOrder
        self.items = items
    }
}

// MARK: - Embedded Item

struct TripItemData: Codable, Identifiable, Hashable {
    
    var id: UUID = UUID()
    
    var title: String = ""
    
    var isChecked: Bool = false
    
    var notes: String = ""
    
    var quantity: Int = 1
    
    var isImportant: Bool = false
    
    var url: String = ""
    
    var dueDate: Date?
    
    var locationName: String = ""
    
    var sortOrder: Int = 0
    
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    var isTemplateLocked: Bool = false
    
    init(
        title: String,
        isChecked: Bool = false,
        notes: String = "",
        quantity: Int = 1,
        isImportant: Bool = false,
        url: String = "",
        dueDate: Date? = nil,
        locationName: String = "",
        sortOrder: Int = 0,
        isTemplateLocked: Bool = false
    ) {
        self.title = title
        self.isChecked = isChecked
        self.notes = notes
        self.quantity = quantity
        self.isImportant = isImportant
        self.url = url
        self.dueDate = dueDate
        self.locationName = locationName
        self.sortOrder = sortOrder
        self.isTemplateLocked = isTemplateLocked
    }
}
