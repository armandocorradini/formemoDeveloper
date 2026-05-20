import SwiftData
import SwiftUI
import Foundation
import os

enum Persistence {
    private static let cloudKitContainerID =
        "iCloud.corradini.armando.NewTask"

    private static let schema = Schema([
        TodoTask.self,
        TaskAttachment.self,
        DeletedItem.self
    ])


    static func makeModelContainer(
        cloudKitEnabled: Bool
    ) -> ModelContainer {

        DebugLog.write(
            cloudKitEnabled
            ? "☁️ CLOUDKIT: Preparing SwiftData container"
            : "🟠 BOOTSTRAP: Preparing LOCAL SwiftData container"
        )

        do {

            let configuration: ModelConfiguration

            if cloudKitEnabled {

                configuration = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private(cloudKitContainerID)
                )

            } else {

                let bootstrapURL = URL.documentsDirectory
                    .appendingPathComponent("bootstrap.store")

                DebugLog.write(
                    "🟠 BOOTSTRAP: Using isolated bootstrap store: \(bootstrapURL.lastPathComponent)"
                )

                configuration = ModelConfiguration(
                    schema: schema,
                    url: bootstrapURL,
                    cloudKitDatabase: .none
                )
            }

            let container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )

            DebugLog.write(
                cloudKitEnabled
                ? "☁️ CLOUDKIT: SwiftData container initialized"
                : "🟠 BOOTSTRAP: LOCAL SwiftData container initialized"
            )

            return container

        } catch {

            DebugLog.write(
                "❌ SwiftData container initialization FAILED: \(error.localizedDescription)"
            )

            AppLogger.persistence.fault(
                "SwiftData ModelContainer error: \(error.localizedDescription)"
            )

            fatalError(
                "SwiftData ModelContainer initialization failed: \(error.localizedDescription)"
            )
        }
    }
}
