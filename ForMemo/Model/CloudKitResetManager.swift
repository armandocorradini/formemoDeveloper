import Foundation
import SwiftData

enum CloudKitResetManager {

    private static let resetCompletedKey = "cloudKitResetCompleted"

    static func performLocalResetIfNeeded() {

        // 🔥 Run ONLY once
        guard !UserDefaults.standard.bool(
            forKey: resetCompletedKey
        ) else {

            DebugLog.writeCloudKitEvent(
                "Local CloudKit reset already completed"
            )

            return
        }

        DebugLog.writeCloudKitEvent(
            "☁️ Starting LOCAL CloudKit reset"
        )

        let fm = FileManager.default

        // MARK: - SwiftData Stores

        let documents = URL.documentsDirectory

        let possibleStores = [
            // Main CloudKit-backed store
            "default.store",
            "default.store-shm",
            "default.store-wal"
        ]

        for fileName in possibleStores {

            let url = documents.appendingPathComponent(fileName)

            if fm.fileExists(atPath: url.path) {

                do {

                    try fm.removeItem(at: url)

                    DebugLog.writeCloudKitEvent(
                        "🗑 Removed store: \(fileName)"
                    )

                } catch {

                    DebugLog.writeCloudKitEvent(
                        "❌ Failed removing \(fileName): \(error.localizedDescription)"
                    )
                }
            }
        }

        // MARK: - CloudKit Metadata

        let library = fm.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first

        if let library {

            let metadataFolders = [
                "Application Support/CloudKit",
                "Application Support/com.apple.cloudkit",
                "Caches/CloudKit"
            ]

            for relativePath in metadataFolders {

                let url = library.appendingPathComponent(relativePath)

                if fm.fileExists(atPath: url.path) {

                    do {

                        try fm.removeItem(at: url)

                        DebugLog.writeCloudKitEvent(
                            "🗑 Removed CloudKit metadata: \(relativePath)"
                        )

                    } catch {

                        DebugLog.writeCloudKitEvent(
                            "❌ Failed removing metadata \(relativePath): \(error.localizedDescription)"
                        )
                    }
                }
            }
        }

        // MARK: - Sync Tokens / Flags

        let defaults = UserDefaults.standard

        let keysToRemove = [
            "cloudKitResetInProgress",
            "legacyRecoveryCompleted",
            "legacyRecoveryStartDate"
        ]

        for key in keysToRemove {

            defaults.removeObject(forKey: key)
        }

        defaults.set(
            true,
            forKey: resetCompletedKey
        )

        defaults.synchronize()

        DebugLog.writeCloudKitEvent(
            "✅ LOCAL CloudKit reset completed"
        )
    }
}
