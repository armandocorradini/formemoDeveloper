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
            ? "☁️ CLOUDKIT: Preparing SwiftData container"
            : "🟠 BOOTSTRAP: Preparing LOCAL-FIRST SwiftData container"
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

            let start = CFAbsoluteTimeGetCurrent()

            let container = try ModelContainer(

                for: schema,

                configurations: [configuration]

            )
            CrashDetector.setLastEvent(
                cloudKitEnabled
                ? "SwiftData container initialized (CloudKit)"
                : "SwiftData container initialized (Local)"
            )

            let elapsed = CFAbsoluteTimeGetCurrent() - start

            DebugLog.write(

                String(

                    format: "⏱️ ModelContainer creation: %.3fs",

                    elapsed

                )

            )

            DebugLog.write(
                cloudKitEnabled
                ? "☁️ CLOUDKIT: SwiftData container initialized"
                : "🟠 BOOTSTRAP: LOCAL-FIRST container initialized"
            )

            return container

        } catch {
            CrashDetector.setLastEvent(
                "SwiftData container initialization failed"
            )
            print("❌ SWIFTDATA ERROR:")
            print(error)
            if let swiftDataError = error as? SwiftDataError {
                print("SwiftDataError:", swiftDataError)
            }
            print("Schema models:")
            print(schema)

            DebugLog.write(
                "❌ SwiftData container initialization FAILED: \(error.localizedDescription)"
            )

            AppLogger.persistence.fault(
                "SwiftData ModelContainer error: \(error.localizedDescription)"
            )

            fatalError("SwiftData container initialization failed: \(error)")
        }
    }
}
