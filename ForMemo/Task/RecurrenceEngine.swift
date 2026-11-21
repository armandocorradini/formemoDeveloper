import Foundation
import SwiftUI
import SwiftData
import os

/// Shared accelerated stepper for selecting a recurrence occurrence count.
/// A short press changes the value by one; holding a control progressively
/// increases the step size. Releasing always resets the acceleration.
struct AcceleratingStepper: View {
    @Binding var selection: Int
    let range: ClosedRange<Int>

    @State private var activeDirection = 0
    @State private var repeatTask: Task<Void, Never>?

    private var safeRange: ClosedRange<Int> {
        max(1, range.lowerBound)...max(max(1, range.lowerBound), range.upperBound)
    }

    var body: some View {
        HStack(spacing: 6) {
            stepButton(symbol: "minus", direction: -1)

            Text(selection.formatted())
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
                .frame(minWidth: 54)
                .accessibilityLabel(Text("Total occurrences"))
                .accessibilityValue(Text(selection.formatted()))

            stepButton(symbol: "plus", direction: 1)
        }
        .onAppear { clampSelection() }
        .onChange(of: safeRange) { _, _ in clampSelection() }
        .onDisappear { stopRepeating() }
    }

    private func stepButton(symbol: String, direction: Int) -> some View {
        Image(systemName: symbol)
            .font(.headline.weight(.semibold))
            .frame(width: 44, height: 36)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
            .foregroundStyle(isAtLimit(direction) ? .tertiary : .primary)
            .accessibilityLabel(Text(direction < 0 ? "Decrease occurrences" : "Increase occurrences"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { change(by: direction) }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard activeDirection != direction else { return }
                        stopRepeating()
                        activeDirection = direction
                        change(by: direction)

                        repeatTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(400))
                            var heldMilliseconds = 400
                            while !Task.isCancelled && activeDirection == direction {
                                let step: Int
                                switch heldMilliseconds {
                                case ..<900: step = 1
                                case ..<1400: step = 2
                                case ..<1900: step = 5
                                case ..<2400: step = 10
                                case ..<2900: step = 25
                                case ..<3400: step = 50
                                default: step = 100
                                }
                                change(by: direction * step)
                                let delay = heldMilliseconds < 1400 ? 220 : (heldMilliseconds < 2400 ? 160 : 110)
                                try? await Task.sleep(for: .milliseconds(delay))
                                heldMilliseconds += delay
                            }
                        }
                    }
                    .onEnded { _ in stopRepeating() }
            )
    }

    private func isAtLimit(_ direction: Int) -> Bool {
        direction < 0 ? selection <= safeRange.lowerBound : selection >= safeRange.upperBound
    }

    @MainActor
    private func change(by delta: Int) {
        selection = min(max(selection + delta, safeRange.lowerBound), safeRange.upperBound)
    }

    @MainActor
    private func clampSelection() {
        selection = min(max(selection, safeRange.lowerBound), safeRange.upperBound)
    }

    @MainActor
    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
        activeDirection = 0
    }
}

struct RecurrenceEngine {

    enum Rule: String {
        case hourly
        case daily
        case weekly
        case monthly
        case yearly
    }

    enum MigrationError: Error {
        case notLegacyRecurrence
    }

    enum Limit {
        case until(Date)
        case count(Int)
        case unlimited
    }

    /// Maximum number of NEW future occurrences created by one generation
    /// or regeneration operation. The lifetime size of a recurrence series
    /// is not capped by this value.
    static var maximumGeneratedOccurrencesPerOperation: Int {
        RecurrenceGenerationConfiguration.maximumOccurrencesPerOperation
    }

    static var maximumGeneratedFutureOccurrences: Int {
        maximumGeneratedOccurrencesPerOperation
    }

    /// Date calculations include an anchor date and a safety sentinel in
    /// addition to the maximum number of future occurrences for one operation.
    private static var maximumGeneratedDates: Int {
        maximumGeneratedOccurrencesPerOperation + 2
    }

