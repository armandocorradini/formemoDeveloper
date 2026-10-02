import SwiftData
import Foundation
import os

@MainActor
final class NotificationActionProcessor {
    
    static let shared = NotificationActionProcessor()
    
    private init() {}

    // MARK: - Manual Snooze (Context Menu)
    func applyManualSnooze(
        to task: TodoTask,
        interval: TimeInterval,
        using context: ModelContext
    ) {
        // Manual snooze requested from the app UI.
        // This is intentionally independent from notification-action snooze.
        task.manualSnoozeUntil = Date().addingTimeInterval(interval)
        task.snoozeUntil = nil

        do {
            try context.save()
            context.processPendingChanges()
            NotificationManager.shared.refresh(force: true)
        } catch {
            AppLogger.persistence.fault("Failed to apply snooze: \(error)")
        }
    }
    
    func processAll(using context: ModelContext) {
        processCompletion(using: context)
    }

    private func processCompletion(using context: ModelContext) {
        guard let id = UserDefaults.standard.string(
            forKey: "completeTaskFromNotification"
        ),
        let uuid = UUID(uuidString: id)
        else {
            return
        }

        UserDefaults.standard.removeObject(
            forKey: "completeTaskFromNotification"
        )

        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.id == uuid }
        )

        guard let task = try? context.fetch(descriptor).first else {
            AppLogger.notifications.error(
                "Completion failed: task not found"
            )
            return
        }

        task.isCompleted = true
        task.completedAt = .now
        task.snoozeUntil = nil
        task.manualSnoozeUntil = nil

        do {
            try context.save()
            context.processPendingChanges()
            NotificationManager.shared.refresh(force: true)
            NotificationCenter.default.post(
                name: .taskDidChange,
                object: nil
            )
        } catch {
            AppLogger.persistence.fault(
                "Failed to complete task from notification: \(error.localizedDescription)"
            )
        }
    }
}
