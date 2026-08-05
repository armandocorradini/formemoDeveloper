import Foundation
import SwiftData




@MainActor
enum WalletMigrationService {
    
    
    @MainActor
    static func migrateLegacyLogo(
        for card: LoyaltyCard,
        in context: ModelContext
    ) throws {
        
        // già migrata
        if card.logoAsset != nil {
            return
        }
        
        var imageData: Data?

        // 1️⃣ Nuovo formato (se presente)
        if let legacyPath = card.loyaltyLogoRelativePath,
           !legacyPath.isEmpty {

            imageData = LegacyLoyaltyCardLogoStore.loadLegacy(
                relativePath: legacyPath
            )
        }

        // 2️⃣ Compatibilità con tutte le versioni precedenti
        if imageData == nil {

            imageData = LegacyLoyaltyCardLogoStore.loadLegacy(
                relativePath: "\(card.id.uuidString).jpg"
            )
        }

        guard let imageData else {
            return
        }
        
        _ = try WalletAsset.createRequired(
            kind: .logo,
            imageData: imageData,
            for: card,
            in: context
        )
        

    }
    
    
    
    static func runIfNeeded(
        context: ModelContext
    ) {

        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        let descriptor = FetchDescriptor<LoyaltyCard>()

        guard let cards = try? context.fetch(descriptor) else {
            return
        }

        for card in cards {
            try? migrateLegacyLogo(
                for: card,
                in: context
            )
        }

        try? context.save()

        UserDefaults.standard.set(
            true,
            forKey: migrationKey
        )
    }
    
    private static let migrationKey = "WalletLegacyMigrationCompleted"
    
}