    /// Calcola le date delle occorrenze senza creare o modificare TodoTask.
    static func occurrenceDates(
        startDate: Date,
        rule: Rule,
        interval: Int,
        limit: Limit,
        calendar: Calendar = .autoupdatingCurrent,
        maximumDateCount: Int? = nil
    ) -> [Date] {

        let safeInterval = max(1, interval)
        let dateLimit = max(0, maximumDateCount ?? maximumGeneratedDates)

        var dates: [Date] = []
        dates.reserveCapacity(
            min(limitCapacity(for: limit), dateLimit)
        )

        var currentDate = startDate

        while dates.count < dateLimit {

            switch limit {
            case .until(let endDate):
                let endOfDay = calendar.date(
                    bySettingHour: 23,
                    minute: 59,
                    second: 59,
                    of: endDate
                ) ?? endDate

                guard currentDate <= endOfDay else {
                    return dates
                }

            case .count(let count):
                guard dates.count < max(0, count) else {
                    return dates
                }

            case .unlimited:
                break
            }

            dates.append(currentDate)

            guard let nextDate = nextDate(
                from: currentDate,
                rule: rule,
                interval: safeInterval,
                calendar: calendar
            ) else {
                return dates
            }

            guard nextDate > currentDate else {
                return dates
            }

            currentDate = nextDate
        }

        return dates
    }
    

    enum ExtensionError: Error {
        case invalidSeries
        case notFinalOccurrence
        case maximumReached
        case invalidExtension
    }

    /// Preview information used by the confirmation shown before an extension.
    /// The count is capped at the per-operation maximum; `exceedsOperationLimit`
    /// indicates that additional occurrences remain beyond this first batch.
    struct ExtensionPreview {
        let additionalOccurrences: Int
        let exceedsOperationLimit: Bool
    }

    /// Returns the next scheduled date after the supplied occurrence. This is
    /// used to initialize the end-date picker without changing the series.
    static func nextScheduledOccurrenceDate(
        after task: TodoTask,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard let rawRule = task.recurrenceRule,
              let rule = Rule(rawValue: rawRule),
              let index = task.occurrenceIndex,
              let startDate = task.recurrenceStartDate ?? task.deadLine,
              let scheduledDate = scheduledOccurrenceDate(
                  at: index,
                  startDate: startDate,
                  rule: rule,
                  interval: max(1, task.recurrenceInterval),
                  calendar: calendar
              ) else {
            return nil
        }

        return nextDate(
            from: scheduledDate,
            rule: rule,
            interval: max(1, task.recurrenceInterval),
            calendar: calendar
        )
    }

    /// Counts the requested extension only up to the operation cap plus one
    /// sentinel. It is side-effect free, so the user can confirm or cancel
    /// before any recurrence fields or tasks are changed.
    @MainActor
    static func previewExtension(
        after completedTask: TodoTask,
        until endDate: Date,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> ExtensionPreview {
        guard let anchor = try extensionAnchor(for: completedTask, in: context),
              let rawRule = anchor.recurrenceRule,
              let rule = Rule(rawValue: rawRule),
              let index = anchor.occurrenceIndex,
              let startDate = anchor.recurrenceStartDate ?? anchor.deadLine,
              let scheduledDate = scheduledOccurrenceDate(
                  at: index,
                  startDate: startDate,
                  rule: rule,
                  interval: max(1, anchor.recurrenceInterval),
                  calendar: calendar
              ) else {
            throw ExtensionError.notFinalOccurrence
        }

        let endOfDay = calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: endDate
        ) ?? endDate

        guard let firstAdditionalDate = nextDate(
            from: scheduledDate,
            rule: rule,
            interval: max(1, anchor.recurrenceInterval),
            calendar: calendar
        ), firstAdditionalDate <= endOfDay else {
            throw ExtensionError.invalidExtension
        }

        var count = 0
        var candidateDate = firstAdditionalDate

        while candidateDate <= endOfDay {
            count += 1
            if count > maximumGeneratedFutureOccurrences {
                return ExtensionPreview(
                    additionalOccurrences: maximumGeneratedFutureOccurrences,
                    exceedsOperationLimit: true
                )
            }

            guard let next = nextDate(
                from: candidateDate,
                rule: rule,
                interval: max(1, anchor.recurrenceInterval),
                calendar: calendar
            ), next > candidateDate else {
                throw ExtensionError.invalidExtension
            }

            candidateDate = next
        }

        return ExtensionPreview(
            additionalOccurrences: count,
            exceedsOperationLimit: false
        )
    }

