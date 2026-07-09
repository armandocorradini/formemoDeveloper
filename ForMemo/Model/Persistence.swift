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

    private static let schema = Schema([
        TodoTask.self,
        TaskAttachment.self,
        DeletedItem.self,
        LoyaltyCard.self,
        TripList.self,
        DocumentItem.self,
        VaultItem.self
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
                url: legacyStoreURL,
                cloudKitDatabase:
                    cloudKitEnabled
                    ? .private(cloudKitContainerID)
                    : .none
            )


            let container = try ModelContainer(

                for: schema,

                configurations: [configuration]

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
