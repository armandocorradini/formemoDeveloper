import Foundation
import SwiftData
import SwiftUI
import AlarmKit
import ActivityKit
import os


private struct ForMemoAlarmMetadata: AlarmMetadata {}

@MainActor
final class ForMemoAlarmManager {

    static let shared = ForMemoAlarmManager()

    private let alarmManager = AlarmManager.shared
    
    func logScheduledAlarmsCount() {
        do {
            let alarms = try alarmManager.alarms

            let scheduledAlarms = alarms.filter { alarm in
                if case .scheduled = alarm.state {
                    return true
                }
                return false
            }

            AppLogger.notifications.info(
                "🔔 AlarmKit: \(alarms.count) total — \(scheduledAlarms.count) scheduled"
            )

//            for alarm in alarms {
//                print(
//                    "🔔 AlarmKit ID: \(alarm.id.uuidString) — state: \(String(describing: alarm.state))"
//                )
//            }
        } catch {
            print("❌ AlarmKit: unable to read scheduled alarms: \(error)")
        }
    }
    
    func scheduledAlarmCount() -> Int? {
        do {
            let alarms = try alarmManager.alarms

            return alarms.reduce(into: 0) { count, alarm in
                if case .scheduled = alarm.state {
                    count += 1
                }
            }

        } catch {
            AppLogger.notifications.error(
                "❌ AlarmKit count failed: \(error.localizedDescription)"
            )
            return nil
        }
    }
    
    private func verifySynchronization(tasks: [TodoTask]) async -> Bool {
        do {
            let alarms = try alarmManager.alarms

            let scheduledAlarmIDs = Set(
                alarms.compactMap { alarm -> UUID? in
                    if case .scheduled = alarm.state {
                        return alarm.id
                    }
                    return nil
                }
            )

            var mismatchedTaskIDs: [UUID] = []

            for task in tasks {
                let shouldBeScheduled =
                    task.alarmEnabled &&
                    !task.isCompleted &&
                    task.deadLine.map { $0 > .now } ?? false

                let isScheduled = scheduledAlarmIDs.contains(task.id)

                if shouldBeScheduled != isScheduled {
                    mismatchedTaskIDs.append(task.id)
                }
            }

            if mismatchedTaskIDs.isEmpty {
                AppLogger.notifications.info(
                    "✅ AlarmKit batch synchronization verified: \(tasks.count) tasks"
                )
                return true
            }

            AppLogger.notifications.error(
                "❌ AlarmKit batch synchronization mismatch: \(mismatchedTaskIDs.count) tasks"
            )

            return false

        } catch {
            AppLogger.notifications.error(
                "❌ AlarmKit batch synchronization verification failed: \(error.localizedDescription)"
            )
            return false
        }
    }
    private func verifySynchronization(task: TodoTask) async -> Bool {
        do {
            let alarms = try alarmManager.alarms

            let shouldBeScheduled =
                task.alarmEnabled &&
                !task.isCompleted &&
                task.deadLine.map { $0 > .now } ?? false

            let isScheduled = alarms.contains { alarm in
                guard alarm.id == task.id else { return false }

                if case .scheduled = alarm.state {
                    return true
                }

                return false
            }

            if shouldBeScheduled == isScheduled {
                return true
            }

            AppLogger.notifications.error(
                "❌ AlarmKit task synchronization mismatch: \(task.id.uuidString) — expected scheduled: \(shouldBeScheduled), actual scheduled: \(isScheduled)"
            )

            return false

        } catch {
            AppLogger.notifications.error(
                "❌ AlarmKit task verification failed: \(error.localizedDescription)"
            )
            return false
        }
    }
    
    private var synchronizationTasks: [UUID: Task<Bool, Never>] = [:]
    
    private var pendingBatchSynchronization: Task<Bool, Never>?
    
    private func performSynchronization(task: TodoTask) async {
        let alarmID = task.id

        guard task.alarmEnabled,
              let deadline = task.deadLine,
              !task.isCompleted,
              deadline > .now else {

            do {
                try await cancelAlarm(id: alarmID)

                AppLogger.notifications.info(
                    "🔕 AlarmKit cancel succeeded: \(alarmID.uuidString)"
                )
            } catch {
                AppLogger.notifications.error(
                    "❌ AlarmKit cancel FAILED: \(alarmID.uuidString) — \(error.localizedDescription)"
                )
            }

            return
        }

        do {
            try? await cancelAlarm(id: alarmID)

            try await scheduleAlarm(
                id: alarmID,
                date: deadline,
                title: task.title
            )

        } catch {
            AppLogger.notifications.error(
                "ForMemo AlarmKit synchronization failed: \(error.localizedDescription)"
            )
        }
    }
    
    
    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async throws {
        _ = try await alarmManager.requestAuthorization()
    }

    func authorizationState() -> AlarmManager.AuthorizationState {
        alarmManager.authorizationState
    }

    // MARK: - Schedule

    func scheduleAlarm(
        id: UUID,
        date: Date,
        title: String
    ) async throws {

        let stopButton = AlarmButton(
            text: "Stop",
            textColor: .white,
            systemImageName: "stop.circle"
        )

        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stopButton
        )

