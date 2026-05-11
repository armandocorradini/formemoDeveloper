import Foundation
import SwiftData
import os

enum AttachmentMigration {
    
    private static let logger = Logger(subsystem: "com.formemo.migration", category: "migration")
    
    static func runIfNeeded(context: ModelContext) {
        
        log("🚀 MIGRATION START")
        
        let versionKey = "attachmentMigrationVersion"
        let attemptsKey = "attachmentMigrationAttempts"
        let currentVersion = 2
        let maxAttempts = 3

        let defaults = UserDefaults.standard

        let savedVersion = defaults.integer(forKey: versionKey)
        let attempts = defaults.integer(forKey: attemptsKey)

        log("Version: \(savedVersion) → \(currentVersion)")
        log("Migration attempts: \(attempts)/\(maxAttempts)")
        
        guard savedVersion < currentVersion else {
            log("⏭️ Migration already done")
            return
        }
        
        let success = migrate(context: context)
        
        if success {

            defaults.set(currentVersion, forKey: versionKey)
            defaults.set(0, forKey: attemptsKey)

            log("✅ Migration DONE")

        } else {

            let newAttempts = attempts + 1
            defaults.set(newAttempts, forKey: attemptsKey)

            if newAttempts >= maxAttempts {

                // 🔥 evita retry infiniti
                defaults.set(currentVersion, forKey: versionKey)
                defaults.set(0, forKey: attemptsKey)

                log("⚠️ Migration skipped after \(maxAttempts) failed attempts")

            } else {

                log("❌ Migration FAILED → retry next launch")
            }
        }
    }
    
    // MARK: - CORE
    
    private static func migrate(context: ModelContext) -> Bool {
        
        guard let iCloudDir = TaskAttachment.attachmentsDirectory else {
            log("❌ iCloud dir missing")
            return false
        }
        
        guard let legacyDir = legacyDirectory else {
            log("❌ Legacy dir missing")
            return false
        }
        
        let fm = FileManager.default
        
        guard let files = try? fm.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil) else {
            log("⚠️ Cannot read legacy directory")
            return false
        }
        
        log("📦 Legacy files found: \(files.count)")
        
        for fileURL in files {
            let fileName = fileURL.lastPathComponent
            let newURL = iCloudDir.appendingPathComponent(fileName)
            
            log("➡️ Migrating file: \(fileName)")
            
            let newExists = fm.fileExists(atPath: newURL.path)
            
            if newExists {
                log("⏭️ Already exists in iCloud")
                continue
            }
            
            do {
                try fm.copyItem(at: fileURL, to: newURL)
                
                let size = (try? fm.attributesOfItem(atPath: newURL.path)[.size] as? Int64) ?? 0
                
                if size == 0 {
                    try? fm.removeItem(at: newURL)
                    log("❌ Copied file empty")
                    continue
                }
                
                log("✅ Copied OK")
                
            } catch {
                log("❌ Copy error: \(error.localizedDescription)")
            }
        }
        
        // 🔥 opzionale: aggiorna record SwiftData se esistono
        let descriptor = FetchDescriptor<TaskAttachment>()
        
        if let attachments = try? context.fetch(descriptor) {
            for attachment in attachments {
                let fileName = (attachment.relativePath as NSString).lastPathComponent
                attachment.relativePath = fileName
            }
            try? context.save()
        }
        
        return true
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
        DebugLog.write(message)
#endif
        logger.info("\(message)")
        
    }
}
 
