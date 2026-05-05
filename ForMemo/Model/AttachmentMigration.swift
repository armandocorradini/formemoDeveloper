import Foundation
import SwiftData

enum AttachmentMigration {
    
    private static let migrationKey = "didMigrateAttachmentsToiCloud"
    
    static func runIfNeeded(context: ModelContext) {
        let alreadyMigrated = UserDefaults.standard.bool(forKey: migrationKey)
        
        guard !alreadyMigrated else { return }
        
        migrateToiCloud(context: context)
        
        UserDefaults.standard.set(true, forKey: migrationKey)
    }
    
    private static func migrateToiCloud(context: ModelContext) {
        
        guard let iCloudDir = TaskAttachment.attachmentsDirectory else {
            print("❌ iCloud directory not available")
            return
        }
        
        let descriptor = FetchDescriptor<TaskAttachment>()
        
        guard let attachments = try? context.fetch(descriptor) else {
            print("❌ Failed to fetch attachments")
            return
        }
        
        print("🔄 Starting migration for \(attachments.count) attachments")
        
        for attachment in attachments {
            
            guard let currentURL = attachment.fileURL else { continue }
            
            let fileName = currentURL.lastPathComponent
            let destinationURL = iCloudDir.appendingPathComponent(fileName)
            
            let isAlreadyInICloud = currentURL.path.contains("Mobile Documents")
            
            if isAlreadyInICloud {
                continue
            }
            
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                attachment.relativePath = fileName
                continue
            }
            
            if FileManager.default.fileExists(atPath: currentURL.path) {
                do {
                    try FileManager.default.copyItem(at: currentURL, to: destinationURL)
                    attachment.relativePath = fileName
                } catch {
                    print("❌ Copy failed:", fileName, error.localizedDescription)
                }
            }
        }
        
        do {
            try context.save()
            print("✅ Migration completed")
        } catch {
            print("❌ Save failed:", error.localizedDescription)
        }
    }
}