    /// Extends the existing series to an inclusive end date. If the requested
    /// range exceeds the operation cap, this creates only the first batch while
    /// retaining the selected end date on every occurrence. Callers must show
    /// the preview and obtain confirmation before invoking this method.
    @MainActor
    static func extendSeries(
        after completedTask: TodoTask,
        until endDate: Date,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [TodoTask] {
        _ = try previewExtension(
            after: completedTask,
            until: endDate,
            in: context,
            calendar: calendar
        )

        guard let anchor = try extensionAnchor(for: completedTask, in: context),
              let recurrenceID = completedTask.recurrenceID else {
            throw ExtensionError.notFinalOccurrence
        }

        let recurrenceIDValue = recurrenceID
        let occurrences = try context.fetch(
            FetchDescriptor<TodoTask>(
                predicate: #Predicate<TodoTask> { occurrence in
                    occurrence.recurrenceID == recurrenceIDValue
                }
            )
        )

        guard occurrences.contains(where: { $0.id == completedTask.id }) else {
            throw ExtensionError.invalidSeries
        }

        // The extension is appended after the highest materialized index.
        // Later completed occurrences remain part of the history and must not
        // be recreated or cause the new batch to start from an occupied index.
        guard occurrences.contains(where: { $0.id == anchor.id }) else {
            throw ExtensionError.invalidSeries
        }

        // Keep the selected end date even when this operation reaches the configured
        // generation cap, so the requested boundary is not lost.
        for occurrence in occurrences {
            occurrence.recurrenceCount = nil
            occurrence.recurrenceEndDate = endDate
        }

        return try materializeFutureOccurrences(
            for: anchor,
            in: context,
            calendar: calendar
        )
    }

    /// Returns the latest materialized occurrence when the supplied completed
    /// occurrence has no later active occurrence. Later completed occurrences
    /// remain historical, but they still reserve their indexes and dates.
    private static func extensionAnchor(
        for completedTask: TodoTask,
        in context: ModelContext
    ) throws -> TodoTask? {
        guard completedTask.isCompleted,
              completedTask.recurrenceRule != nil,
              let recurrenceID = completedTask.recurrenceID,
              let currentIndex = completedTask.occurrenceIndex,
              currentIndex > 0 else {
            return nil
        }

        let occurrences = try context.fetch(
            FetchDescriptor<TodoTask>(
                predicate: #Predicate<TodoTask> { occurrence in
                    occurrence.recurrenceID == recurrenceID
                }
            )
        )

        guard occurrences.contains(where: { $0.id == completedTask.id }) else {
            return nil
        }

        let hasLaterActiveOccurrence = occurrences.contains { occurrence in
            guard occurrence.id != completedTask.id,
                  !occurrence.isCompleted,
                  let index = occurrence.occurrenceIndex else {
                return false
            }
            return index > currentIndex
        }

        guard !hasLaterActiveOccurrence else {
            return nil
        }

