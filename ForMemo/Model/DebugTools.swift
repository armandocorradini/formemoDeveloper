import Foundation
import SwiftData
import UIKit

enum DebugTools {
    
    static let testTitle = "TESTTEST"
    
    // MARK: - Generate
    
    static func generateTasks(context: ModelContext, count: Int = 400) {
        let start = Date()
        let calendar = Calendar.current
        let now = Date()
        
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = true }
        
        for i in 0..<count {
            let task = TodoTask(
                title: testTitle,
                deadLine: calendar.date(byAdding: .hour, value: i * 24, to: now)
            )
            
            // 🔴 IMPORTANTE: evita notifiche / logiche pesanti
            task.isDebugTask = true

            // 📎 Real debug attachment for performance testing
            if i % 3 == 0,
               let attachmentsDir = TaskAttachment.attachmentsDirectory {

                let fileName = "debug_app_icon.png"
                let destinationURL = attachmentsDir.appendingPathComponent(fileName)
                let fm = FileManager.default

                // Generate a real image file if missing
                if !fm.fileExists(atPath: destinationURL.path) {

                    let config = UIImage.SymbolConfiguration(pointSize: 120, weight: .regular)

                    if let image = UIImage(
                        systemName: "checkmark.circle.dotted",
                        withConfiguration: config
                    ),
                    let data = image.pngData() {

                        try? data.write(to: destinationURL)
                    }
                }

                // Only create attachment if file really exists
                if fm.fileExists(atPath: destinationURL.path) {

                    let attachment = TaskAttachment(
                        originalName: fileName,
                        relativePath: fileName,
                        contentType: "image/png",
                        task: task
                    )

                    task.attachments = [attachment]
                }
            }
            
            context.insert(task)
        }
        
        try? context.save()
#if DEBUG
        print("✅ Generated \(count) tasks in \(Date().timeIntervalSince(start)) sec")
        
#endif
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
#if DEBUG
        print("✅ Completed debug tasks in \(Date().timeIntervalSince(start)) sec")
#endif
        
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
#if DEBUG
        print("🗑 Deleted tasks in \(Date().timeIntervalSince(start)) sec")
#endif
        
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

    
    // MARK: - Reset Preferences
    
    static func resetPreferences() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }
    }
}

enum DebugLog {
    
    static func write(_ message: String) {
        
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("migration.log")
        
        let line = "\(Date()): \(message)\n"
        
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: url)
            }
        }
    }
}
