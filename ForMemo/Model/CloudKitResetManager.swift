import Foundation
import SwiftData

enum CloudKitResetManager {

    static func performLocalResetIfNeeded() {

        // 🔥 LOCAL-FIRST ARCHITECTURE
        // CloudKit reset logic permanently disabled.
        // The local SQLite database is now the only source of truth.
        // CloudKit operates only as a background sync layer.

        DebugLog.writeCloudKitEvent(
            "CloudKit reset skipped (local persistence architecture)"
        )
    }
}