        return occurrences
            .filter { $0.occurrenceIndex != nil }
            .max { lhs, rhs in
                (lhs.occurrenceIndex ?? 0) < (rhs.occurrenceIndex ?? 0)
            }
    }

    /// True when this completed occurrence has no later active occurrence
    /// in its series. The original count or end date does not prevent offering an
    /// extension; further occurrences can be generated in subsequent batches.
    static func isFinalPlannedOccurrence(
        _ task: TodoTask,
        in context: ModelContext
    ) throws -> Bool {
        try extensionAnchor(for: task, in: context) != nil
    }

    /// Resolves the next scheduled date from the actual end of the materialized
    /// series, while still enforcing that no later occurrence is currently active.
    static func nextScheduledOccurrenceDate(
        after task: TodoTask,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard let anchor = try? extensionAnchor(for: task, in: context) else {
            return nil
        }
        return nextScheduledOccurrenceDate(after: anchor, calendar: calendar)
    }

    /// Extends the same recurrence definition without recreating existing tasks.
    /// The completed occurrence and its history remain untouched except for the
    /// shared recurrence boundary fields stored on every occurrence.
    @MainActor
    static func extendSeries(
        after completedTask: TodoTask,
        by additionalOccurrences: Int,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [TodoTask] {
        guard additionalOccurrences > 0 else {
            throw ExtensionError.invalidExtension
        }

        // The cap applies to this extension operation only, not to the total
        // occurrence index or lifetime size of the series.
        guard additionalOccurrences <= maximumGeneratedFutureOccurrences else {
            throw ExtensionError.maximumReached
        }

        guard let anchor = try extensionAnchor(for: completedTask, in: context),
              let recurrenceID = completedTask.recurrenceID,
              let anchorIndex = anchor.occurrenceIndex,
              let rawRule = anchor.recurrenceRule,
              let _ = Rule(rawValue: rawRule),
              let _ = anchor.recurrenceStartDate ?? anchor.deadLine else {
            throw ExtensionError.notFinalOccurrence
        }

        guard anchorIndex <= Int.max - additionalOccurrences else {
            throw ExtensionError.maximumReached
        }

        let recurrenceIDValue = recurrenceID
        let occurrences = try context.fetch(
            FetchDescriptor<TodoTask>(
                predicate: #Predicate<TodoTask> { occurrence in
                    occurrence.recurrenceID == recurrenceIDValue
                }
            )
        )

        guard occurrences.contains(where: { $0.id == completedTask.id }) else {
            throw ExtensionError.invalidSeries
        }

        guard occurrences.contains(where: { $0.id == anchor.id }) else {
            throw ExtensionError.invalidSeries
        }

        // Count new, non-deleted occurrence indexes after the latest existing
        // occurrence, not after the earlier occurrence that triggered the offer.
        // A deleted occurrence
        // keeps its index reserved, so the next valid occurrence must be used.
        var newTotalCount = anchorIndex
        var validAdditionalOccurrences = 0

        while validAdditionalOccurrences < additionalOccurrences {
            let (nextIndex, overflow) = newTotalCount.addingReportingOverflow(1)
            guard !overflow else {
                throw ExtensionError.maximumReached
            }

            // "This and future" deletion permanently blocks the remainder of
            // the series; do not search indefinitely for an available index.
            guard !DeletedFingerprintStore.isDeletedFromOccurrence(
                recurrenceID: recurrenceID,
                occurrenceIndex: nextIndex
            ) else {
                throw ExtensionError.invalidSeries
            }

            newTotalCount = nextIndex
            if !DeletedFingerprintStore.isDeletedOccurrence(
                recurrenceID: recurrenceID,
                occurrenceIndex: nextIndex
            ) {
                validAdditionalOccurrences += 1
            }
        }

        // "Additional occurrences" is an exact-count request regardless of
        // whether the series was originally bounded by a count or an end date.
        // Keeping recurrenceCount non-nil makes materializeFutureOccurrences
        // use the exact-count limit (which takes precedence over the end-of-day
        // semantics of .until). Extension eligibility is based on the last
        // materialized occurrence, not on recurrenceEndDate.
        let newCount: Int? = newTotalCount

        // Each occurrence stores a copy of the recurrence definition. Keep the
        // count synchronized here; materializeFutureOccurrences recalculates
        // and propagates the informational end date for the extended series.
        for occurrence in occurrences {
            occurrence.recurrenceCount = newCount
        }

        return try materializeFutureOccurrences(
            for: anchor,
            in: context,
            calendar: calendar,
            maximumDateCount: newTotalCount - anchorIndex + 1
        )
    }

    static func hasFutureOccurrence(
        for task: TodoTask,
        in context: ModelContext
    ) throws -> Bool {
        guard !task.isCompleted,
              let recurrenceID = task.recurrenceID,
              let currentIndex = task.occurrenceIndex else {
            return false
        }

        let occurrences = try context.fetch(
            FetchDescriptor<TodoTask>(
                predicate: #Predicate<TodoTask> { occurrence in
                    occurrence.recurrenceID == recurrenceID
                }
            )
        )

        return occurrences.contains { occurrence in
            guard occurrence.id != task.id,
                  !occurrence.isCompleted,
                  let occurrenceIndex = occurrence.occurrenceIndex else {
                return false
            }

            return occurrenceIndex > currentIndex
        }
    }
    
    

    // MARK: - Legacy Migration

    /// Migra un task legacy nella nuova struttura delle ricorrenze.
    ///
    /// Il task originale diventa l'occorrenza #1 completata.
    /// `futureCount` indica esclusivamente quante nuove occorrenze creare.
    @MainActor
    static func migrateLegacyRecurrence(
        for task: TodoTask,
        futureCount: Int?,
        endDate: Date?,
        keepCurrentOccurrenceActive: Bool,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [TodoTask] {

        guard task.recurrenceRule != nil,
              task.occurrenceIndex == nil else {
            throw MigrationError.notLegacyRecurrence
        }

        let recurrenceID = UUID()

        task.recurrenceID = recurrenceID
        task.occurrenceIndex = 1
        task.recurrenceStartDate = task.deadLine
        task.recurrenceEndDate = endDate

        if let futureCount {
            task.recurrenceCount = max(0, futureCount) + 1
        } else {
            task.recurrenceCount = nil
        }

        if keepCurrentOccurrenceActive {
            task.isCompleted = false
            task.completedAt = nil
        } else {
            task.isCompleted = true
            task.completedAt = .now
        }

        task.snoozeUntil = nil
        task.manualSnoozeUntil = nil
        
        
        return try materializeFutureOccurrences(
            for: task,
            in: context,
            calendar: calendar
        )
    }

    // MARK: - Materialization

    /// Materializes the occurrences after the supplied task's index.
    ///
    /// The supplied task is the anchor and is never recreated. Each call creates
    /// at most `maximumGeneratedFutureOccurrences` new future occurrences, so a
    /// series can grow beyond the per-operation cap across successive extensions.
    ///
    static func materializeFutureOccurrences(
        for task: TodoTask,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent,
        maximumDateCount: Int? = nil
    ) throws -> [TodoTask] {

        guard let recurrenceRule = task.recurrenceRule,
              let rule = Rule(rawValue: recurrenceRule) else {
            return []
        }

        guard let startDate = task.recurrenceStartDate ?? task.deadLine else {
            return []
        }

        let recurrenceID = task.recurrenceID ?? UUID()

        if task.recurrenceID == nil {
            task.recurrenceID = recurrenceID
        }

        let anchorIndex = max(1, task.occurrenceIndex ?? 1)
        let safeInterval = max(1, task.recurrenceInterval)

        guard let anchorDate = scheduledOccurrenceDate(
            at: anchorIndex,
            startDate: startDate,
            rule: rule,
            interval: safeInterval,
            calendar: calendar
        ) else {
            return []
        }

        let limit: Limit

        if let recurrenceCount = task.recurrenceCount {
            guard recurrenceCount >= anchorIndex else {
                return []
            }
            // The limit is relative to the current anchor occurrence. This
            // lets a later generation append another block after the operation cap.
            limit = .count(recurrenceCount - anchorIndex + 1)
        } else if let recurrenceEndDate = task.recurrenceEndDate {
            limit = .until(recurrenceEndDate)
        } else {
            limit = .unlimited
        }

        let dates = occurrenceDates(
            startDate: anchorDate,
            rule: rule,
            interval: safeInterval,
            limit: limit,
            calendar: calendar,
            maximumDateCount: maximumDateCount
        )

        // Fetch only tasks belonging to this recurrence series.
        // The previous implementation fetched every TodoTask in the store
        // and filtered them in memory. That becomes unnecessarily expensive
        // as the database grows.
        let existingTasks = try context.fetch(
            FetchDescriptor<TodoTask>(
                predicate: #Predicate<TodoTask> { existingTask in
                    existingTask.recurrenceID == recurrenceID
                }
            )
        )

        let existingIndexes: Set<Int> = Set(
            existingTasks.compactMap(\.occurrenceIndex)
        )

        var createdTasks: [TodoTask] = []

        if dates.count <= 1 {
            synchronizeRecurrenceEndDate(
                for: task,
                existingTasks: existingTasks,
                createdTasks: createdTasks,
                startDate: startDate,
                rule: rule,
                interval: safeInterval,
                calendar: calendar
            )
            return []
        }

        for (offset, occurrenceDate) in dates.dropFirst().enumerated() {
            guard createdTasks.count < maximumGeneratedFutureOccurrences else {
                break
            }

            let (occurrenceIndex, overflow) = anchorIndex.addingReportingOverflow(offset + 1)
            guard !overflow else {
                break
            }

            // Evita duplicazioni se il metodo viene richiamato nuovamente.
            guard !existingIndexes.contains(occurrenceIndex) else {
                continue
            }
            
            guard !DeletedFingerprintStore.isDeletedOccurrence(
                recurrenceID: recurrenceID,
                occurrenceIndex: occurrenceIndex
            ) else {
                continue
            }

            let occurrence = TodoTask(
                title: task.title,
                taskDescription: task.taskDescription,
                deadLine: occurrenceDate,
                isCompleted: false,
                completedAt: nil,
                reminderOffsetMinutes: task.reminderOffsetMinutes,
                excludeGlobalNotification: task.excludeGlobalNotification,
                locationName: task.locationName,
                locationLatitude: task.locationLatitude,
                locationLongitude: task.locationLongitude,
                priorityRaw: task.priorityRaw

            )

            occurrence.recurrenceID = recurrenceID
            occurrence.occurrenceIndex = occurrenceIndex

            occurrence.recurrenceRule = task.recurrenceRule
            occurrence.recurrenceInterval = task.recurrenceInterval
            occurrence.recurrenceStartDate = startDate
            occurrence.recurrenceEndDate = task.recurrenceEndDate
            occurrence.recurrenceCount = task.recurrenceCount

            occurrence.mainTagRaw = task.mainTagRaw
            occurrence.alarmEnabled = task.alarmEnabled
            occurrence.locationReminderEnabled = task.locationReminderEnabled
            
            occurrence.snoozeUntil = nil
            occurrence.manualSnoozeUntil = nil

            context.insert(occurrence)
            createdTasks.append(occurrence)
        }

        synchronizeRecurrenceEndDate(
            for: task,
            existingTasks: existingTasks,
            createdTasks: createdTasks,
            startDate: startDate,
            rule: rule,
            interval: safeInterval,
            calendar: calendar
        )

        return createdTasks
    }

    /// Recalculates the stored boundary after an occurrence has been deleted
    /// and its deletion fingerprint has been committed.
    ///
    /// This is intentionally limited to count-based recurrences. Date-based
    /// recurrence boundaries retain their existing deletion behavior.
    @MainActor
    static func synchronizeCountBasedEndDateAfterDeletion(
        recurrenceID: UUID,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        let remainingTasks = try context.fetch(
            FetchDescriptor<TodoTask>(
                predicate: #Predicate<TodoTask> { candidate in
                    candidate.recurrenceID == recurrenceID
                }
            )
        )

        guard let anchorTask = remainingTasks.first,
              anchorTask.recurrenceCount != nil,
              let rawRule = anchorTask.recurrenceRule,
              let rule = Rule(rawValue: rawRule),
              let startDate = anchorTask.recurrenceStartDate ?? anchorTask.deadLine else {
            return
        }

        synchronizeRecurrenceEndDate(
            for: anchorTask,
            existingTasks: remainingTasks,
            createdTasks: [],
            startDate: startDate,
            rule: rule,
            interval: max(1, anchorTask.recurrenceInterval),
            calendar: calendar
        )

        try context.save()
    }

    /// Keeps the recurrence boundary synchronized on every occurrence.
    /// Count-based series store the date of the last valid scheduled occurrence;
    /// deleted indexes only move that date backwards when they form a deleted tail.
    private static func synchronizeRecurrenceEndDate(
        for task: TodoTask,
        existingTasks: [TodoTask],
        createdTasks: [TodoTask],
        startDate: Date,
        rule: Rule,
        interval: Int,
        calendar: Calendar
    ) {
        let seriesTasks = existingTasks + createdTasks + [task]

        if let requestedCount = task.recurrenceCount {
            let recurrenceID = task.recurrenceID
            let existingByIndex = Dictionary(
                seriesTasks.compactMap { occurrence -> (Int, TodoTask)? in
                    guard let index = occurrence.occurrenceIndex else { return nil }
                    return (index, occurrence)
                },
                uniquingKeysWith: { first, _ in first }
            )

            var lastValidIndex = requestedCount

            while lastValidIndex > 0 {
                // A materialized occurrence is valid even if a stale deletion
                // fingerprint for the same index is still present.
                if existingByIndex[lastValidIndex] != nil {
                    break
                }

                guard let recurrenceID,
                      DeletedFingerprintStore.isDeletedOccurrence(
                        recurrenceID: recurrenceID,
                        occurrenceIndex: lastValidIndex
                      ) || DeletedFingerprintStore.isDeletedFromOccurrence(
                        recurrenceID: recurrenceID,
                        occurrenceIndex: lastValidIndex
                      ) else {
                    break
                }

                lastValidIndex -= 1
            }

            let effectiveEndDate = existingByIndex[lastValidIndex]?.deadLine
                ?? scheduledOccurrenceDate(
                    at: lastValidIndex,
                    startDate: startDate,
                    rule: rule,
                    interval: interval,
                    calendar: calendar
                )

            guard let effectiveEndDate else { return }

            for occurrence in seriesTasks {
                occurrence.recurrenceEndDate = effectiveEndDate
            }
            return
        }

        // Date-based series retain their existing behavior: the boundary is
        // the latest deadline that has actually been materialized.
        guard task.recurrenceEndDate != nil,
              let effectiveEndDate = seriesTasks.compactMap(\.deadLine).max() else {
            return
        }

        for occurrence in seriesTasks {
            occurrence.recurrenceEndDate = effectiveEndDate
        }
    }
    
    /// Calculates the canonical date for a 1-based occurrence index while
    /// preserving the engine's iterative calendar semantics (important for
    /// monthly and yearly recurrences near the end of a month).
    private static func scheduledOccurrenceDate(
        at occurrenceIndex: Int,
        startDate: Date,
        rule: Rule,
        interval: Int,
        calendar: Calendar
    ) -> Date? {
        guard occurrenceIndex >= 1 else {
            return nil
        }

        var date = startDate
        var index = 1
        let safeInterval = max(1, interval)

        while index < occurrenceIndex {
            guard let next = nextDate(
                from: date,
                rule: rule,
                interval: safeInterval,
                calendar: calendar
            ), next > date else {
                return nil
            }

            date = next
            index += 1
        }

        return date
    }

    private static func nextDate(
        from date: Date,
        rule: Rule,
        interval: Int,
        calendar: Calendar
    ) -> Date? {

        switch rule {
        case .hourly:
            return calendar.date(
                byAdding: .hour,
                value: interval,
                to: date
            )

        case .daily:
            return calendar.date(
                byAdding: .day,
                value: interval,
                to: date
            )

        case .weekly:
            return calendar.date(
                byAdding: .weekOfYear,
                value: interval,
                to: date
            )

        case .monthly:
            return calendar.date(
                byAdding: .month,
                value: interval,
                to: date
            )

        case .yearly:
            return calendar.date(
                byAdding: .year,
                value: interval,
                to: date
            )
        }
    }

    private static func limitCapacity(for limit: Limit) -> Int {
        switch limit {
        case .count(let count):
            return min(max(0, count), maximumGeneratedDates)

        case .until:
            return maximumGeneratedDates

        case .unlimited:
            return maximumGeneratedDates
        }
    }
}




