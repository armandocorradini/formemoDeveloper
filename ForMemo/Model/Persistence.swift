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
        DocumentItem.self
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

            print("❌ SWIFTDATA ERROR:")
            print(error)

            DebugLog.write(
                "❌ SwiftData container initialization FAILED: \(error.localizedDescription)"
            )

            AppLogger.persistence.fault(
                "SwiftData ModelContainer error: \(error.localizedDescription)"
            )

            do {

                return try ModelContainer(
                    for: schema,
                    configurations: [
                        ModelConfiguration(
                            schema: schema,
                            isStoredInMemoryOnly: true
                        )
                    ]
                )

            } catch {

                DebugLog.write(
                    "❌ In-memory SwiftData container initialization FAILED: \(error.localizedDescription)"
                )

                AppLogger.persistence.fault(
                    "In-memory SwiftData ModelContainer error: \(error.localizedDescription)"
                )

                fatalError(
                    "Unable to create any SwiftData ModelContainer: \(error.localizedDescription)"
                )
            }
        }
    }
}
