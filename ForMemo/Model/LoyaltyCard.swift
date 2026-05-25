

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

    var createdAt: Date = Date()

    init(
        storeName: String,
        cardHolder: String? = nil,
        barcodeValue: String,
        barcodeFormat: String,
        notes: String? = nil
    ) {


        self.storeName = storeName
        self.cardHolder = cardHolder

        self.barcodeValue = barcodeValue
        self.barcodeFormat = barcodeFormat

        self.notes = notes

    }
}
