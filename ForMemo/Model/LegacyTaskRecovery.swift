import Foundation
import SwiftData
import os

@MainActor
enum LegacyTaskRecovery {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ForMemo",
        category: "legacyRecovery"
    )

    private static var isRunning = false

    static func runIfNeeded(
        context: ModelContext
    ) async {

        DebugLog.writeRecoveryEvent(
            "Recovery started"
        )

        guard !isRunning else {
            log("⏭️ Recovery already running")
            return
        }

        isRunning = true

        defer {
            isRunning = false
        }

        guard LegacyPersistence.legacyStoreExists else {

            log("ℹ️ Legacy store missing")

            return
        }

        do {

            let legacyContainer = try LegacyPersistence.openLegacyContainer()

            let legacyContext = legacyContainer.mainContext

            let taskDescriptor = FetchDescriptor<TodoTask>()

            let attachmentDescriptor = FetchDescriptor<TaskAttachment>()

            let legacyTasks = try legacyContext.fetch(
                taskDescriptor
            )

            let legacyAttachments = try legacyContext.fetch(
                attachmentDescriptor
            )

            log("📦 Legacy tasks found: \(legacyTasks.count)")
            log("📎 Legacy attachments found: \(legacyAttachments.count)")

            guard !legacyTasks.isEmpty else {

                log("ℹ️ Legacy store empty")

                return
            }

            var importedTasks = 0
            var importedAttachments = 0

            for legacyTask in legacyTasks {
                let alreadyExists = try context.fetch(taskDescriptor)
                    .contains {
                        $0.id == legacyTask.id
                    }

                if alreadyExists {

                    log(
                        "⏭️ Task already imported: \(legacyTask.title)"
                    )

                    continue
                }

                let importedTask = TodoTask(
                    id: legacyTask.id,
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
                importedTask.snoozeUntil = legacyTask.snoozeUntil
                importedTask.isDebugTask = legacyTask.isDebugTask

                context.insert(importedTask)

                importedTasks += 1

                let relatedAttachments = legacyAttachments.filter {
                    $0.task?.id == legacyTask.id
                }

                for legacyAttachment in relatedAttachments {

                    if importedTask.attachments == nil {
                        importedTask.attachments = []
                    }

                    let attachmentAlreadyExists = importedTask.attachments?.contains {
                        $0.relativePath == legacyAttachment.relativePath
                    } ?? false

                    if attachmentAlreadyExists {
                        continue
                    }

                    let attachment = TaskAttachment(
                        originalName: legacyAttachment.originalName,
                        relativePath: legacyAttachment.relativePath,
                        contentType: legacyAttachment.contentType,
                        task: importedTask
                    )

                    context.insert(attachment)

                    importedTask.attachments?.append(
                        attachment
                    )

                    importedAttachments += 1
                }
            }

            context.processPendingChanges()

            context.safeSave(
                operation: "LegacyTaskRecovery"
            )

            log("✅ Imported tasks: \(importedTasks)")
            log("✅ Imported attachments: \(importedAttachments)")
            log("✅ Legacy recovery completed successfully")

            DebugLog.writeRecoveryEvent(
                "Recovery completed"
            )

        } catch {

            log(
                "❌ Recovery failed: \(error.localizedDescription)"
            )

            DebugLog.writeRecoveryEvent(
                "Recovery failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Log

    private static func log(
        _ message: String
    ) {

#if DEBUG
        print("🟣 LEGACY RECOVERY:", message)
#endif

        logger.info("\(message)")

        DebugLog.write(
            "LEGACY RECOVERY: \(message)"
        )
    }
}
