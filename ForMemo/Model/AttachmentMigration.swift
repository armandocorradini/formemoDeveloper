import Foundation
import SwiftData
import os

enum AttachmentMigration {
    
    private static let logger = Logger(subsystem: "com.formemo.migration", category: "migration")
    private static var isRunning = false
    
    static func runIfNeeded(context: ModelContext) {
        
        log("🚀 MIGRATION START")
        
        // 🔥 Prevent overlapping migrations
        guard !isRunning else {
            log("⏭️ Migration already running")
            return
        }

        isRunning = true

        defer {
            isRunning = false
        }
        
        let versionKey = "attachmentMigrationVersion"
        let currentVersion = 3

        let defaults = UserDefaults.standard

        let savedVersion = defaults.integer(forKey: versionKey)

        log("Version: \(savedVersion) → \(currentVersion)")
        
        guard savedVersion < currentVersion else {
            log("⏭️ Migration already done")
            return
        }
        
        let success = migrate(context: context)

        if success {

            defaults.set(currentVersion, forKey: versionKey)

            log("✅ Migration DONE")

        } else {

            log("⚠️ Migration partially completed - retry next launch")
        }
    }
    
    // MARK: - CORE
    
    private static func migrate(context: ModelContext) -> Bool {
        
        guard let iCloudDir = TaskAttachment.attachmentsDirectory else {
            log("❌ iCloud dir missing")
            return false
        }

        guard let legacyDir = legacyDirectory else {
            log("⚠️ Legacy dir unavailable")
            return true
        }

        // 🔥 No legacy attachments on this device
        // (fresh install or already migrated)
        guard FileManager.default.fileExists(atPath: legacyDir.path) else {
            log("ℹ️ Legacy attachment directory not found")
            return true
        }

        let fm = FileManager.default
        var allFilesMigrated = true

        guard let files = try? fm.contentsOfDirectory(
            at: legacyDir,
            includingPropertiesForKeys: nil
        ) else {
            log("⚠️ Cannot read legacy directory")
            return false
        }

        // 🔥 Nothing to migrate
        if files.isEmpty {
            log("ℹ️ No legacy attachments to migrate")
            return true
        }
        
        log("📦 Legacy files found: \(files.count)")
        
        for fileURL in files {
            let fileName = fileURL.lastPathComponent
            // 🔥 Verify source file is readable
            guard fm.isReadableFile(atPath: fileURL.path) else {
                allFilesMigrated = false
                log("❌ Legacy file unreadable: \(fileName)")
                continue
            }
            let newURL = iCloudDir.appendingPathComponent(fileName)

            log("➡️ Migrating file: \(fileName)")

            let newExists = fm.fileExists(atPath: newURL.path)

            if newExists {
                log("⏭️ Already exists in iCloud")
                continue
            }

            do {

                // ensure parent dir exists
                try fm.createDirectory(
                    at: iCloudDir,
                    withIntermediateDirectories: true
                )

                try fm.copyItem(at: fileURL, to: newURL)

                // force iCloud materialization/upload
                var uploadReady = false

                for _ in 0..<20 {

                    if fm.fileExists(atPath: newURL.path) {

                        let size = (try? fm.attributesOfItem(
                            atPath: newURL.path
                        )[.size] as? Int64) ?? 0

                        if size > 0 {
                            uploadReady = true
                            break
                        }
                    }

                    Thread.sleep(forTimeInterval: 0.25)
                }

                guard uploadReady else {
                    try? fm.removeItem(at: newURL)
                    allFilesMigrated = false
                    log("❌ Copied file not materialized")
                    continue
                }

                // 🔥 verify copied file integrity
                let originalSize = (try? fm.attributesOfItem(
                    atPath: fileURL.path
                )[.size] as? Int64) ?? 0

                let copiedSize = (try? fm.attributesOfItem(
                    atPath: newURL.path
                )[.size] as? Int64) ?? 0

                guard originalSize > 0,
                      copiedSize == originalSize else {

                    try? fm.removeItem(at: newURL)
                    allFilesMigrated = false

                    log("❌ Integrity verification failed")
                    continue
                }

                // trigger ubiquitous upload/download state
                try? fm.startDownloadingUbiquitousItem(at: newURL)

                log("✅ Copied OK")

            } catch {
                allFilesMigrated = false
                log("❌ Copy error: \(error.localizedDescription)")
            }
        }
        
        // verify migrated files exist physically
        let migratedFiles = (try? fm.contentsOfDirectory(
            at: iCloudDir,
            includingPropertiesForKeys: nil
        )) ?? []

        log("☁️ iCloud files available: \(migratedFiles.count)")

        return allFilesMigrated
    }
    
    // MARK: - LEGACY PATH
    
    private static var legacyDirectory: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TaskAttachments", isDirectory: true)
    }
    
    // MARK: - LOG (TestFlight visible)
    
    private static func log(_ message: String) {
#if DEBUG
        print("🟣 MIGRATION:", message)
#endif
        logger.info("\(message)")
        
    }
}
 
