#if DEBUG
import Foundation
import SwiftData

enum DebugTools {
    
    static let testTitle = "TESTTEST"
    
    // MARK: - Generate
    
    static func generateTasks(context: ModelContext, count: Int = 2000) {
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
}
#endif
