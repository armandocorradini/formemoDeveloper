import Foundation
import SwiftData

enum AttachmentMigration {
    
    private static var isRunning = false
    
    static func runIfNeeded(context: ModelContext) {

        guard !isRunning else {
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
        
        guard savedVersion < currentVersion else {
            return
        }
        let success = migrate(context: context)

        if success {

            defaults.set(currentVersion, forKey: versionKey)

        } else {

        }
    }
    
    // MARK: - Migration
    
    private static func migrate(context: ModelContext) -> Bool {
        
        guard let iCloudDir = TaskAttachment.attachmentsDirectory else {
            
            return false
        }

        guard let legacyDir = legacyDirectory else {

            return true
        }

        guard FileManager.default.fileExists(atPath: legacyDir.path) else {

            return true
        }
        let fm = FileManager.default

//        let attachmentsByRelativePath = Dictionary(
//            uniqueKeysWithValues: attachments.map {
//                ($0.relativePath, $0)
//            }
//        )
        var allFilesMigrated = true

        guard let files = try? fm.contentsOfDirectory(
            at: legacyDir,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        if files.isEmpty {
            return true
        }
        
        for fileURL in files {
            let fileName = fileURL.lastPathComponent
            guard fm.isReadableFile(atPath: fileURL.path) else {
                allFilesMigrated = false
                continue
            }
            let newURL = iCloudDir.appendingPathComponent(fileName)
            let newExists = fm.fileExists(atPath: newURL.path)

            if newExists {
                continue
            }
            do {
                try fm.createDirectory(
                    at: iCloudDir,
                    withIntermediateDirectories: true
                )
//                let legacySize = (try? fm.attributesOfItem(
//                    atPath: fileURL.path
//                )[.size] as? Int64) ?? 0
//                try fm.copyItem(at: fileURL, to: newURL)
                
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
                    RunLoop.current.run(
                        until: Date().addingTimeInterval(0.25)
                    )
                }
                guard uploadReady else {
                    allFilesMigrated = false
                    continue
                }
                let originalSize = (try? fm.attributesOfItem(
                    atPath: fileURL.path
                )[.size] as? Int64) ?? 0
                let copiedSize = (try? fm.attributesOfItem(
                    atPath: newURL.path
                )[.size] as? Int64) ?? 0
                guard originalSize > 0,
                      copiedSize == originalSize else {

                    allFilesMigrated = false

                    continue
                }

            } catch {
                allFilesMigrated = false
            }
        }

        if context.hasChanges {
            try? context.save()
        }
        return allFilesMigrated
    }
    
    // MARK: - Legacy Path
    
    private static var legacyDirectory: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TaskAttachments", isDirectory: true)
    }

}
 
