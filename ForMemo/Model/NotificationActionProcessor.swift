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
        // Reserved for future notification actions.
    }
}
