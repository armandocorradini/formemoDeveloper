import Foundation
import SwiftData
import os

@MainActor
enum LegacyTaskRecovery {
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ForMemo",
        category: "legacyRecovery"
    )
    private static let recoveryStartKey = "legacyRecoveryStartDate"
    private static let recoveryCompletedKey = "legacyRecoveryCompleted"
    private static let recoveredFingerprintsKey = "legacyRecoveredFingerprints"
    private static let recoveryWindowDays = 14
    
    private static func shouldRunRecovery() -> Bool {
        
        let defaults = UserDefaults.standard
        
        if defaults.bool(forKey: recoveryCompletedKey) {
            log("⏭️ Recovery permanently completed")
            return false
        }
        
        let now = Date()
        
        let startDate: Date
        
        if let existing = defaults.object(
            forKey: recoveryStartKey
        ) as? Date {
            
            startDate = existing
            
        } else {
            
            startDate = now
            
            defaults.set(
                now,
                forKey: recoveryStartKey
            )
            
            log("🚀 Recovery window started")
        }
        
        let elapsed = now.timeIntervalSince(startDate)
        let limit = Double(recoveryWindowDays) * 86400
        
        if elapsed > limit {
            
            defaults.set(
                true,
                forKey: recoveryCompletedKey
            )
            
            log("✅ Recovery window expired")
            
            return false
        }
        
        let remainingDays = Int(
            ceil((limit - elapsed) / 86400)
        )
        
        log("🕒 Recovery active - remaining days: \(remainingDays)")
        
        return true
    }
    
    private struct TaskFingerprint: Hashable {
        let normalizedTitle: String
        let deadline: Int?
        let created: Int
    }
    
    static func runIfNeeded(context: ModelContext) async {
        DebugLog.writeRecoveryEvent("Recovery started")
        
        guard shouldRunRecovery() else {
            DebugLog.writeRecoveryEvent(
                "Recovery skipped"
            )
            return
        }
        
        guard LegacyPersistence.legacyStoreExists else {
            log("ℹ️ No legacy local.store found")
            DebugLog.writeRecoveryEvent("Legacy store missing")
            return
        }
        
        do {
            
            let legacyContainer = try LegacyPersistence.openLegacyContainer()
            DebugLog.writeRecoveryEvent(
                "Legacy store opened successfully"
            )
            
            let legacyContext = legacyContainer.mainContext
            
            let descriptor = FetchDescriptor<TodoTask>()
            
            let legacyTasks = try legacyContext.fetch(descriptor)
            
            log("⏳ Waiting CloudKit stabilization before recovery")
            
            try? await Task.sleep(
                for: .seconds(15)
            )
            
            let currentTasks = try context.fetch(descriptor)
            
            log("📦 Legacy tasks: \(legacyTasks.count)")
            log("☁️ Current tasks: \(currentTasks.count)")
            
            if currentTasks.count > 0 {
                
                log(
                    "⚠️ Existing CloudKit tasks detected before recovery"
                )
            }
            
            guard !legacyTasks.isEmpty else {
                log("ℹ️ Legacy store empty")
                return
            }
            
            let currentFingerprints = Set(
                currentTasks.map(buildFingerprint)
            )
            
            var recoveredFingerprints = Set(
                UserDefaults.standard.stringArray(
                    forKey: recoveredFingerprintsKey
                ) ?? []
            )
            
            var imported = 0
            var skipped = 0
            
            for legacyTask in legacyTasks {
                
                let fingerprint = buildFingerprint(for: legacyTask)
                
                let persistentFingerprint = buildPersistentFingerprint(
                    for: legacyTask
                )
                
                if DeletedFingerprintStore.isDeleted(
                    persistentFingerprint
                ) {
                    
                    skipped += 1
                    
                    log(
                        "🚫 Previously deleted task blocked: \(legacyTask.title)"
                    )
                    
                    continue
                }
                
                if recoveredFingerprints.contains(
                    persistentFingerprint
                ) {
                    
                    skipped += 1
                    
                    log(
                        "⏭️ Already recovered previously: \(legacyTask.title)"
                    )
                    
                    continue
                }
                
                if currentFingerprints.contains(fingerprint) {
                    skipped += 1
                    continue
                }
                
                let importedTask = TodoTask(
                    title: legacyTask.title,
                    taskDescription: legacyTask.taskDescription,
                    deadLine: legacyTask.deadLine,
                    reminderOffsetMinutes: legacyTask.reminderOffsetMinutes,
                    locationName: legacyTask.locationName,
                    locationLatitude: legacyTask.locationLatitude,
                    locationLongitude: legacyTask.locationLongitude
                )
                
                importedTask.priority = legacyTask.priority
                importedTask.mainTag = legacyTask.mainTag
                importedTask.isCompleted = legacyTask.isCompleted
                importedTask.createdAt = legacyTask.createdAt
                importedTask.completedAt = legacyTask.completedAt
                
                context.insert(importedTask)
                
                recoveredFingerprints.insert(
                    persistentFingerprint
                )
                
                imported += 1
            }
            
            if context.hasChanges {
                context.safeSave(operation: "LegacyTaskRecovery")
            }
            
            UserDefaults.standard.set(
                Array(recoveredFingerprints),
                forKey: recoveredFingerprintsKey
            )
            
            log("✅ Imported missing tasks: \(imported)")
            log("⏭️ Skipped existing tasks: \(skipped)")
            DebugLog.writeRecoveryEvent("Recovery completed")
            
        } catch {
            
            log("❌ Legacy recovery failed: \(error.localizedDescription)")
            DebugLog.writeRecoveryEvent(
                "Recovery failed: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Fingerprint
    
    private static func buildFingerprint(
        for task: TodoTask
    ) -> TaskFingerprint {
        
        let normalizedTitle = task.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        let deadline = task.deadLine.map {
            Int($0.timeIntervalSince1970 / 60)
        }
        
        let created = Int(task.createdAt.timeIntervalSince1970 / 60)
        
        return TaskFingerprint(
            normalizedTitle: normalizedTitle,
            deadline: deadline,
            created: created
        )
    }
    
    private static func buildPersistentFingerprint(
        for task: TodoTask
    ) -> String {
        
        let normalizedTitle = task.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        let deadline = Int(
            (task.deadLine ?? .distantPast)
                .timeIntervalSince1970 / 60
        )
        
        return "\(normalizedTitle)|\(deadline)"
    }
    
    // MARK: - Log
    
    private static func log(_ message: String) {
        
#if DEBUG
        print("🟣 LEGACY RECOVERY:", message)
#endif
        
        logger.info("\(message)")
        
        DebugLog.write("LEGACY RECOVERY: \(message)")
    }
}
