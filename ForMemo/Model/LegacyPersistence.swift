

import Foundation
import SwiftData
import os

enum LegacyPersistence {
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ForMemo",
        category: "legacyPersistence"
    )
    private static let legacyLock = NSLock()
    
    static var legacyStoreURL: URL {
        URL.documentsDirectory
            .appendingPathComponent("local.store")
    }
    
    static var legacyStoreExists: Bool {
        let exists = FileManager.default.fileExists(
            atPath: legacyStoreURL.path
        )

        if exists {
            logger.info("Legacy local.store detected")
        } else {
            logger.info("Legacy local.store missing")
        }

        return exists
    }
    
    @MainActor
    static func openLegacyContainer() throws -> ModelContainer {
        
        logger.info("Opening legacy local.store")

        // 🔥 Prevent concurrent access during bootstrap.
        legacyLock.lock()

        defer {
            legacyLock.unlock()
        }

        let schema = Schema([
            TodoTask.self,
            TaskAttachment.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            url: legacyStoreURL
        )

        logger.info("Legacy container configuration prepared")

        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )

        logger.info("Legacy container opened successfully")

        return container
    }
}
