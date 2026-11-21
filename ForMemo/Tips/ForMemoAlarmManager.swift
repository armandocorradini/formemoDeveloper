import Foundation
import SwiftData
import SwiftUI
import AlarmKit
import ActivityKit
import os


struct ForMemoAlarmMetadata: AlarmMetadata {}

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
                    authorizationState() == .authorized &&
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
                authorizationState() == .authorized &&
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
    
    // Every synchronization entry point uses the same per-task queue.
    // The queued operation reloads the task from a fresh SwiftData context,
    // so a late request carrying an old TodoTask snapshot cannot restore stale data.
    private var synchronizationTasks: [UUID: Task<Bool, Never>] = [:]
    private var synchronizationTokens: [UUID: UUID] = [:]

#if DEBUG
    // One-shot fault injection used only by DebugDiagnosticsView.
    private var debugScheduleFailuresRemaining: [UUID: Int] = [:]
    var debugScheduleFailureObserver: ((UUID, String) -> Void)?

    func debugFailNextSchedule(for id: UUID) {
        debugScheduleFailuresRemaining[id, default: 0] += 1
    }
#endif

    private struct AuthoritativeTaskState {
        let title: String
        let deadline: Date?
        let alarmEnabled: Bool
        let isCompleted: Bool
    }

    @MainActor
    private final class BatchDiagnostics {
        var cancellationSeconds: TimeInterval = 0
        var schedulingSeconds: TimeInterval = 0
        var cancellationCount = 0
        var schedulingCount = 0
    }

    private func fetchAuthoritativeTask(
        id: UUID,
        in container: ModelContainer
    ) throws -> AuthoritativeTaskState? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { candidate in
                candidate.id == id
            }
        )
        guard let task = try context.fetch(descriptor).first else {
            return nil
        }
        return AuthoritativeTaskState(
            title: task.title,
            deadline: task.deadLine,
            alarmEnabled: task.alarmEnabled,
            isCompleted: task.isCompleted
        )
    }

    private func isEligibleForAlarm(_ task: AuthoritativeTaskState) -> Bool {
        authorizationState() == .authorized &&
        task.alarmEnabled &&
        !task.isCompleted &&
        (task.deadline.map { $0 > .now } ?? false)
    }

    private func verifySynchronization(
        taskID: UUID,
        expectedDeadline: Date?
    ) async -> Bool {
        do {
            let alarms = try alarmManager.alarms
            let matchingAlarm = alarms.first { $0.id == taskID }

            // An ineligible task must not retain a scheduled alarm.
            guard let expectedDeadline else {
                guard let matchingAlarm else { return true }
                if case .scheduled = matchingAlarm.state {
                    return false
                }
                return true
            }

            guard let matchingAlarm,
                  case .scheduled = matchingAlarm.state,
                  let schedule = matchingAlarm.schedule,
                  case .fixed(let scheduledDeadline) = schedule else {
                return false
            }

            // AlarmKit stores this ForMemo alarm as a fixed Date. Compare the
            // actual registered date, not merely the existence of a scheduled ID.
            return abs(scheduledDeadline.timeIntervalSince(expectedDeadline)) < 1.0
        } catch {
            AppLogger.notifications.error(
                "AlarmKit task verification failed for task \(taskID.uuidString): \(error.localizedDescription)"
            )
            return false
        }
    }

    private func cancelIfPresent(id: UUID) async {
        do {
            let alarms = try alarmManager.alarms
            let hasAlarmEntry = alarms.contains { $0.id == id }

            guard hasAlarmEntry else {
                AppLogger.notifications.debug(
                    "AlarmKit cancellation skipped for task \(id.uuidString): no AlarmKit entry exists"
                )
                return
            }
        } catch {
            // Preserve the previous cancellation attempt if the preliminary
            // snapshot cannot be read. The caller still verifies the final state.
            AppLogger.notifications.debug(
                "AlarmKit pre-cancellation snapshot failed for task \(id.uuidString): \(error.localizedDescription)"
            )
        }

        do {
            try await cancelAlarmDirect(id: id)
        } catch {
            // The final state verification remains authoritative.
            AppLogger.notifications.debug(
                "AlarmKit cancellation returned for task \(id.uuidString): \(error.localizedDescription)"
            )
        }
    }

    private func cancelAndVerifyNoScheduledAlarm(id: UUID) async -> Bool {
        await cancelIfPresent(id: id)
        return await verifyNoScheduledAlarm(id: id)
    }

    private func verifyNoScheduledAlarm(id: UUID) async -> Bool {
        do {
            let alarms = try alarmManager.alarms
            return !alarms.contains { alarm in
                guard alarm.id == id else { return false }
                if case .scheduled = alarm.state {
                    return true
                }
                return false
            }
        } catch {
            AppLogger.notifications.error(
                "AlarmKit absence verification failed for task \(id.uuidString): \(error.localizedDescription)"
            )
            return false
        }
    }

    private func performSynchronization(
        taskID: UUID,
        in container: ModelContainer
    ) async -> Bool {
        guard authorizationState() == .authorized else {
            let isClear = await cancelAndVerifyNoScheduledAlarm(id: taskID)
            AppLogger.notifications.info(
                "AlarmKit authorization unavailable; cancellation verified for task \(taskID.uuidString): \(isClear)"
            )
            return isClear
        }

        do {
            guard let task = try fetchAuthoritativeTask(id: taskID, in: container) else {
                // A missing record is authoritative: its AlarmKit entry is orphaned.
                return await cancelAndVerifyNoScheduledAlarm(id: taskID)
            }

            guard isEligibleForAlarm(task), task.deadline != nil else {
                return await cancelAndVerifyNoScheduledAlarm(id: taskID)
            }

            // Replace an existing AlarmKit entry only when one is present.
            // A task may have been edited while cancellation was suspended.
            await cancelIfPresent(id: taskID)

            guard let latestTask = try fetchAuthoritativeTask(id: taskID, in: container) else {
                return await cancelAndVerifyNoScheduledAlarm(id: taskID)
            }

            guard isEligibleForAlarm(latestTask),
                  let latestDeadline = latestTask.deadline else {
                return await cancelAndVerifyNoScheduledAlarm(id: taskID)
            }

            try await scheduleAlarmDirect(
                id: taskID,
                date: latestDeadline,
                title: latestTask.title
            )

            // Verify against another fresh read, not the request's snapshot.
            guard let verificationTask = try fetchAuthoritativeTask(id: taskID, in: container) else {
                return await cancelAndVerifyNoScheduledAlarm(id: taskID)
            }

            guard isEligibleForAlarm(verificationTask),
                  let expectedDeadline = verificationTask.deadline else {
                return await cancelAndVerifyNoScheduledAlarm(id: taskID)
            }

            return await verifySynchronization(
                taskID: taskID,
                expectedDeadline: expectedDeadline
            )
        } catch {
            AppLogger.notifications.error(
                "ForMemo AlarmKit synchronization failed for task \(taskID.uuidString): \(error.localizedDescription)"
            )
#if DEBUG
            debugScheduleFailureObserver?(taskID, error.localizedDescription)
#endif
            return false
        }
    }
    

    // Batch synchronization avoids repeating full SwiftData reads and AlarmKit
    // snapshots for every task. Per-ID queue ordering is still preserved.
    private func performBatchSynchronization(
        taskID: UUID,
        initialTask: AuthoritativeTaskState?,
        hasExistingAlarm: Bool,
        diagnostics: BatchDiagnostics,
        in container: ModelContainer
    ) async -> Bool {
        guard authorizationState() == .authorized else {
            guard hasExistingAlarm else { return true }
            let cancellationStart = Date()
            do {
                try await cancelAlarmDirect(id: taskID)
                diagnostics.cancellationCount += 1
            } catch {
                diagnostics.cancellationCount += 1
                AppLogger.notifications.debug(
                    "AlarmKit batch cancellation returned for task \(taskID.uuidString): \(error.localizedDescription)"
                )
            }
            diagnostics.cancellationSeconds += Date().timeIntervalSince(cancellationStart)
            return true
        }

        guard var task = initialTask, isEligibleForAlarm(task),
              task.deadline != nil else {
            guard hasExistingAlarm else { return true }
            let cancellationStart = Date()
            do {
                try await cancelAlarmDirect(id: taskID)
                diagnostics.cancellationCount += 1
            } catch {
                diagnostics.cancellationCount += 1
                AppLogger.notifications.debug(
                    "AlarmKit batch cancellation returned for task \(taskID.uuidString): \(error.localizedDescription)"
                )
            }
            diagnostics.cancellationSeconds += Date().timeIntervalSince(cancellationStart)
            return true
        }

        if hasExistingAlarm {
            let cancellationStart = Date()
            do {
                try await cancelAlarmDirect(id: taskID)
                diagnostics.cancellationCount += 1
            } catch {
                diagnostics.cancellationCount += 1
                // Match the established synchronization behavior: reload the
                // authoritative task after cancellation before scheduling.
                AppLogger.notifications.debug(
                    "AlarmKit batch replacement cancellation returned for task \(taskID.uuidString): \(error.localizedDescription)"
                )
            }
            diagnostics.cancellationSeconds += Date().timeIntervalSince(cancellationStart)

            do {
                guard let latestTask = try fetchAuthoritativeTask(id: taskID, in: container) else {
                    return true
                }
                guard isEligibleForAlarm(latestTask), latestTask.deadline != nil else {
                    return true
                }
                task = latestTask
            } catch {
                AppLogger.notifications.error(
                    "AlarmKit batch authoritative reload failed for task \(taskID.uuidString): \(error.localizedDescription)"
                )
                return false
            }
        }

        guard let deadline = task.deadline else { return true }

        let schedulingStart = Date()
        diagnostics.schedulingCount += 1
        do {
            try await scheduleAlarmDirect(
                id: taskID,
                date: deadline,
                title: task.title
            )
            diagnostics.schedulingSeconds += Date().timeIntervalSince(schedulingStart)
            return true
        } catch {
            diagnostics.schedulingSeconds += Date().timeIntervalSince(schedulingStart)
            AppLogger.notifications.error(
                "ForMemo AlarmKit batch scheduling failed for task \(taskID.uuidString): \(error.localizedDescription)"
            )
            return false
        }
    }

    private func verifyBatchSynchronization(
        taskIDs: [UUID],
        in container: ModelContainer
    ) -> Bool {
        do {
            let context = ModelContext(container)
            let storedTasks = try context.fetch(FetchDescriptor<TodoTask>())
            let requestedIDs = Set(taskIDs)
            var authoritativeTasks: [UUID: AuthoritativeTaskState] = [:]

            for task in storedTasks where requestedIDs.contains(task.id) {
                authoritativeTasks[task.id] = AuthoritativeTaskState(
                    title: task.title,
                    deadline: task.deadLine,
                    alarmEnabled: task.alarmEnabled,
                    isCompleted: task.isCompleted
                )
            }

            let alarms = try alarmManager.alarms
            let alarmsByID = Dictionary(
                alarms.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            var mismatches = 0
            for id in taskIDs {
                let task = authoritativeTasks[id]
                let shouldBeScheduled = task.map(isEligibleForAlarm) ?? false
                let alarm = alarmsByID[id]

                if shouldBeScheduled {
                    guard let expectedDeadline = task?.deadline,
                          let alarm,
                          case .scheduled = alarm.state,
                          let schedule = alarm.schedule,
                          case .fixed(let actualDeadline) = schedule,
                          abs(actualDeadline.timeIntervalSince(expectedDeadline)) < 1.0 else {
                        mismatches += 1
                        continue
                    }
                } else if let alarm, case .scheduled = alarm.state {
                    mismatches += 1
                }
            }

            if mismatches == 0 {
                AppLogger.notifications.info(
                    "✅ AlarmKit batch synchronization verified: \(taskIDs.count) tasks"
                )
                return true
            }

            AppLogger.notifications.error(
                "❌ AlarmKit batch synchronization mismatch: \(mismatches) of \(taskIDs.count) tasks"
            )
            return false
        } catch {
            AppLogger.notifications.error(
                "❌ AlarmKit batch synchronization verification failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    private func enqueueBatchSynchronization(
        taskID: UUID,
        initialTask: AuthoritativeTaskState?,
        hasExistingAlarm: Bool,
        diagnostics: BatchDiagnostics,
        in container: ModelContainer
    ) -> Task<Bool, Never> {
        let previousSynchronization = synchronizationTasks[taskID]
        let token = UUID()
        synchronizationTokens[taskID] = token

        AppLogger.notifications.info(
            "AlarmKit DIAG batch enqueue: task=\(taskID.uuidString), token=\(token.uuidString), predecessor=\(previousSynchronization != nil)"
        )

        let operation = Task { @MainActor in
            if let previousSynchronization {
                AppLogger.notifications.info(
                    "AlarmKit DIAG batch waiting for predecessor: task=\(taskID.uuidString), token=\(token.uuidString)"
                )
                _ = await previousSynchronization.value
                AppLogger.notifications.info(
                    "AlarmKit DIAG batch predecessor finished: task=\(taskID.uuidString), token=\(token.uuidString)"
                )
            }

            // If another operation was already queued for this ID, discard the
            // batch snapshot and use the established fresh-read synchronization.
            let succeeded: Bool
            if previousSynchronization != nil {
                succeeded = await self.performSynchronization(
                    taskID: taskID,
                    in: container
                )
            } else {
                succeeded = await self.performBatchSynchronization(
                    taskID: taskID,
                    initialTask: initialTask,
                    hasExistingAlarm: hasExistingAlarm,
                    diagnostics: diagnostics,
                    in: container
                )
            }

            AppLogger.notifications.info(
                "AlarmKit DIAG batch operation finished: task=\(taskID.uuidString), token=\(token.uuidString), usedFreshSynchronization=\(previousSynchronization != nil), result=\(succeeded)"
            )

            if self.synchronizationTokens[taskID] == token {
                self.synchronizationTasks[taskID] = nil
                self.synchronizationTokens[taskID] = nil
            }

            return succeeded
        }

        synchronizationTasks[taskID] = operation
        return operation
    }

    private func enqueueCancellation(taskID: UUID) -> Task<Bool, Never> {
        let previousSynchronization = synchronizationTasks[taskID]
        let token = UUID()
        synchronizationTokens[taskID] = token

        let operation = Task { @MainActor in
            _ = await previousSynchronization?.value

            let succeeded = await self.cancelAndVerifyNoScheduledAlarm(
                id: taskID
            )

            if self.synchronizationTokens[taskID] == token {
                self.synchronizationTasks[taskID] = nil
                self.synchronizationTokens[taskID] = nil
            }

            return succeeded
        }

        synchronizationTasks[taskID] = operation
        return operation
    }

    
    private func enqueueOrphanCheck(
        taskID: UUID,
        in container: ModelContainer,
        verifyCancellation: Bool = true
    ) -> Task<Bool, Never> {
        let previousSynchronization = synchronizationTasks[taskID]
        let token = UUID()
        synchronizationTokens[taskID] = token

        let operation = Task { @MainActor in
            _ = await previousSynchronization?.value

            let result: Bool
            do {
                if let task = try self.fetchAuthoritativeTask(id: taskID, in: container),
                   self.isEligibleForAlarm(task) {
                    // A current task owns this alarm. Leave its existing schedule
                    // untouched; restoration is handled by the dedicated restore path.
                    result = true
                } else if verifyCancellation {
                    result = await self.cancelAndVerifyNoScheduledAlarm(id: taskID)
                } else {
                    // Batch cleanup verifies the complete AlarmKit state after
                    // the group. Skip cancellation when this ID is already absent.
                    await self.cancelIfPresent(id: taskID)
                    result = true
                }
            } catch {
                AppLogger.notifications.error(
                    "AlarmKit orphan check failed for task \(taskID.uuidString): \(error.localizedDescription)"
                )
                result = false
            }

            if self.synchronizationTokens[taskID] == token {
                self.synchronizationTasks[taskID] = nil
                self.synchronizationTokens[taskID] = nil
            }

            return result
        }

        synchronizationTasks[taskID] = operation
        return operation
    }

    private func enqueueRestoration(
        taskID: UUID,
        in container: ModelContainer
    ) -> Task<Bool, Never> {
        let previousSynchronization = synchronizationTasks[taskID]
        let token = UUID()
        synchronizationTokens[taskID] = token

        let operation = Task { @MainActor in
            _ = await previousSynchronization?.value

            let result: Bool
            do {
                guard let task = try self.fetchAuthoritativeTask(id: taskID, in: container) else {
                    result = await self.cancelAndVerifyNoScheduledAlarm(id: taskID)
                    if self.synchronizationTokens[taskID] == token {
                        self.synchronizationTasks[taskID] = nil
                        self.synchronizationTokens[taskID] = nil
                    }
                    return result
                }

                guard self.isEligibleForAlarm(task), let deadline = task.deadline else {
                    result = await self.cancelAndVerifyNoScheduledAlarm(id: taskID)
                    if self.synchronizationTokens[taskID] == token {
                        self.synchronizationTasks[taskID] = nil
                        self.synchronizationTokens[taskID] = nil
                    }
                    return result
                }

                let existingAlarm = try self.alarmManager.alarms.first { $0.id == taskID }
                if let existingAlarm,
                   case .scheduled = existingAlarm.state,
                   let schedule = existingAlarm.schedule,
                   case .fixed(let existingDeadline) = schedule,
                   abs(existingDeadline.timeIntervalSince(deadline)) < 1.0 {
                    result = true
                } else {
                    result = await self.performSynchronization(taskID: taskID, in: container)
                }
            } catch {
                AppLogger.notifications.error(
                    "AlarmKit restoration failed for task \(taskID.uuidString): \(error.localizedDescription)"
                )
                result = false
            }

            if self.synchronizationTokens[taskID] == token {
                self.synchronizationTasks[taskID] = nil
                self.synchronizationTokens[taskID] = nil
            }

            return result
        }

        synchronizationTasks[taskID] = operation
        return operation
    }

    private func enqueueSchedule(
        id: UUID,
        date: Date,
        title: String
    ) -> Task<Bool, Never> {
        let previousSynchronization = synchronizationTasks[id]
        let token = UUID()
        synchronizationTokens[id] = token

        let operation = Task { @MainActor in
            _ = await previousSynchronization?.value

            let result: Bool
            do {
                try await self.scheduleAlarmDirect(id: id, date: date, title: title)
                result = await self.verifySynchronization(
                    taskID: id,
                    expectedDeadline: date
                )
            } catch {
                AppLogger.notifications.error(
                    "AlarmKit queued scheduling failed for task \(id.uuidString): \(error.localizedDescription)"
                )
                result = false
            }

            if self.synchronizationTokens[id] == token {
                self.synchronizationTasks[id] = nil
                self.synchronizationTokens[id] = nil
            }

            return result
        }

        synchronizationTasks[id] = operation
        return operation
    }

    private func enqueueSynchronization(
        taskID: UUID,
        in container: ModelContainer
    ) -> Task<Bool, Never> {
        let previousSynchronization = synchronizationTasks[taskID]
        let token = UUID()
        synchronizationTokens[taskID] = token

        AppLogger.notifications.info(
            "AlarmKit DIAG individual enqueue: task=\(taskID.uuidString), token=\(token.uuidString), predecessor=\(previousSynchronization != nil)"
        )

        let operation = Task { @MainActor in
            if let previousSynchronization {
                AppLogger.notifications.info(
                    "AlarmKit DIAG individual waiting for predecessor: task=\(taskID.uuidString), token=\(token.uuidString)"
                )
                _ = await previousSynchronization.value
                AppLogger.notifications.info(
                    "AlarmKit DIAG individual predecessor finished: task=\(taskID.uuidString), token=\(token.uuidString)"
                )
            }

            let result = await self.performSynchronization(
                taskID: taskID,
                in: container
            )

            AppLogger.notifications.info(
                "AlarmKit DIAG individual operation finished: task=\(taskID.uuidString), token=\(token.uuidString), result=\(result)"
            )

            if self.synchronizationTokens[taskID] == token {
                self.synchronizationTasks[taskID] = nil
                self.synchronizationTokens[taskID] = nil
            }

            return result
        }

        synchronizationTasks[taskID] = operation
        return operation
    }

    private init() {}

    private enum AlarmSchedulingError: Error {
        case authorizationUnavailable
        case failed
    }

    // MARK: - Authorization

    func requestAuthorization() async throws -> Bool {
        let state = try await alarmManager.requestAuthorization()
        return state == .authorized
    }

    func authorizationState() -> AlarmManager.AuthorizationState {
        alarmManager.authorizationState
    }

    // MARK: - Schedule

    private func scheduleAlarmDirect(
        id: UUID,
        date: Date,
        title: String
    ) async throws {
        guard authorizationState() == .authorized else {
            throw AlarmSchedulingError.authorizationUnavailable
        }

#if DEBUG
        if let remaining = debugScheduleFailuresRemaining[id], remaining > 0 {
            if remaining == 1 {
                debugScheduleFailuresRemaining[id] = nil
            } else {
                debugScheduleFailuresRemaining[id] = remaining - 1
            }
            throw NSError(
                domain: "ForMemo.Debug.AlarmKit",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Injected AlarmKit schedule failure for diagnostic test."]
            )
        }
#endif

        let stopButton = AlarmButton(
            text: "Stop",
            textColor: .white,
            systemImageName: "stop.circle"
        )

//        let snoozeButton = AlarmButton(
//            text: LocalizedStringResource("Alarm.Snooze"),
//            textColor: .white,
//            systemImageName: "zzz"
//        )

        let snoozeButton = AlarmButton(
            text: LocalizedStringResource(
                "Snooze ",
                table: "Localizable",
                bundle: .main
            ),
            textColor: .white,
            systemImageName: "zzz"
        )
        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .countdown
        )

        let countdownPresentation = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: title)
        )

        let attributes = AlarmAttributes<ForMemoAlarmMetadata>(
            presentation: AlarmPresentation(
                alert: alertPresentation,
                countdown: countdownPresentation,
                paused: nil
            ),
            metadata: nil,
            tintColor: Color.orange
        )

        // AlarmKit handles snoozing natively. postAlert is the interval until
        // the alarm rings again after the secondary countdown action.
        let configuration: AlarmManager.AlarmConfiguration<ForMemoAlarmMetadata> = .init(
            countdownDuration: Alarm.CountdownDuration(
                preAlert: nil,
                postAlert: 9 * 60
            ),
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

    /// Public scheduling participates in the same per-task queue as synchronization.
    func scheduleAlarm(
        id: UUID,
        date: Date,
        title: String
    ) async throws {
        guard await enqueueSchedule(id: id, date: date, title: title).value else {
            throw AlarmSchedulingError.failed
        }
    }

    // MARK: - Cancel

    private enum AlarmCancellationError: Error {
        case failed
    }

    private func cancelAlarmDirect(id: UUID) async throws {
        try alarmManager.cancel(id: id)
    }

    /// Public cancellation participates in the same per-task queue as synchronization.
    func cancelAlarm(id: UUID) async throws {
        guard await enqueueCancellation(taskID: id).value else {
            throw AlarmCancellationError.failed
        }
    }

    func cancelAlarmIfNeeded(id: UUID) {
        Task { @MainActor in
            _ = await enqueueCancellation(taskID: id).value
            logScheduledAlarmsCount()
        }
    }

    // MARK: - Synchronize

    func synchronize(task: TodoTask, in context: ModelContext) async -> Bool {
        let operation = enqueueSynchronization(
            taskID: task.id,
            in: context.container
        )
        return await operation.value
    }

    // Compatibility overloads keep diagnostics and older internal call sites
    // source-compatible while still using the task's owning SwiftData container.
    func synchronize(task: TodoTask) async -> Bool {
        guard let context = task.modelContext else {
            AppLogger.notifications.error(
                "Unable to synchronize AlarmKit task \(task.id.uuidString): ModelContext is unavailable"
            )
            return false
        }
        return await synchronize(task: task, in: context)
    }

    func synchronize(tasks: [TodoTask]) async -> Bool {
        guard let context = tasks.first?.modelContext else {
            return tasks.isEmpty
        }
        return await synchronize(tasks: tasks, in: context)
    }

    func synchronize(tasks: [TodoTask], in context: ModelContext) async -> Bool {
        let totalStart = Date()
        let container = context.container

        var seenIDs = Set<UUID>()
        let taskIDs = tasks.map(\.id).filter { seenIDs.insert($0).inserted }
        guard !taskIDs.isEmpty else {
            logScheduledAlarmsCount()
            return true
        }

        // Concurrent work means the initial batch snapshot may be stale. Keep
        // the established serialized path in that exceptional case.
        guard synchronizationTasks.isEmpty else {
            var allSucceeded = true
            for taskID in taskIDs {
                let operation = enqueueSynchronization(taskID: taskID, in: container)
                if !(await operation.value) { allSucceeded = false }
            }
            logScheduledAlarmsCount()
            AppLogger.notifications.info(
                "AlarmKit DIAG batch serialized fallback result: tasks=\(taskIDs.count), allSucceeded=\(allSucceeded), pendingIDs=\(self.synchronizationTasks.keys.map(\.uuidString).sorted())"
            )
            AppLogger.notifications.info(
                "⏱️ AlarmKit batch diagnostics (serialized fallback): tasks=\(taskIDs.count), total=\(Date().timeIntervalSince(totalStart))s"
            )
            return allSucceeded
        }

        do {
            let preparationStart = Date()
            let batchContext = ModelContext(container)
            let storedTasks = try batchContext.fetch(FetchDescriptor<TodoTask>())
            let requestedIDs = Set(taskIDs)
            var statesByID: [UUID: AuthoritativeTaskState] = [:]
            for task in storedTasks where requestedIDs.contains(task.id) {
                statesByID[task.id] = AuthoritativeTaskState(
                    title: task.title,
                    deadline: task.deadLine,
                    alarmEnabled: task.alarmEnabled,
                    isCompleted: task.isCompleted
                )
            }
            let swiftDataPreparationSeconds = Date().timeIntervalSince(preparationStart)

            let alarmSnapshotStart = Date()
            let existingAlarmIDs = Set(try alarmManager.alarms.map(\.id))
            let alarmSnapshotSeconds = Date().timeIntervalSince(alarmSnapshotStart)

            let diagnostics = BatchDiagnostics()
            // Controlled benchmark: reduce concurrent per-ID scheduling to 5.
            // Per-ID serialization remains unchanged; compare elapsed wall time and failures.
            let batchSize = 15
            var allSucceeded = true
            for batchStart in stride(from: 0, to: taskIDs.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, taskIDs.count)
                let operations = taskIDs[batchStart..<batchEnd].map { taskID in
                    enqueueBatchSynchronization(
                        taskID: taskID,
                        initialTask: statesByID[taskID],
                        hasExistingAlarm: existingAlarmIDs.contains(taskID),
                        diagnostics: diagnostics,
                        in: container
                    )
                }
                for operation in operations {
                    if !(await operation.value) { allSucceeded = false }
                }
                await Task.yield()
            }

            let pendingIDsBeforeVerification = synchronizationTasks.keys
                .map(\.uuidString)
                .sorted()
            AppLogger.notifications.info(
                "AlarmKit DIAG batch before final verification: allSucceeded=\(allSucceeded), pendingIDs=\(pendingIDsBeforeVerification)"
            )

            // A newer per-task operation may have been enqueued while the batch
            // was suspended. Drain only operations for IDs owned by this batch
            // before verifying, so the verification observes the final serialized
            // state rather than an intermediate AlarmKit snapshot.
            var pendingOperationsSucceeded = true
            while true {
                let pendingOperations = taskIDs.compactMap { synchronizationTasks[$0] }
                guard !pendingOperations.isEmpty else { break }

                for operation in pendingOperations {
                    if !(await operation.value) {
                        pendingOperationsSucceeded = false
                    }
                }
            }

            // Keep this verification synchronous after the final queue check:
            // no MainActor operation can enqueue between the stable check and
            // the AlarmKit snapshot.
            let verificationStart = Date()
            let verified = verifyBatchSynchronization(taskIDs: taskIDs, in: container)
            let verificationSeconds = Date().timeIntervalSince(verificationStart)

            AppLogger.notifications.info(
                "AlarmKit DIAG batch final result: allSucceeded=\(allSucceeded), verified=\(verified), pendingIDsAfterVerification=\(self.synchronizationTasks.keys.map(\.uuidString).sorted())"
            )

            let totalSeconds = Date().timeIntervalSince(totalStart)
            AppLogger.notifications.info(
                "⏱️ AlarmKit batch diagnostics: tasks=\(taskIDs.count), SwiftData preparation=\(swiftDataPreparationSeconds)s, AlarmKit initial snapshot=\(alarmSnapshotSeconds)s, cancellations=\(diagnostics.cancellationCount) in \(diagnostics.cancellationSeconds)s, schedules=\(diagnostics.schedulingCount) in \(diagnostics.schedulingSeconds)s, final verification=\(verificationSeconds)s, total before final count log=\(totalSeconds)s"
            )

            logScheduledAlarmsCount()
            return allSucceeded && pendingOperationsSucceeded && verified
        } catch {
            AppLogger.notifications.error(
                "AlarmKit batch preparation failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    func waitForPendingSynchronizations() async {
        // A new request may be enqueued while this method is suspended.
        while !synchronizationTasks.isEmpty {
            let pending = Array(synchronizationTasks.values)
            for operation in pending {
                _ = await operation.value
            }
        }
    }

    /// Cancels alarms still registered with AlarmKit while authorization is unavailable.
    /// Saved task settings are not modified.
    private func cancelAllAlarmsWhenUnauthorized() async {
        guard authorizationState() != .authorized else {
            return
        }

        do {
            let alarms = try alarmManager.alarms
            for alarm in alarms {
                _ = await enqueueCancellation(taskID: alarm.id).value
            }
        } catch {
            AppLogger.notifications.error(
                "Unable to inspect AlarmKit alarms while authorization is unavailable: \(error.localizedDescription)"
            )
        }
    }

    /// Restores configured future alarms that are missing or have a stale fixed date.
    /// Correctly scheduled alarms are left untouched.
    func restoreMissingConfiguredAlarms(tasks: [TodoTask]) async {
        guard authorizationState() == .authorized else {
            await cancelAllAlarmsWhenUnauthorized()
            return
        }

        guard let container = tasks.first?.modelContext?.container else {
            // An empty input has nothing to restore. A non-empty input without
            // its SwiftData container cannot be reconciled safely.
            if !tasks.isEmpty {
                AppLogger.notifications.error(
                    "Unable to restore AlarmKit alarms: task ModelContext is unavailable"
                )
            }
            return
        }

        // Reconcile through the authoritative store and the shared per-ID queue.
        // This also repairs an existing alarm whose fixed date is stale.
        var allSucceeded = true
        for task in tasks {
            let operation = enqueueRestoration(taskID: task.id, in: container)
            if !(await operation.value) {
                allSucceeded = false
            }
        }

        AppLogger.notifications.info(
            "AlarmKit configured alarm restoration completed; success: \(allSucceeded)"
        )
        logScheduledAlarmsCount()
    }

    func cancelAlarms(ids: [UUID]) async {
        // Batch cancellations participate in the same per-ID queue as syncs.
        let operations = ids.map { enqueueCancellation(taskID: $0) }
        for operation in operations {
            _ = await operation.value
        }
    }
    
    /// Verifies orphan cleanup with one authoritative SwiftData fetch and one
    /// AlarmKit snapshot. A scheduled alarm is valid only while its task exists
    /// and remains eligible for an alarm.
    private func verifyNoOrphanedScheduledAlarms(
        in container: ModelContainer
    ) -> Bool {
        do {
            let context = ModelContext(container)
            let tasks = try context.fetch(FetchDescriptor<TodoTask>())
            let eligibleTaskIDs = Set(tasks.compactMap { task -> UUID? in
                guard task.alarmEnabled,
                      !task.isCompleted,
                      task.deadLine.map({ $0 > .now }) ?? false else {
                    return nil
                }
                return task.id
            })

            let alarms = try alarmManager.alarms
            let orphanedIDs = alarms.compactMap { alarm -> UUID? in
                guard case .scheduled = alarm.state,
                      !eligibleTaskIDs.contains(alarm.id) else {
                    return nil
                }
                return alarm.id
            }

            guard orphanedIDs.isEmpty else {
                AppLogger.notifications.error(
                    "AlarmKit orphan cleanup verification failed: \(orphanedIDs.count) scheduled orphan alarms remain"
                )
                return false
            }

            AppLogger.notifications.info(
                "AlarmKit orphan cleanup batch verified: \(alarms.count) registered alarms"
            )
            return true
        } catch {
            AppLogger.notifications.error(
                "AlarmKit orphan cleanup batch verification failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    func removeOrphanedAlarms(tasks: [TodoTask]) async {
        guard authorizationState() == .authorized else {
            await cancelAllAlarmsWhenUnauthorized()
            return
        }

        do {
            let alarms = try alarmManager.alarms
            let alarmIDs = alarms.compactMap { alarm -> UUID? in
                if case .scheduled = alarm.state { return alarm.id }
                return nil
            }

            if let container = tasks.first?.modelContext?.container {
                // Keep per-ID serialization, but process a bounded number of
                // orphan checks at a time. Each check reloads its task from the
                // authoritative store; AlarmKit is verified once after all groups.
                let batchSize = 50
                for batchStart in stride(from: 0, to: alarmIDs.count, by: batchSize) {
                    let batchEnd = min(batchStart + batchSize, alarmIDs.count)
                    let operations = alarmIDs[batchStart..<batchEnd].map { id in
                        enqueueOrphanCheck(
                            taskID: id,
                            in: container,
                            verifyCancellation: false
                        )
                    }

                    for operation in operations {
                        _ = await operation.value
                    }
                    await Task.yield()
                }

                guard verifyNoOrphanedScheduledAlarms(in: container) else {
                    AppLogger.notifications.error(
                        "AlarmKit orphan cleanup completed with unresolved scheduled alarms"
                    )
                    return
                }
            } else if tasks.isEmpty {
                // Reset-all path: the caller has already removed every task.
                await cancelAlarms(ids: alarmIDs)
            } else {
                AppLogger.notifications.error(
                    "Unable to clean orphaned alarms: task ModelContext is unavailable"
                )
                return
            }

            AppLogger.notifications.info(
                "AlarmKit orphan cleanup completed for \(alarmIDs.count) registered alarms"
            )
            logScheduledAlarmsCount()
        } catch {
            AppLogger.notifications.error(
                "AlarmKit orphan cleanup failed: \(error.localizedDescription)"
            )
        }
    }

    func removeOrphanedAlarmsAtStartup(context: ModelContext) async {
        guard authorizationState() == .authorized else {
            await cancelAllAlarmsWhenUnauthorized()
            return
        }

        do {
            let alarms = try alarmManager.alarms
            let alarmIDs = alarms.compactMap { alarm -> UUID? in
                if case .scheduled = alarm.state { return alarm.id }
                return nil
            }

            // Do not derive cancellation decisions from a potentially stale
            // task array. Each ID is re-evaluated from the store inside its queue.
            for id in alarmIDs {
                let operation = enqueueOrphanCheck(
                    taskID: id,
                    in: context.container
                )
                _ = await operation.value
            }

            AppLogger.notifications.info(
                "AlarmKit startup reconciliation completed for \(alarmIDs.count) registered alarms"
            )
            logScheduledAlarmsCount()
        } catch {
            AppLogger.notifications.error(
                "AlarmKit startup orphan cleanup failed: \(error.localizedDescription)"
            )
        }
    }

}
