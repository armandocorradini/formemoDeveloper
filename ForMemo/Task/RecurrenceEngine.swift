import Foundation
import SwiftData

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

    static let maximumGeneratedTasks = 2_000

    static let maximumGeneratedFutureOccurrences =
        maximumGeneratedTasks - 1
    
    /// occurrenceDates also includes the current task (#1).
    private static let maximumGeneratedDates =
    maximumGeneratedTasks + 2

    /// Calcola le date delle occorrenze senza creare o modificare TodoTask.
    static func occurrenceDates(
        startDate: Date,
        rule: Rule,
        interval: Int,
        limit: Limit,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Date] {

        let safeInterval = max(1, interval)

        var dates: [Date] = []
        dates.reserveCapacity(
            limitCapacity(for: limit)
        )

        var currentDate = startDate

        while dates.count < maximumGeneratedDates {

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

    /// True only when this completed occurrence is the actual last occurrence
    /// defined by a finite recurrence. Unlimited series and series truncated by
    /// the generation cap are deliberately excluded.
    static func isFinalPlannedOccurrence(
        _ task: TodoTask,
        in context: ModelContext
    ) throws -> Bool {
        guard isFinalDefinedOccurrence(task),
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

        guard occurrences.contains(where: { $0.id == task.id }) else {
            return false
        }

        // Refuse to extend if inconsistent records exist beyond the configured
        // final index. This avoids treating a malformed series as completed.
        return !occurrences.contains { occurrence in
            guard occurrence.id != task.id,
                  let occurrenceIndex = occurrence.occurrenceIndex else {
                return false
            }
            return occurrenceIndex > currentIndex
        }
    }

    private static func isFinalDefinedOccurrence(_ task: TodoTask) -> Bool {
        guard task.isCompleted,
              task.recurrenceRule != nil,
              let occurrenceIndex = task.occurrenceIndex,
              occurrenceIndex > 0,
              occurrenceIndex < maximumGeneratedTasks,
              let rawRule = task.recurrenceRule,
              let rule = Rule(rawValue: rawRule),
              let startDate = task.recurrenceStartDate ?? task.deadLine else {
            return false
        }

        if let count = task.recurrenceCount {
            // recurrenceCount includes occurrence #1.
            return count > 0 && occurrenceIndex == count
        }

        guard let endDate = task.recurrenceEndDate else {
            // An unlimited series has no final occurrence.
            return false
        }

        let dates = occurrenceDates(
            startDate: startDate,
            rule: rule,
            interval: max(1, task.recurrenceInterval),
            limit: .until(endDate)
        )

        // A full result means occurrenceDates hit its safety cap; in that case
        // we cannot prove that the configured end date is the true final date.
        guard dates.count < maximumGeneratedDates else {
            return false
        }

        return dates.count == occurrenceIndex
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
        guard additionalOccurrences > 0,
              isFinalDefinedOccurrence(completedTask),
              let recurrenceID = completedTask.recurrenceID,
              let currentIndex = completedTask.occurrenceIndex,
              let rawRule = completedTask.recurrenceRule,
              let rule = Rule(rawValue: rawRule),
              let startDate = completedTask.recurrenceStartDate ?? completedTask.deadLine else {
            throw ExtensionError.invalidSeries
        }

        guard additionalOccurrences <= maximumGeneratedTasks - currentIndex else {
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

        guard !occurrences.contains(where: { occurrence in
            guard occurrence.id != completedTask.id,
                  let index = occurrence.occurrenceIndex else {
                return false
            }
            return index > currentIndex
        }) else {
            throw ExtensionError.notFinalOccurrence
        }

        let newTotalCount = currentIndex + additionalOccurrences
        let newCount: Int?
        let newEndDate: Date?

        if let existingCount = completedTask.recurrenceCount {
            guard existingCount == currentIndex else {
                throw ExtensionError.notFinalOccurrence
            }
            newCount = existingCount + additionalOccurrences
            newEndDate = completedTask.recurrenceEndDate
        } else if completedTask.recurrenceEndDate != nil {
            let extendedDates = occurrenceDates(
                startDate: startDate,
                rule: rule,
                interval: max(1, completedTask.recurrenceInterval),
                limit: .count(newTotalCount),
                calendar: calendar
            )

            guard extendedDates.count == newTotalCount,
                  let finalDate = extendedDates.last else {
                throw ExtensionError.invalidExtension
            }

            newCount = nil
            newEndDate = finalDate
        } else {
            // Unlimited series are not eligible for this interaction.
            throw ExtensionError.invalidSeries
        }

        // Each occurrence stores a copy of the recurrence definition. Keep these
        // fields synchronized so editing any occurrence later sees the extension.
        for occurrence in occurrences {
            occurrence.recurrenceCount = newCount
            occurrence.recurrenceEndDate = newEndDate
        }

        return try materializeFutureOccurrences(
            for: completedTask,
            in: context,
            calendar: calendar
        )
    }

    static func hasFutureOccurrence(
        for task: TodoTask,
        in context: ModelContext
    ) throws -> Bool {
        guard let recurrenceID = task.recurrenceID,
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

        return try materializeFutureOccurrences(
            for: task,
            in: context,
            calendar: calendar
        )
    }

    // MARK: - Materialization

    /// Crea nel ModelContext tutte le occorrenze successive alla prima.
    ///
    /// Il `task` passato è già l'occorrenza #1 e non viene ricreato.
    /// Vengono generate esclusivamente le occorrenze #2, #3, ...
    ///
    static func materializeFutureOccurrences(
        for task: TodoTask,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
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

        let limit: Limit

        if let recurrenceCount = task.recurrenceCount {
            limit = .count(recurrenceCount)
        } else if let recurrenceEndDate = task.recurrenceEndDate {
            limit = .until(recurrenceEndDate)
        } else {
            limit = .unlimited
        }

        let dates = occurrenceDates(
            startDate: startDate,
            rule: rule,
            interval: max(1, task.recurrenceInterval),
            limit: limit,
            calendar: calendar
        )

        guard dates.count > 1 else {
            return []
        }

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

        for (index, occurrenceDate) in dates.dropFirst().prefix(maximumGeneratedFutureOccurrences).enumerated() {
            let occurrenceIndex = index + 2

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

        return createdTasks
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
        guard !wasCompleted,
              task.isCompleted,
              task.recurrenceRule != nil,
              task.recurrenceID != nil,
              task.occurrenceIndex != nil else {
            return
        }

        NotificationCenter.default.post(
            name: .recurrenceOccurrenceCompleted,
            object: task.id
        )
    }
}
