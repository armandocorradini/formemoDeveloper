import Foundation
import SwiftData
import os

enum WalletAssetKind: String, Codable {

    case logo
    case front
    case back
}

enum WalletAssetCreationError: LocalizedError {
    case emptyImageData
    case fileWriteFailed
    case missingAfterSave

    var errorDescription: String? {
        switch self {
        case .emptyImageData: return "The selected image contains no data."
        case .fileWriteFailed: return "The wallet image could not be written locally."
        case .missingAfterSave: return "The wallet asset was not persisted locally."
        }
    }
}

@Model
final class WalletAsset {

    var id: UUID = UUID()

    // Keep the CloudKit-backed attribute scalar. A Codable enum is stored as a
    // transformable value and causes the mirroring export for this entity to fail.
    var kindRaw: String = WalletAssetKind.logo.rawValue

    var relativePath: String = ""

    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    var card: LoyaltyCard?

    var kind: WalletAssetKind {
        get { WalletAssetKind(rawValue: kindRaw) ?? .logo }
        set { kindRaw = newValue.rawValue }
    }

    
    init(
        kind: WalletAssetKind,
        relativePath: String
    ) {
        self.kindRaw = kind.rawValue
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

        context.insert(asset)
        asset.card = card

        if card.assets == nil {
            card.assets = []
        }
        if card.assets?.contains(where: { $0.id == asset.id }) == false {
            card.assets?.append(asset)
        }

        // 3. Aggiorna i campi legacy
        switch kind {

        case .logo:
            card.loyaltyLogoRelativePath = relativePath

        case .front:
            card.loyaltyFrontRelativePath = relativePath

        case .back:
            card.loyaltyBackRelativePath = relativePath
        }

        return asset
    }

    /// Creates a local SwiftData record or throws. New-card creation must never
    /// silently continue with a logo that has no WalletAsset record.
    static func createRequired(
        kind: WalletAssetKind,
        imageData: Data,
        for card: LoyaltyCard,
        in context: ModelContext
    ) throws -> WalletAsset {
        guard !imageData.isEmpty else {
            throw WalletAssetCreationError.emptyImageData
        }
        guard let asset = create(kind: kind, imageData: imageData, for: card, in: context) else {
            throw WalletAssetCreationError.fileWriteFailed
        }
        return asset
    }

    static func verifyPersisted(
        _ assets: [WalletAsset],
        in context: ModelContext
    ) throws {
        let stored = try context.fetch(FetchDescriptor<WalletAsset>())
        let storedByID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
        guard assets.allSatisfy({ asset in
            guard let storedAsset = storedByID[asset.id] else { return false }
            return storedAsset.card?.id == asset.card?.id
        }) else {
            throw WalletAssetCreationError.missingAfterSave
        }
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

    /// Repairs the scalar kind introduced after the original transformable enum.
    /// The parent already stores the three paths, so this is deterministic and
    /// does not require a second CloudKit migration.
    @MainActor
    static func normalizePersistedKinds(in context: ModelContext) {
        guard let assets = try? context.fetch(FetchDescriptor<WalletAsset>()) else {
            return
        }

        for asset in assets {
            guard let card = asset.card else { continue }
            let expectedKind: WalletAssetKind?
            if asset.relativePath == card.loyaltyFrontRelativePath {
                expectedKind = .front
            } else if asset.relativePath == card.loyaltyBackRelativePath {
                expectedKind = .back
            } else if asset.relativePath == card.loyaltyLogoRelativePath {
                expectedKind = .logo
            } else {
                expectedKind = nil
            }

            if let expectedKind, asset.kind != expectedKind {
                asset.kind = expectedKind
            }
        }

        if context.hasChanges {
            context.safeSave(operation: "NormalizeWalletAssetKinds")
        }
    }
}
