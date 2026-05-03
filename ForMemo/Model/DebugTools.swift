#if DEBUG
import Foundation
import SwiftData

enum DebugTools {
    
    static let testTitle = "TESTTEST"
    
    // MARK: - Generate
    
    static func generateTasks(context: ModelContext, count: Int = 1000) {
        let start = Date()
        let calendar = Calendar.current
        let now = Date()
        
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = true }
        
        for i in 0..<count {
            let task = TodoTask(
                title: testTitle,
                deadLine: calendar.date(byAdding: .hour, value: i, to: now)
            )
            
            // 🔴 IMPORTANTE: evita notifiche / logiche pesanti
            task.isDebugTask = true
            
            context.insert(task)
        }
        
        try? context.save()
        
        print("✅ Generated \(count) tasks in \(Date().timeIntervalSince(start)) sec")
    }
    
    // MARK: - Complete

    static func completeTasks(context: ModelContext) {
        let start = Date()
        
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.title == testTitle }
        )
        
        if let tasks = try? context.fetch(descriptor) {
            for task in tasks {
                task.isCompleted = true
                task.completedAt = .now
                task.snoozeUntil = nil
            }
        }
        
        try? context.save()
        
        print("✅ Completed debug tasks in \(Date().timeIntervalSince(start)) sec")
    }

    // MARK: - Delete
    
    static func deleteTasks(context: ModelContext) {
        let start = Date()
        
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.title == testTitle }
        )
        
        if let tasks = try? context.fetch(descriptor) {
            for task in tasks {
                context.delete(task)
            }
        }
        
        try? context.save()
        
        print("🗑 Deleted tasks in \(Date().timeIntervalSince(start)) sec")
    }
    
    // MARK: - Check
    
    static func hasTestTasks(context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.title == testTitle }
        )
        
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count > 0
    }

    static func areTestTasksCompleted(context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.title == testTitle }
        )
        
        guard let tasks = try? context.fetch(descriptor), !tasks.isEmpty else {
            return false
        }
        
        return tasks.allSatisfy { $0.isCompleted }
    }
    
    // MARK: - Migration iCloud Attachments

    static func migrateAttachmentsToiCloud(context: ModelContext) {
        
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
            
            guard let currentURL = attachment.fileURL else {
                print("⚠️ Missing URL for:", attachment.originalName)
                continue
            }
            
            let fileName = currentURL.lastPathComponent
            let destinationURL = iCloudDir.appendingPathComponent(fileName)
            
            let isAlreadyInICloud = currentURL.path.contains("Mobile Documents")
            
            // ✅ Caso 1: già perfetto
            if isAlreadyInICloud {
                print("✅ Already in iCloud:", fileName)
                continue
            }
            
            // ❗ Caso 2: file esiste già in iCloud
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                attachment.relativePath = fileName
                print("♻️ Linked existing iCloud file:", fileName)
                continue
            }
            
            // ❗ Caso 3: file locale esiste → copia
            if FileManager.default.fileExists(atPath: currentURL.path) {
                do {
                    try FileManager.default.copyItem(at: currentURL, to: destinationURL)
                    attachment.relativePath = fileName
                    print("⬆️ Migrated:", fileName)
                } catch {
                    print("❌ Copy failed:", fileName, error.localizedDescription)
                }
            } else {
                print("❌ Source file missing:", fileName)
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
#endif
