import Foundation
import SwiftData
import os

enum WalletAssetKind: String, Codable {

    case logo
    case front
    case back
}

@Model
final class WalletAsset {

    var id: UUID = UUID()

    var kind: WalletAssetKind = WalletAssetKind.logo

    var relativePath: String = ""

    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    var card: LoyaltyCard?

    
    init(
        kind: WalletAssetKind,
        relativePath: String
    ) {
        self.kind = kind
        self.relativePath = relativePath
    }
    
    @discardableResult
    static func create(
        kind: WalletAssetKind,
        imageData: Data,
        for card: LoyaltyCard,
        in context: ModelContext
    ) -> WalletAsset? {

        guard let relativePath = LoyaltyCardLogoStore.save(
            imageData: imageData
        ) else {
            return nil
        }

        let asset = WalletAsset(
            kind: kind,
            relativePath: relativePath
        )

        // 1. Inserisci subito il nuovo modello nel context
        context.insert(asset)

        // 2. Collega la relazione inversa
        asset.card = card

        // 3. Aggiorna i campi legacy
        switch kind {

        case .logo:
            card.loyaltyLogoRelativePath = relativePath

        case .front:
            card.loyaltyFrontRelativePath = relativePath

        case .back:
            card.loyaltyBackRelativePath = relativePath
        }

//        // 4. Aggiorna la relazione sul padre
//        if card.assets == nil {
//            card.assets = []
//        }
//
//        card.assets?.append(asset)

        return asset
    }
    
    @MainActor
    @discardableResult
    static func createLegacyLogoReference(
        for card: LoyaltyCard,
        in context: ModelContext
    ) -> WalletAsset? {

        guard card.logoAsset == nil else {
            return card.logoAsset
        }

        guard card.assets?.contains(where: { $0.kind == .logo }) != true else {
            return card.logoAsset
        }

        let legacyRelativePath = "\(card.id.uuidString).jpg"

        guard let imageData = LoyaltyCardLogoStore.loadLegacy(
            relativePath: legacyRelativePath
        ) else {
            return nil
        }

        guard let newRelativePath = LoyaltyCardLogoStore.save(
            imageData: imageData
        ) else {
            return nil
        }

        let asset = WalletAsset(
            kind: .logo,
            relativePath: newRelativePath
        )

        context.insert(asset)

        asset.card = card

        if card.assets == nil {
            card.assets = []
        }

        card.assets?.append(asset)

        context.safeSave(
            operation: "CreateLegacyWalletLogoReference"
        )

        return asset
    }
}