extension Notification.Name {
    static let recurrenceOccurrenceCompleted =
        Notification.Name("recurrenceOccurrenceCompleted")
}

enum RecurrenceCompletionNotice {
    @MainActor
    static func postIfNeeded(for task: TodoTask, wasCompleted: Bool) {
        let taskID = task.id
        let hasRecurrenceRule = task.recurrenceRule != nil
        let hasRecurrenceID = task.recurrenceID != nil
        let occurrenceIndex = task.occurrenceIndex

        guard !wasCompleted,
              task.isCompleted,
              hasRecurrenceRule,
              hasRecurrenceID,
              occurrenceIndex != nil else {
            AppLogger.persistence.debug(
                "[RecurrenceExtension] Signal skipped task=\(taskID.uuidString, privacy: .public) wasCompleted=\(wasCompleted) isCompleted=\(task.isCompleted) hasRule=\(hasRecurrenceRule) hasRecurrenceID=\(hasRecurrenceID) occurrenceIndex=\(occurrenceIndex ?? -1)"
            )
            return
        }

        AppLogger.persistence.debug(
            "[RecurrenceExtension] Posting completion signal task=\(taskID.uuidString, privacy: .public) occurrenceIndex=\(occurrenceIndex ?? -1)"
        )
        NotificationCenter.default.post(
            name: .recurrenceOccurrenceCompleted,
            object: taskID
        )
    }
}