        let attributes = AlarmAttributes<ForMemoAlarmMetadata>(
            presentation: AlarmPresentation(
                alert: alertPresentation
            ),
            metadata: nil,
            tintColor: Color.accentColor
        )

        typealias AlarmConfiguration =
            AlarmManager.AlarmConfiguration<ForMemoAlarmMetadata>

        let configuration = AlarmConfiguration.alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: .default
        )

        _ = try await alarmManager.schedule(
            id: id,
            configuration: configuration
        )
    }

    // MARK: - Cancel

    func cancelAlarm(id: UUID) async throws {
        try alarmManager.cancel(id: id)
    }

    func cancelAlarmIfNeeded(id: UUID) {
        Task { @MainActor in
            do {
                try await cancelAlarm(id: id)
                logScheduledAlarmsCount()
            } catch {
                AppLogger.notifications.error(
                    "AlarmKit cancellation failed for task \(id.uuidString): \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Synchronize

    func synchronize(task: TodoTask) async -> Bool {
        let alarmID = task.id
        let previousSynchronization = synchronizationTasks[alarmID]

        let currentSynchronization = Task { @MainActor in
            _ = await previousSynchronization?.value
            await performSynchronization(task: task)
            return await verifySynchronization(task: task)
        }

        synchronizationTasks[alarmID] = currentSynchronization

        return await currentSynchronization.value
    }
    
    func synchronize(tasks: [TodoTask]) async -> Bool {
        let previousSynchronization = pendingBatchSynchronization

        let currentSynchronization = Task { @MainActor in
            _ = await previousSynchronization?.value

            for task in tasks {
                await performSynchronization(task: task)
            }

            let verified = await verifySynchronization(tasks: tasks)

            logScheduledAlarmsCount()

            return verified
        }

        pendingBatchSynchronization = currentSynchronization

        return await currentSynchronization.value
    }
    
    func waitForPendingSynchronizations() async {
        _ = await pendingBatchSynchronization?.value
    }
    

    func cancelAlarms(ids: [UUID]) async {
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    try? await self.cancelAlarm(id: id)
                }
            }
        }
    }
    
    func removeOrphanedAlarms(tasks: [TodoTask]) async {
        
//        let startTime = Date()
//
//        AppLogger.notifications.info(
//            "🔔 AlarmKit orphan cleanup START"
//        )
        
        
        do {
            let scheduledAlarms = try alarmManager.alarms
            let referenceDate = Date.now
            let eligibleTaskIDs = Set(
                tasks.compactMap { task -> UUID? in
                    guard task.alarmEnabled,
                          !task.isCompleted,
                          let deadline = task.deadLine,
                          deadline > referenceDate else {
                        return nil
                    }
                    return task.id
                }
            )

            var removedCount = 0

            for alarm in scheduledAlarms {
                guard !eligibleTaskIDs.contains(alarm.id) else {
                    continue
                }

                do {
                    try alarmManager.cancel(id: alarm.id)
                    removedCount += 1
                } catch {
                    AppLogger.notifications.error(
                        "Failed to remove orphaned AlarmKit alarm \(alarm.id.uuidString): \(error.localizedDescription)"
                    )
                }
            }

            
//            let elapsed = Date().timeIntervalSince(startTime)

//            AppLogger.notifications.info(
//                "🔔 AlarmKit orphan cleanup END — \(removedCount) alarms removed in \(String(format: "%.2f", elapsed)) s"
//            )
            
            
            AppLogger.notifications.info(
                "🔔 AlarmKit orphan cleanup: removed \(removedCount) alarms"
            )

            logScheduledAlarmsCount()

        } catch {
            AppLogger.notifications.error(
                "AlarmKit orphan cleanup failed: \(error.localizedDescription)"
            )
        }
    }
    
    
    func removeOrphanedAlarmsAtStartup(context: ModelContext) async {
        do {
            let scheduledAlarms = try alarmManager.alarms

            guard !scheduledAlarms.isEmpty else {
                return
            }

            // A failed SwiftData fetch must never be interpreted as an empty task list,
            // otherwise the cleanup could cancel every AlarmKit alarm.
            let tasks = try context.fetch(FetchDescriptor<TodoTask>())
            let referenceDate = Date.now
            let eligibleTaskIDs = Set(
                tasks.compactMap { task -> UUID? in
                    guard task.alarmEnabled,
                          !task.isCompleted,
                          let deadline = task.deadLine,
                          deadline > referenceDate else {
                        return nil
                    }
                    return task.id
                }
            )

            var removedCount = 0

            for alarm in scheduledAlarms {
                guard !eligibleTaskIDs.contains(alarm.id) else {
                    continue
                }

                do {
                    try alarmManager.cancel(id: alarm.id)
                    removedCount += 1
                } catch {
                    AppLogger.notifications.error(
                        "Failed to remove orphaned AlarmKit alarm \(alarm.id.uuidString): \(error.localizedDescription)"
                    )
                }
            }

            AppLogger.notifications.info(
                "🔔 AlarmKit startup orphan cleanup: removed \(removedCount) alarms"
            )

            logScheduledAlarmsCount()

        } catch {
            AppLogger.notifications.error(
                "AlarmKit startup orphan cleanup failed: \(error.localizedDescription)"
            )
        }
    }
    
}
