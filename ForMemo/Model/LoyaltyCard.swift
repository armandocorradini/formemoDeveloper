import Foundation
import SwiftData

@Model
final class LoyaltyCard {

    var id: UUID = UUID()

    var storeName: String = ""
    var cardHolder: String?

    var barcodeValue: String = ""
    var barcodeFormat: String = "code128"
    var itemType: String = "loyaltyCard"

    var notes: String?

    // Optional custom card color stored as HEX string
    var colorHex: String?
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var lastOpenedAt: Date?
    
    
    // WALLET ASSETS

    var loyaltyLogoRelativePath: String?
    
    
    @Relationship(
        deleteRule: .cascade,
        inverse: \WalletAsset.card
    )
    var assets: [WalletAsset]?
    
    

    init(
        id: UUID = UUID(),
        storeName: String,
        cardHolder: String? = nil,
        barcodeValue: String,
        barcodeFormat: String,
        itemType: String = "loyaltyCard",
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
        self.itemType = itemType
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
        
        item.loyaltyItemType = card.itemType
        
        item.loyaltyNotes = card.notes
        item.loyaltyColorHex = card.colorHex

        item.loyaltySortOrder = card.sortOrder
        
        
        print("=== DELETE CARD ===")
        print("Assets:", card.assets?.count ?? 0)
        print("Logo:", card.logoAsset?.relativePath ?? "nil")
        print("Front:", card.frontAsset?.relativePath ?? "nil")
        print("Back:", card.backAsset?.relativePath ?? "nil")
        
        item.loyaltyLogoRelativePath =
            card.logoAsset?.relativePath
            ?? card.loyaltyLogoRelativePath

        context.insert(item)
    }
}
extension LoyaltyCard {

    func asset(for kind: WalletAssetKind) -> WalletAsset? {
        assets?.first { $0.kind == kind
        }
    }

    var logoAsset: WalletAsset? {
        asset(for: .logo)
    }

    var frontAsset: WalletAsset? {
        asset(for: .front)
    }

    var backAsset: WalletAsset? {
        asset(for: .back)
    }
    
    var galleryAssets: [WalletAsset] {
        (assets ?? []).filter { $0.kind != .logo }
    }
    
    
    

}
