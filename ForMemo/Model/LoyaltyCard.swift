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

    // Optional filesystem path for the logo image.
    // Keeping only lightweight metadata inside SwiftData
    // dramatically improves CloudKit reliability.
    var logoRelativePath: String?

    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        storeName: String,
        cardHolder: String? = nil,
        barcodeValue: String,
        barcodeFormat: String,
        notes: String? = nil,
        colorHex: String? = nil,
        logoRelativePath: String? = nil,
        createdAt: Date = Date()
    ) {

        self.id = id
        self.storeName = storeName
        self.cardHolder = cardHolder
        self.barcodeValue = barcodeValue
        self.barcodeFormat = barcodeFormat
        self.notes = notes
        self.colorHex = colorHex
        self.logoRelativePath = logoRelativePath
        self.createdAt = createdAt
    }

    var hasLogo: Bool {

        logoRelativePath != nil
    }
}
