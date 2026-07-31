import SwiftData
import SwiftUI
import Foundation
import os

enum Persistence {
    private static let cloudKitContainerID =
        "iCloud.corradini.armando.NewTask"

    // 🔥 Use the SAME local database path as legacy versions.
    // Local DB is the permanent source of truth.
    private static let legacyStoreURL =
        URL.documentsDirectory.appendingPathComponent("local.store")

    private static func storeURL() -> URL {
        selectedStoreURL()
    }

    private static let appGroupIdentifier = "group.corradini.armando.NewTask"

    private static func appGroupStoreURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("local.store")
    }

    private static func appGroupStoreExists() -> Bool {
        guard let url = appGroupStoreURL() else {
            return false
        }

        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func canUseAppGroupStore() -> Bool {

        guard appGroupStoreExists() else {
            AppLogger.persistence.debug("App Group store is not eligible")
            return false
        }

        guard let marker = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(".migration-completed"),
              FileManager.default.fileExists(atPath: marker.path)
        else {
            AppLogger.persistence.debug("Migration marker missing")
            return false
        }

        AppLogger.persistence.debug("App Group store is eligible")

        return true
    }

    private static func selectedStoreURL() -> URL {

        let selectedURL: URL

        if canUseAppGroupStore(),
           let appGroupURL = appGroupStoreURL() {

            selectedURL = appGroupURL

        } else {

            selectedURL = legacyStoreURL
        }

        AppLogger.persistence.debug("Selected SwiftData store: \(selectedURL.path)")

        return selectedURL
    }
    
    static var diagnosticsCurrentStoreURL: String {
        selectedStoreURL().path
    }

    static var diagnosticsUsingAppGroupStore: Bool {
        guard let appGroupURL = appGroupStoreURL() else {
            return false
        }

        return selectedStoreURL() == appGroupURL
    }
    
    static let schema = Schema([
        TodoTask.self,
        TaskAttachment.self,
        DeletedItem.self,
        LoyaltyCard.self,
        WalletAsset.self,
        TripList.self,
        DocumentItem.self,
        DocumentAsset.self,
        VaultItem.self,
        VaultSecret.self
    ])

    static func makeModelContainer(
        cloudKitEnabled: Bool
    ) -> ModelContainer {

        DebugLog.write(
            cloudKitEnabled
            ? "Persistence initialization started (CloudKit)"
            : "Persistence initialization started (Local)"
        )

        do {
            CrashDetector.setLastEvent(
                cloudKitEnabled
                ? "SwiftData container initialization (CloudKit)"
                : "SwiftData container initialization (Local)"
            )

            // 🔥 SINGLE PERSISTENT STORE
            // Local database is ALWAYS the source of truth.
            // CloudKit only adds sync capabilities on top.

            let configuration = ModelConfiguration(
                schema: schema,
                url: storeURL(),
                cloudKitDatabase:
                    cloudKitEnabled
                    ? .private(cloudKitContainerID)
                    : .none
            )


            let container = try ModelContainer(

                for: schema,

                configurations: [configuration]

            )
            
            let context = ModelContext(container)
            
            let taskCount = (try? context.fetchCount(
                FetchDescriptor<TodoTask>()
            )) ?? -1

            let vaultCount = (try? context.fetchCount(
                FetchDescriptor<VaultItem>()
            )) ?? -1

            AppLogger.persistence.notice(
                "ModelContainer initial TodoTask count: \(taskCount)"
            )

            AppLogger.persistence.notice(
                "ModelContainer initial VaultItem count: \(vaultCount)"
            )
            
            
            CrashDetector.setLastEvent(
                cloudKitEnabled
                ? "SwiftData container initialized (CloudKit)"
                : "SwiftData container initialized (Local)"
            )


            DebugLog.write(
                cloudKitEnabled
                ? "Persistence initialization completed (CloudKit)"
                : "Persistence initialization completed (Local)"
            )

            return container

        } catch {
            CrashDetector.setLastEvent(
                "SwiftData container initialization failed"
            )

            DebugLog.write(
                "Persistence initialization failed"
            )

            AppLogger.persistence.fault(
                "SwiftData ModelContainer error: \(error.localizedDescription)"
            )

            fatalError("SwiftData container initialization failed: \(error)")
        }
    }
}
