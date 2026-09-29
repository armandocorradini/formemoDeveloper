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

        task.isCompleted = true
        task.completedAt = .now
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


