import SwiftData
import Foundation
import os

@MainActor
final class NotificationActionProcessor {
    
    static let shared = NotificationActionProcessor()
    
    private init() {}
    
    func processAll(using context: ModelContext) {
        processSnooze(using: context)
    }
    private func processSnooze(using context: ModelContext) {
        
        guard let data = UserDefaults.standard.data(forKey: "snoozeTaskFromNotification"),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = payload["id"] as? String,
              let interval = payload["interval"] as? TimeInterval,
              let uuid = UUID(uuidString: id)
        else { return }
        
        UserDefaults.standard.removeObject(forKey: "snoozeTaskFromNotification")
        
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.id == uuid }
        )
        
        if let task = try? context.fetch(descriptor).first {
            task.snoozeUntil = Date().addingTimeInterval(interval)
        } else {
            AppLogger.notifications.error("Snooze failed: task not found")
        }
        
        try? context.save()
        context.processPendingChanges()
    }
}
