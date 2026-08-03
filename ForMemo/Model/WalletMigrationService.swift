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
        
        // nessun logo legacy
        guard let legacyPath = card.loyaltyLogoRelativePath,
              !legacyPath.isEmpty else {
            return
        }
        
        // file legacy assente
        guard let imageData = LoyaltyCardLogoStore.loadLegacy(
            relativePath: legacyPath
        ) else {
            return
        }
        
        _ = try WalletAsset.createRequired(
            kind: .logo,
            imageData: imageData,
            for: card,
            in: context
        )
        
        try context.save()
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

        UserDefaults.standard.set(
            true,
            forKey: migrationKey
        )
    }
    
    private static let migrationKey = "WalletLegacyMigrationCompleted"
    
}
