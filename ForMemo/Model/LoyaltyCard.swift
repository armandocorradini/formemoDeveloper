import Foundation
import SwiftData

@Model
final class LoyaltyCard {

    var id: UUID = UUID()

    var storeName: String = ""
    var cardHolder: String?

    var barcodeValue: String = ""
    var barcodeFormat: String = "code128"

    var notes: String?

    // Optional custom card color stored as HEX string
    var colorHex: String?
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        storeName: String,
        cardHolder: String? = nil,
        barcodeValue: String,
        barcodeFormat: String,
        notes: String? = nil,
        colorHex: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {

        self.id = id
        self.storeName = storeName
        self.cardHolder = cardHolder
        self.barcodeValue = barcodeValue
        self.barcodeFormat = barcodeFormat
        self.notes = notes
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

extension LoyaltyCard {

    @MainActor
    static func createDeletedCardRecord(
        from card: LoyaltyCard,
        in context: ModelContext
    ) {

        let item = DeletedItem(type: "loyaltycard")

        item.loyaltyCardID = card.id

        item.storeName = card.storeName
        item.cardHolder = card.cardHolder

        item.barcodeValue = card.barcodeValue
        item.barcodeFormat = card.barcodeFormat

        item.loyaltyNotes = card.notes
        item.loyaltyColorHex = card.colorHex

        item.loyaltySortOrder = card.sortOrder

        context.insert(item)
    }
}
