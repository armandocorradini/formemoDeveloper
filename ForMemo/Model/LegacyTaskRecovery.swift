import Foundation
import SwiftData
import os

@MainActor
enum LegacyTaskRecovery {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ForMemo",
        category: "legacyRecovery"
    )

    private static var isRunning = false

    static func runIfNeeded(
        context: ModelContext
    ) async {

        DebugLog.writeRecoveryEvent(
            "Recovery started"
        )

        guard !isRunning else {
            log("⏭️ Recovery already running")
            return
        }

        isRunning = true

        defer {
            isRunning = false
        }

        // 🔥 SINGLE LOCAL-FIRST STORE
        // Tasks already exist directly inside local.store.
        // No import is required anymore.

        let existingTaskCount = (
            try? context.fetchCount(
                FetchDescriptor<TodoTask>()
            )
        ) ?? 0

        log(
            "ℹ️ Single-store mode active"
        )

        log(
            "ℹ️ Existing tasks in local store: \(existingTaskCount)"
        )

        log(
            "⏭️ Legacy import skipped (no longer needed)"
        )

        return
    }

    // MARK: - Log

    private static func log(
        _ message: String
    ) {

#if DEBUG
        print("🟣 LEGACY RECOVERY:", message)
#endif

        logger.info("\(message)")

        DebugLog.write(
            "LEGACY RECOVERY: \(message)"
        )
    }
}
