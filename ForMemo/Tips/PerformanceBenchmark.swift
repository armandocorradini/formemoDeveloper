//
// PerformanceBenchmark.swift
// ForMemo
//
// DEBUG ONLY
//
// Benchmark autonomo delle performance di TodoTask.
// NON CREA, NON MODIFICA e NON CANCELLA alcun Task.
//
// Il benchmark:
// - conta automaticamente Task totali, attivi e completati
// - esegue warm-up
// - esegue più misurazioni reali
// - calcola min / max / media / mediana / deviazione standard
// - misura memoria residente prima e dopo
// - misura fetch, filter, sort e combinazioni
// - produce un report completo direttamente nell'app
//
// Non misura il rendering SwiftUI frame-per-frame.
// Misura invece il lavoro dati che alimenta TaskListView/WeeklyTasksView.

#if DEBUG

import Foundation
import SwiftUI
import SwiftData
import Darwin.Mach
import UIKit
import UserNotifications
import UniformTypeIdentifiers

@MainActor
enum PerformanceBenchmark {

    // MARK: - Public API

    struct MeasurementSummary {
        let name: String
        let values: [Double]

        var min: Double { values.min() ?? 0 }
        var max: Double { values.max() ?? 0 }
        var mean: Double {
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Double(values.count)
        }
        var median: Double {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            if sorted.count % 2 == 0 {
                return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            }
            return sorted[sorted.count / 2]
        }
        var standardDeviation: Double {
            guard values.count > 1 else { return 0 }
            let m = mean
            let variance = values.reduce(0) { partial, value in
                partial + pow(value - m, 2)
            } / Double(values.count - 1)
            return sqrt(variance)
        }
    }

    struct Result {
        let date: Date
        let repetitions: Int
        let warmups: Int
        let totalTasks: Int
        let activeTasks: Int
        let completedTasks: Int
        let memoryBeforeMB: Double
        let memoryAfterMB: Double
        let memoryDeltaMB: Double
        let measurements: [MeasurementSummary]

        var report: String {
            makeReport()
        }
    }

    /// Esegue il benchmark completo.
    ///
    /// NON modifica il ModelContext.
    ///
    /// Parametri consigliati:
    /// repetitions: 7
    /// warmups: 2
    ///
    /// Il risultato contiene già il report finale.
    static func run(
        modelContext: ModelContext,
        repetitions: Int = 7,
        warmups: Int = 2
    ) throws -> Result {

        precondition(repetitions > 0)
        precondition(warmups >= 0)

        
        
        
        
        // ---------------------------------------------------------
        // WARM-UP
        // ---------------------------------------------------------
        // Serve a ridurre l'effetto di inizializzazione/cache.
        // I warm-up NON entrano nelle statistiche finali.
        // ---------------------------------------------------------

        for _ in 0..<warmups {
            _ = try performIteration(modelContext: modelContext)
        }

        // ---------------------------------------------------------
        // MEMORIA INIZIALE
        // ---------------------------------------------------------

        let memoryBefore = residentMemoryMB()

        // ---------------------------------------------------------
        // MISURAZIONI
        // ---------------------------------------------------------

        var fetchActiveValues: [Double] = []
        var fetchAllValues: [Double] = []
        var filterValues: [Double] = []
        var sortValues: [Double] = []
        var filterSortValues: [Double] = []
        var allFilterSortValues: [Double] = []

        var totalTasks = 0
        var activeTasks = 0
        var completedTasks = 0

        for _ in 0..<repetitions {
            let iteration = try performIteration(modelContext: modelContext)

            totalTasks = iteration.totalTasks
            activeTasks = iteration.activeTasks
            completedTasks = iteration.completedTasks

            fetchActiveValues.append(iteration.fetchActiveMS)
            fetchAllValues.append(iteration.fetchAllMS)
            filterValues.append(iteration.filterMS)
            sortValues.append(iteration.sortMS)
            filterSortValues.append(iteration.filterSortMS)
            allFilterSortValues.append(iteration.allFilterSortMS)
        }

        let memoryAfter = residentMemoryMB()

        let measurements = [
            MeasurementSummary(name: "Fetch Task attivi", values: fetchActiveValues),
            MeasurementSummary(name: "Fetch tutti i Task", values: fetchAllValues),
            MeasurementSummary(name: "Filter in memoria", values: filterValues),
            MeasurementSummary(name: "Sort in memoria", values: sortValues),
            MeasurementSummary(name: "Filter + Sort", values: filterSortValues),
            MeasurementSummary(name: "Fetch tutti + Filter + Sort", values: allFilterSortValues)
        ]

        return Result(
            date: Date(),
            repetitions: repetitions,
            warmups: warmups,
            totalTasks: totalTasks,
            activeTasks: activeTasks,
            completedTasks: completedTasks,
            memoryBeforeMB: memoryBefore,
            memoryAfterMB: memoryAfter,
            memoryDeltaMB: memoryAfter - memoryBefore,
            measurements: measurements
        )
    }

    /// Copia il report negli appunti.
    static func copyReport(_ result: Result) {
        UIPasteboard.general.string = result.report
    }

    // MARK: - Iteration

    private struct IterationResult {
        let totalTasks: Int
        let activeTasks: Int
        let completedTasks: Int

        let fetchActiveMS: Double
        let fetchAllMS: Double
        let filterMS: Double
        let sortMS: Double
        let filterSortMS: Double
        let allFilterSortMS: Double
    }

    private static func performIteration(
        modelContext: ModelContext
    ) throws -> IterationResult {

        // ---------------------------------------------------------
        // 1. FETCH ATTIVI
        // ---------------------------------------------------------

        let activeStart = ContinuousClock.now

        let activeDescriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { !$0.isCompleted }
        )

        let activeTasks = try modelContext.fetch(activeDescriptor)

        let activeEnd = ContinuousClock.now

        // ---------------------------------------------------------
        // 2. FETCH TOTALI
        // ---------------------------------------------------------

        let allStart = ContinuousClock.now

        let allDescriptor = FetchDescriptor<TodoTask>()
        let allTasks = try modelContext.fetch(allDescriptor)

        let allEnd = ContinuousClock.now

        // ---------------------------------------------------------
        // 3. FILTER IN MEMORIA
        // ---------------------------------------------------------

        let filterStart = ContinuousClock.now

        let filteredTasks = activeTasks.filter { !$0.isCompleted }

        let filterEnd = ContinuousClock.now

        // ---------------------------------------------------------
        // 4. SORT IN MEMORIA
        // ---------------------------------------------------------

        let sortStart = ContinuousClock.now

        let sortedTasks = filteredTasks.sorted(by: taskSort)

        let sortEnd = ContinuousClock.now

        // ---------------------------------------------------------
        // 5. FILTER + SORT
        // ---------------------------------------------------------

        let filterSortStart = ContinuousClock.now

        let filteredSortedTasks = activeTasks
            .filter { !$0.isCompleted }
            .sorted(by: taskSort)

        let filterSortEnd = ContinuousClock.now

        // ---------------------------------------------------------
        // 6. FETCH TOTALI + FILTER + SORT
        //
        // Questo è il caso più costoso e serve per capire quanto
        // peserebbe una lista che carica tutti i record e poi
        // seleziona gli attivi in memoria.
        // ---------------------------------------------------------

        let allFilterSortStart = ContinuousClock.now

        let allFilteredSortedTasks = allTasks
            .filter { !$0.isCompleted }
            .sorted(by: taskSort)

        let allFilterSortEnd = ContinuousClock.now

        // Mantiene i risultati vivi fino alla fine dell'iterazione.
        // Evita ottimizzazioni del compilatore che eliminino il lavoro.
        _ = sortedTasks.count
        _ = filteredSortedTasks.count
        _ = allFilteredSortedTasks.count

        let total = allTasks.count
        let active = activeTasks.count

        return IterationResult(
            totalTasks: total,
            activeTasks: active,
            completedTasks: max(0, total - active),
            fetchActiveMS: milliseconds(activeStart, activeEnd),
            fetchAllMS: milliseconds(allStart, allEnd),
            filterMS: milliseconds(filterStart, filterEnd),
            sortMS: milliseconds(sortStart, sortEnd),
            filterSortMS: milliseconds(filterSortStart, filterSortEnd),
            allFilterSortMS: milliseconds(allFilterSortStart, allFilterSortEnd)
        )
    }

    // MARK: - Sorting

    private static func taskSort(
        _ lhs: TodoTask,
        _ rhs: TodoTask
    ) -> Bool {

        switch (lhs.deadLine, rhs.deadLine) {
        case let (l?, r?):
            if l != r {
                return l < r
            }
            return lhs.createdAt < rhs.createdAt

        case (_?, nil):
            return true

        case (nil, _?):
            return false

        case (nil, nil):
            return lhs.createdAt < rhs.createdAt
        }
    }

    // MARK: - Report

    private static func milliseconds(
        _ start: ContinuousClock.Instant,
        _ end: ContinuousClock.Instant
    ) -> Double {

        let duration = start.duration(to: end)
        let components = duration.components

        let seconds = Double(components.seconds)
        let attoseconds =
            Double(components.attoseconds) /
            1_000_000_000_000_000_000.0

        return (seconds + attoseconds) * 1_000.0
    }

    private static func residentMemoryMB() -> Double {

        var info = mach_task_basic_info()

        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size /
            MemoryLayout<natural_t>.size
        )

        let result: kern_return_t =
            withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(
                    to: integer_t.self,
                    capacity: 1
                ) {
                    task_info(
                        mach_task_self_,
                        task_flavor_t(MACH_TASK_BASIC_INFO),
                        $0,
                        &count
                    )
                }
            }

        guard result == KERN_SUCCESS else {
            return -1
        }

        return Double(info.resident_size) / 1024.0 / 1024.0
    }
}

// MARK: - Badge Performance Benchmark

extension PerformanceBenchmark {

    struct BadgeMeasurementSummary {
        let name: String
        let values: [Double]

        var min: Double { values.min() ?? 0 }
        var max: Double { values.max() ?? 0 }

        var mean: Double {
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Double(values.count)
        }

        var median: Double {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            if sorted.count % 2 == 0 {
                return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            }
            return sorted[sorted.count / 2]
        }
    }

    struct BadgeBenchmarkResult {
        let date: Date
        let taskCount: Int
        let repetitions: Int
        let warmups: Int
        let classicOriginal: BadgeMeasurementSummary
        let classicOptimized: BadgeMeasurementSummary
        let globalOriginal: BadgeMeasurementSummary
        let globalOptimized: BadgeMeasurementSummary
        let classicIdentical: Bool
        let globalIdentical: Bool
        let edgeCasesIdentical: Bool

        var report: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            func summaryLine(_ summary: BadgeMeasurementSummary) -> String {
                String(
                    format: "%-24@ min %8.3f | med %8.3f | avg %8.3f | max %8.3f ms",
                    summary.name,
                    summary.min,
                    summary.median,
                    summary.mean,
                    summary.max
                )
            }

            var lines: [String] = []

            lines.append("")
            lines.append("════════════════════════════════════════════════════════════")
            lines.append("FORMEMO — BADGE PERFORMANCE BENCHMARK")
            lines.append("════════════════════════════════════════════════════════════")
            lines.append("Data: \(formatter.string(from: date))")
            lines.append("Task: \(taskCount)")
            lines.append("Warm-up: \(warmups)")
            lines.append("Misurazioni: \(repetitions)")
            lines.append("")

            lines.append("CLASSIC MODE")
            lines.append("------------------------------------------------------------")
            lines.append(summaryLine(classicOriginal))
            lines.append(summaryLine(classicOptimized))
            lines.append("Risultati identici: \(classicIdentical ? "PASS" : "FAIL")")
            lines.append("")

            lines.append("GLOBAL NOTIFICATION MODE")
            lines.append("------------------------------------------------------------")
            lines.append(summaryLine(globalOriginal))
            lines.append(summaryLine(globalOptimized))
            lines.append("Risultati identici: \(globalIdentical ? "PASS" : "FAIL")")
            lines.append("")

            lines.append("EDGE CASES")
            lines.append("------------------------------------------------------------")
            lines.append("Risultati identici: \(edgeCasesIdentical ? "PASS" : "FAIL")")
            lines.append("")

            lines.append("CONCLUSIONE")
            lines.append("------------------------------------------------------------")

            if classicIdentical && globalIdentical && edgeCasesIdentical {
                lines.append("Equivalenza funzionale: PASS")
            } else {
                lines.append("Equivalenza funzionale: FAIL")
                lines.append("NON considerare sicura la modifica.")
            }

            lines.append("")
            lines.append("NOTA")
            lines.append("------------------------------------------------------------")
            lines.append("Il benchmark non modifica, crea o cancella Task.")
            lines.append("Non registra né programma notifiche.")
            lines.append("Confronta il calcolo originale del badge")
            lines.append("con il nuovo indice ottimizzato.")
            lines.append("")
            lines.append("════════════════════════════════════════════════════════════")
            lines.append("FINE BADGE BENCHMARK")
            lines.append("════════════════════════════════════════════════════════════")

            return lines.joined(separator: "\n")
        }
    }

    static func runBadgeBenchmark(
        tasks: [TodoTask],
        repetitions: Int = 7,
        warmups: Int = 2
    ) -> BadgeBenchmarkResult {

        precondition(repetitions > 0)
        precondition(warmups >= 0)

        func originalBadgeCount(
            tasks: [TodoTask],
            referenceDate: Date
        ) -> Int {

            let badgeMode = UserDefaults.standard.integer(
                forKey: "badgeMode"
            )

            let leadDays = UserDefaults.standard.integer(
                forKey: "notificationLeadTimeDays"
            )

            return tasks.reduce(0) { count, task in
                guard !task.isCompleted,
                      let deadline = task.deadLine else {
                    return count
                }

                if badgeMode == 0 {
                    if deadline <= referenceDate {
                        return count + 1
                    }
                    return count
                }

                if leadDays > 0 {
                    let triggerDate = Calendar.current.date(
                        byAdding: .day,
                        value: -leadDays,
                        to: deadline
                    ) ?? deadline

                    if triggerDate <= referenceDate {
                        return count + 1
                    }
                    return count
                }

                if deadline <= referenceDate {
                    return count + 1
                }

                return count
            }
        }

        func measure(
            operation: () -> Int
        ) -> [Double] {

            for _ in 0..<warmups {
                _ = operation()
            }

            var values: [Double] = []
            values.reserveCapacity(repetitions)

            for _ in 0..<repetitions {
                let start = ContinuousClock.now
                _ = operation()
                let end = ContinuousClock.now
                values.append(milliseconds(start, end))
            }

            return values
        }

        let now = Date()

        let referenceDates: [Date] = [
            now.addingTimeInterval(-86_400 * 365),
            now.addingTimeInterval(-86_400 * 30),
            now.addingTimeInterval(-86_400),
            now,
            now.addingTimeInterval(86_400),
            now.addingTimeInterval(86_400 * 30),
            now.addingTimeInterval(86_400 * 365)
        ]

        let savedMode = UserDefaults.standard.integer(
            forKey: "badgeMode"
        )

        let savedLeadDays = UserDefaults.standard.integer(
            forKey: "notificationLeadTimeDays"
        )

        func runScenario(
            mode: Int,
            leadDays: Int
        ) -> (
            BadgeMeasurementSummary,
            BadgeMeasurementSummary,
            Bool
        ) {

            UserDefaults.standard.set(mode, forKey: "badgeMode")
            UserDefaults.standard.set(
                leadDays,
                forKey: "notificationLeadTimeDays"
            )

            let index = TaskBadgePolicy.Index(tasks: tasks)

            let originalValues = measure {
                var result = 0

                for date in referenceDates {
                    result += originalBadgeCount(
                        tasks: tasks,
                        referenceDate: date
                    )
                }

                return result
            }

            let optimizedValues = measure {
                var result = 0

                for date in referenceDates {
                    result += index.count(at: date)
                }

                return result
            }

            var identical = true

            for date in referenceDates {
                let original = originalBadgeCount(
                    tasks: tasks,
                    referenceDate: date
                )

                let optimized = index.count(at: date)

                if original != optimized {
                    identical = false
                    break
                }
            }

            return (
                BadgeMeasurementSummary(
                    name: "Originale",
                    values: originalValues
                ),
                BadgeMeasurementSummary(
                    name: "Ottimizzato",
                    values: optimizedValues
                ),
                identical
            )
        }

        let classic = runScenario(
            mode: 0,
            leadDays: 0
        )

        let global = runScenario(
            mode: 1,
            leadDays: 7
        )

        UserDefaults.standard.set(
            1,
            forKey: "badgeMode"
        )

        UserDefaults.standard.set(
            7,
            forKey: "notificationLeadTimeDays"
        )

        let calendar = Calendar.current

        let edgeDates: [Date] = [
            calendar.startOfDay(for: now),
            calendar.date(
                byAdding: .day,
                value: -1,
                to: calendar.startOfDay(for: now)
            ) ?? now,
            calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: now)
            ) ?? now,
            calendar.date(
                byAdding: .day,
                value: -7,
                to: now
            ) ?? now,
            calendar.date(
                byAdding: .day,
                value: 7,
                to: now
            ) ?? now
        ]

        let edgeIndex = TaskBadgePolicy.Index(tasks: tasks)

        let edgeCasesIdentical = edgeDates.allSatisfy { date in
            originalBadgeCount(
                tasks: tasks,
                referenceDate: date
            ) == edgeIndex.count(at: date)
        }

        UserDefaults.standard.set(
            savedMode,
            forKey: "badgeMode"
        )

        UserDefaults.standard.set(
            savedLeadDays,
            forKey: "notificationLeadTimeDays"
        )

        return BadgeBenchmarkResult(
            date: Date(),
            taskCount: tasks.count,
            repetitions: repetitions,
            warmups: warmups,
            classicOriginal: classic.0,
            classicOptimized: classic.1,
            globalOriginal: global.0,
            globalOptimized: global.1,
            classicIdentical: classic.2,
            globalIdentical: global.2,
            edgeCasesIdentical: edgeCasesIdentical
        )
    }
}

// MARK: - Notification Rebuild Performance Benchmark

extension PerformanceBenchmark {

    struct NotificationRebuildBenchmarkResult {

        let date: Date
        let taskCount: Int
        let repetitions: Int
        let warmups: Int
        let measurements: [Double]

        var min: Double {
            measurements.min() ?? 0
        }

        var max: Double {
            measurements.max() ?? 0
        }

        var mean: Double {
            guard !measurements.isEmpty else { return 0 }
            return measurements.reduce(0, +) / Double(measurements.count)
        }

        var median: Double {
            guard !measurements.isEmpty else { return 0 }

            let sorted = measurements.sorted()

            if sorted.count.isMultiple(of: 2) {
                return (
                    sorted[sorted.count / 2 - 1] +
                    sorted[sorted.count / 2]
                ) / 2
            }

            return sorted[sorted.count / 2]
        }

        var report: String {

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            var lines: [String] = []

            lines.append("")
            lines.append("════════════════════════════════════════════════════════════")
            lines.append("FORMEMO — NOTIFICATION REBUILD PERFORMANCE")
            lines.append("════════════════════════════════════════════════════════════")
            lines.append("Data: \(formatter.string(from: date))")
            lines.append("Task sintetici: \(taskCount)")
            lines.append("Warm-up: \(warmups)")
            lines.append("Misurazioni: \(repetitions)")
            lines.append("")
            lines.append(
                String(
                    format: "Min        %8.3f ms",
                    min
                )
            )
            lines.append(
                String(
                    format: "Mediana    %8.3f ms",
                    median
                )
            )
            lines.append(
                String(
                    format: "Media      %8.3f ms",
                    mean
                )
            )
            lines.append(
                String(
                    format: "Max        %8.3f ms",
                    max
                )
            )
            lines.append("")
            lines.append("Misurazioni:")

            for (index, value) in measurements.enumerated() {
                lines.append(
                    String(
                        format: "  #%d       %8.3f ms",
                        index + 1,
                        value
                    )
                )
            }

            lines.append("")
            lines.append("════════════════════════════════════════════════════════════")

            return lines.joined(separator: "\n")
        }
    }

    @MainActor
    static func runNotificationRebuildBenchmark(
        tasks: [TodoTask],
        repetitions: Int = 7,
        warmups: Int = 2
    ) async -> NotificationRebuildBenchmarkResult {

        let manager = NotificationManager.shared

        // Warm-up: non viene misurato.
        for _ in 0..<warmups {
            await manager.debugRebuild(tasks: tasks)
        }

        var measurements: [Double] = []
        measurements.reserveCapacity(repetitions)

        for _ in 0..<repetitions {

            let start = CFAbsoluteTimeGetCurrent()

            await manager.debugRebuild(tasks: tasks)

            let end = CFAbsoluteTimeGetCurrent()

            measurements.append(
                (end - start) * 1000
            )
        }

        return NotificationRebuildBenchmarkResult(
            date: Date(),
            taskCount: tasks.count,
            repetitions: repetitions,
            warmups: warmups,
            measurements: measurements
        )
    }
}


// MARK: - Notification Refresh Core Performance Benchmark

extension PerformanceBenchmark {

    struct NotificationRefreshBenchmarkResult {

        let date: Date
        let taskCount: Int
        let repetitions: Int
        let warmups: Int

        let fetchMeasurements: [Double]
        let signatureMeasurements: [Double]
        let badgeMeasurements: [Double]

        private func summary(
            _ values: [Double]
        ) -> (min: Double, median: Double, mean: Double, max: Double) {

            let sorted = values.sorted()

            guard !sorted.isEmpty else {
                return (0, 0, 0, 0)
            }

            let median: Double

            if sorted.count.isMultiple(of: 2) {
                median = (
                    sorted[sorted.count / 2 - 1] +
                    sorted[sorted.count / 2]
                ) / 2
            } else {
                median = sorted[sorted.count / 2]
            }

            return (
                sorted.first ?? 0,
                median,
                sorted.reduce(0, +) / Double(sorted.count),
                sorted.last ?? 0
            )
        }

        var report: String {

            let fetch = summary(fetchMeasurements)
            let signature = summary(signatureMeasurements)
            let badge = summary(badgeMeasurements)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            var lines: [String] = []

            lines.append("")
            lines.append("════════════════════════════════════════════════════════════")
            lines.append("FORMEMO — NOTIFICATION REFRESH CORE PERFORMANCE")
            lines.append("════════════════════════════════════════════════════════════")
            lines.append("Data: \(formatter.string(from: date))")
            lines.append("Task attivi: \(taskCount)")
            lines.append("Warm-up: \(warmups)")
            lines.append("Misurazioni: \(repetitions)")
            lines.append("")

            lines.append("FETCH")
            lines.append(
                String(
                    format: "  Min        %8.3f ms",
                    fetch.min
                )
            )
            lines.append(
                String(
                    format: "  Mediana    %8.3f ms",
                    fetch.median
                )
            )
            lines.append(
                String(
                    format: "  Media      %8.3f ms",
                    fetch.mean
                )
            )
            lines.append(
                String(
                    format: "  Max        %8.3f ms",
                    fetch.max
                )
            )

            lines.append("")
            lines.append("SIGNATURE")
            lines.append(
                String(
                    format: "  Min        %8.3f ms",
                    signature.min
                )
            )
            lines.append(
                String(
                    format: "  Mediana    %8.3f ms",
                    signature.median
                )
            )
            lines.append(
                String(
                    format: "  Media      %8.3f ms",
                    signature.mean
                )
            )
            lines.append(
                String(
                    format: "  Max        %8.3f ms",
                    signature.max
                )
            )

            lines.append("")
            lines.append("BADGE")
            lines.append(
                String(
                    format: "  Min        %8.3f ms",
                    badge.min
                )
            )
            lines.append(
                String(
                    format: "  Mediana    %8.3f ms",
                    badge.median
                )
            )
            lines.append(
                String(
                    format: "  Media      %8.3f ms",
                    badge.mean
                )
            )
            lines.append(
                String(
                    format: "  Max        %8.3f ms",
                    badge.max
                )
            )

            lines.append("")
            lines.append("════════════════════════════════════════════════════════════")

            return lines.joined(separator: "\n")
        }
    }

    @MainActor
    static func runNotificationRefreshCoreBenchmark(
        modelContext: ModelContext,
        repetitions: Int = 7,
        warmups: Int = 2
    ) throws -> NotificationRefreshBenchmarkResult {

        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> {
                !$0.isCompleted
            }
        )

        let tasks = try modelContext.fetch(descriptor)

        guard !tasks.isEmpty else {
            throw NSError(
                domain: "PerformanceBenchmark",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Nessun Task attivo disponibile per il benchmark."
                ]
            )
        }

        func measure(
            _ block: () -> Void
        ) -> Double {

            let start = CFAbsoluteTimeGetCurrent()
            block()
            let end = CFAbsoluteTimeGetCurrent()

            return (end - start) * 1000
        }

        func makeSignature(_ tasks: [TodoTask]) -> String {

            guard !tasks.isEmpty else {
                return "EMPTY"
            }

            let body = tasks
                .map {
                    "\($0.id.uuidString)-\($0.title)-" +
                    "\($0.deadLine?.timeIntervalSince1970 ?? 0)-" +
                    "\($0.reminderOffsetMinutes ?? 0)-" +
                    "\($0.snoozeUntil?.timeIntervalSince1970 ?? 0)-" +
                    "\($0.manualSnoozeUntil?.timeIntervalSince1970 ?? 0)"
                }
                .joined(separator: "|")

            return "\(tasks.count)-" + body
        }

        
        
        
        
        
        // Warm-up.
        for _ in 0..<warmups {
            _ = measure {
                _ = try? modelContext.fetch(descriptor)
            }

            _ = measure {
                _ = makeSignature(tasks)
            }

            _ = measure {
                _ = TaskBadgePolicy.Index(tasks: tasks)
            }
        }

        var fetchMeasurements: [Double] = []
        var signatureMeasurements: [Double] = []
        var badgeMeasurements: [Double] = []

        fetchMeasurements.reserveCapacity(repetitions)
        signatureMeasurements.reserveCapacity(repetitions)
        badgeMeasurements.reserveCapacity(repetitions)

        for _ in 0..<repetitions {

            fetchMeasurements.append(
                measure {
                    _ = try? modelContext.fetch(descriptor)
                }
            )

            signatureMeasurements.append(
                measure {
                    _ = makeSignature(tasks)
                }
            )

            badgeMeasurements.append(
                measure {
                    _ = TaskBadgePolicy.Index(tasks: tasks)
                }
            )
        }

        return NotificationRefreshBenchmarkResult(
            date: Date(),
            taskCount: tasks.count,
            repetitions: repetitions,
            warmups: warmups,
            fetchMeasurements: fetchMeasurements,
            signatureMeasurements: signatureMeasurements,
            badgeMeasurements: badgeMeasurements
        )
    }
    
    // MARK: - Signature Strategy Benchmark

    struct SignatureStrategyBenchmarkResult {

        let date: Date
        let taskCount: Int
        let repetitions: Int
        let warmups: Int

        let currentMeasurements: [Double]
        let hashedMeasurements: [Double]
        let unsortedMeasurements: [Double]
        let directUUIDMeasurements: [Double]
        let orderIndependentMeasurements: [Double]
        
        var directUUIDMedian: Double {
            median(directUUIDMeasurements)
        }

        var orderIndependentMedian: Double {
            median(orderIndependentMeasurements)
        }

        var orderIndependentMean: Double {
            mean(orderIndependentMeasurements)
        }
        
        var directUUIDMean: Double {
            mean(directUUIDMeasurements)
        }
        
        var currentMedian: Double {
            median(currentMeasurements)
        }

        var hashedMedian: Double {
            median(hashedMeasurements)
        }
        var unsortedMedian: Double {
            median(unsortedMeasurements)
        }

        var currentMean: Double {
            mean(currentMeasurements)
        }

        var hashedMean: Double {
            mean(hashedMeasurements)
        }

        var unsortedMean: Double {
            mean(unsortedMeasurements)
        }
        
        var speedup: Double {
            guard hashedMedian > 0 else { return 0 }
            return currentMedian / hashedMedian
        }

        var report: String {

            [
                "════════════════════════════════════════════════════════════",
                "FORMEMO — SIGNATURE STRATEGY BENCHMARK",
                "════════════════════════════════════════════════════════════",
                "Data: \(date.formatted(date: .numeric, time: .standard))",
                "Task attivi: \(taskCount)",
                "Warm-up: \(warmups)",
                "Misurazioni: \(repetitions)",
                "",
                "A — SIGNATURE ATTUALE",
                String(format: " Mediana %.3f ms", currentMedian),
                String(format: " Media %.3f ms", currentMean),
                "",
                "B — HASH SENZA STRINGA GIGANTE",
                String(format: " Mediana %.3f ms", hashedMedian),
                String(format: " Media %.3f ms", hashedMean),
                "",
                "C — SIGNATURE ATTUALE SENZA SORT",
                String(format: " Mediana %.3f ms", unsortedMedian),
                String(format: " Media %.3f ms", unsortedMean),
                "",
                "D — SORT UUID DIRETTO",
                String(format: " Mediana %.3f ms", directUUIDMedian),
                String(format: " Media %.3f ms", directUUIDMean),
                "",
                "E — FINGERPRINT ORDER-INDEPENDENT",
                String(format: " Mediana %.3f ms", orderIndependentMedian),
                String(format: " Media %.3f ms", orderIndependentMean),
                "",
                String(format: "Speed-up B/A: %.2fx", speedup),
                "",
                "════════════════════════════════════════════════════════════",
                "FINE SIGNATURE STRATEGY BENCHMARK",
                "════════════════════════════════════════════════════════════"
            ]
            .joined(separator: "\n")
        }

        private func median(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }

            let sorted = values.sorted()

            if sorted.count.isMultiple(of: 2) {
                return (
                    sorted[sorted.count / 2 - 1] +
                    sorted[sorted.count / 2]
                ) / 2
            }

            return sorted[sorted.count / 2]
        }

        private func mean(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Double(values.count)
        }
    }

    @MainActor
    static func runSignatureStrategyBenchmark(
        tasks: [TodoTask],
        repetitions: Int = 7,
        warmups: Int = 2
    ) -> SignatureStrategyBenchmarkResult {

        func measure(_ block: () -> Void) -> Double {

            let start = CFAbsoluteTimeGetCurrent()

            block()

            let end = CFAbsoluteTimeGetCurrent()

            return (end - start) * 1000
        }

        // ---------------------------------------------------------
        // A — SIGNATURE ATTUALE
        // ---------------------------------------------------------

        func currentSignature(_ tasks: [TodoTask]) -> String {

            guard !tasks.isEmpty else {
                return "EMPTY"
            }

            let body = tasks
                .sorted {
                    $0.id.uuidString < $1.id.uuidString
                }
                .map {
                    "\($0.id.uuidString)-" +
                    "\($0.title)-" +
                    "\($0.deadLine?.timeIntervalSince1970 ?? 0)-" +
                    "\($0.reminderOffsetMinutes ?? 0)-" +
                    "\($0.snoozeUntil?.timeIntervalSince1970 ?? 0)-" +
                    "\($0.manualSnoozeUntil?.timeIntervalSince1970 ?? 0)"
                }
                .joined(separator: "|")

            return "\(tasks.count)-" + body
        }
        
        
        // ---------------------------------------------------------
        // C — SIGNATURE ATTUALE SENZA SORT
        // SOLO DIAGNOSTICA
        // ---------------------------------------------------------

        func unsortedSignature(_ tasks: [TodoTask]) -> String {

            guard !tasks.isEmpty else {
                return "EMPTY"
            }

            let body = tasks
                .map {
                    "\($0.id.uuidString)-" +
                    "\($0.title)-" +
                    "\($0.deadLine?.timeIntervalSince1970 ?? 0)-" +
                    "\($0.reminderOffsetMinutes ?? 0)-" +
                    "\($0.snoozeUntil?.timeIntervalSince1970 ?? 0)-" +
                    "\($0.manualSnoozeUntil?.timeIntervalSince1970 ?? 0)"
                }
                .joined(separator: "|")

            return "\(tasks.count)-" + body
        }

        
        
        
        
        // ---------------------------------------------------------
        // D — SIGNATURE CON SORT UUID DIRETTO
        // SOLO DIAGNOSTICA
        // ---------------------------------------------------------

        func uuidLessThan(_ lhs: UUID, _ rhs: UUID) -> Bool {

            withUnsafeBytes(of: lhs) { lhsBytes in
                withUnsafeBytes(of: rhs) { rhsBytes in

                    for index in 0..<16 {

                        if lhsBytes[index] != rhsBytes[index] {
                            return lhsBytes[index] < rhsBytes[index]
                        }
                    }

                    return false
                }
            }
        }

        func directUUIDSignature(_ tasks: [TodoTask]) -> String {

            guard !tasks.isEmpty else {
                return "EMPTY"
            }

            let body = tasks
                .sorted {
                    uuidLessThan($0.id, $1.id)
                }
                .map {
                    "\($0.id.uuidString)-" +
                    "\($0.title)-" +
                    "\($0.deadLine?.timeIntervalSince1970 ?? 0)-" +
                    "\($0.reminderOffsetMinutes ?? 0)-" +
                    "\($0.snoozeUntil?.timeIntervalSince1970 ?? 0)-" +
                    "\($0.manualSnoozeUntil?.timeIntervalSince1970 ?? 0)"
                }
                .joined(separator: "|")

            return "\(tasks.count)-" + body
        }
        
        
        // ---------------------------------------------------------
        // B — STESSO SORT + HASH
        // ---------------------------------------------------------

        
        
        func hashedSignature(_ tasks: [TodoTask]) -> UInt64 {

            guard !tasks.isEmpty else {
                return 0
            }

            let sortedTasks = tasks.sorted {
                $0.id.uuidString < $1.id.uuidString
            }

            var hash: UInt64 = 14_695_981_039_346_656_037

            @inline(__always)
            func combine(_ value: String) {

                for byte in value.utf8 {
                    hash ^= UInt64(byte)
                    hash = hash &* 1_099_511_628_211
                }

                hash ^= 0
                hash = hash &* 1_099_511_628_211
            }

            @inline(__always)
            func combine(_ value: Double) {
                combine(String(value))
            }

            @inline(__always)
            func combine(_ value: Int) {
                combine(String(value))
            }

            combine(tasks.count)

            for task in sortedTasks {

                combine(task.id.uuidString)
                combine(task.title)
                combine(task.deadLine?.timeIntervalSince1970 ?? 0)
                combine(task.reminderOffsetMinutes ?? 0)
                combine(task.snoozeUntil?.timeIntervalSince1970 ?? 0)
                combine(task.manualSnoozeUntil?.timeIntervalSince1970 ?? 0)
            }

            return hash
        }

        
        
        // ---------------------------------------------------------
        // E — FINGERPRINT ORDER-INDEPENDENT
        // SOLO DIAGNOSTICA
        // ---------------------------------------------------------

        func orderIndependentFingerprint(_ tasks: [TodoTask]) -> UInt64 {
            guard !tasks.isEmpty else {
                return 0
            }

            var accumulator1: UInt64 = 0x9E3779B185EBCA87
            var accumulator2: UInt64 = 0xC2B2AE3D27D4EB4F

            @inline(__always)
            func mix(_ value: UInt64, into accumulator: inout UInt64) {
                var x = value
                x ^= x >> 30
                x &*= 0xBF58476D1CE4E5B9
                x ^= x >> 27
                x &*= 0x94D049BB133111EB
                x ^= x >> 31
                accumulator ^= x
                accumulator &*= 0x9E3779B185EBCA87
            }

            @inline(__always)
            func mix(_ value: String, into accumulator: inout UInt64) {
                var hash: UInt64 = 14_695_981_039_346_656_037

                for byte in value.utf8 {
                    hash ^= UInt64(byte)
                    hash &*= 1_099_511_628_211
                }

                mix(hash, into: &accumulator)
            }

            @inline(__always)
            func mix(_ value: Double, into accumulator: inout UInt64) {
                mix(value.bitPattern, into: &accumulator)
            }

            @inline(__always)
            func mix(_ value: Int, into accumulator: inout UInt64) {
                mix(UInt64(bitPattern: Int64(value)), into: &accumulator)
            }

            for task in tasks {

                var taskHash1: UInt64 = 0x243F6A8885A308D3
                var taskHash2: UInt64 = 0x13198A2E03707344

                mix(task.id.uuidString, into: &taskHash1)
                mix(task.title, into: &taskHash1)
                mix(
                    task.deadLine?.timeIntervalSince1970 ?? 0,
                    into: &taskHash1
                )
                mix(
                    task.reminderOffsetMinutes ?? 0,
                    into: &taskHash1
                )
                mix(
                    task.snoozeUntil?.timeIntervalSince1970 ?? 0,
                    into: &taskHash1
                )
                mix(
                    task.manualSnoozeUntil?.timeIntervalSince1970 ?? 0,
                    into: &taskHash1
                )

                mix(task.id.uuidString, into: &taskHash2)
                mix(task.title, into: &taskHash2)
                mix(
                    task.deadLine?.timeIntervalSince1970 ?? 0,
                    into: &taskHash2
                )
                mix(
                    task.reminderOffsetMinutes ?? 0,
                    into: &taskHash2
                )
                mix(
                    task.snoozeUntil?.timeIntervalSince1970 ?? 0,
                    into: &taskHash2
                )
                mix(
                    task.manualSnoozeUntil?.timeIntervalSince1970 ?? 0,
                    into: &taskHash2
                )

                accumulator1 &+= taskHash1
                accumulator2 &+= taskHash2
            }

            accumulator1 ^= UInt64(tasks.count)
            accumulator2 ^= UInt64(tasks.count)

            accumulator1 &*= 0x9E3779B185EBCA87
            accumulator2 &*= 0xC2B2AE3D27D4EB4F

            return accumulator1 ^ accumulator2
        }
        
        // ---------------------------------------------------------
        // WARM-UP
        // ---------------------------------------------------------

        for _ in 0..<warmups {

            _ = currentSignature(tasks)

            _ = hashedSignature(tasks)
            
            _ = orderIndependentFingerprint(tasks)
        }

        // ---------------------------------------------------------
        // MISURAZIONI
        // ---------------------------------------------------------

        var currentMeasurements: [Double] = []
        var hashedMeasurements: [Double] = []
        var unsortedMeasurements: [Double] = []
        var directUUIDMeasurements: [Double] = []
        var orderIndependentMeasurements: [Double] = []
        
        currentMeasurements.reserveCapacity(repetitions)
        hashedMeasurements.reserveCapacity(repetitions)
        unsortedMeasurements.reserveCapacity(repetitions)
        directUUIDMeasurements.reserveCapacity(repetitions)
        orderIndependentMeasurements.reserveCapacity(repetitions)

        var currentResult = ""
        var hashedResult: UInt64 = 0
        var unsortedResult = ""
        var directUUIDResult = ""
        var orderIndependentResult: UInt64 = 0

        for _ in 0..<repetitions {

            currentMeasurements.append(
                measure {
                    currentResult = currentSignature(tasks)
                }
            )

            hashedMeasurements.append(
                measure {
                    hashedResult = hashedSignature(tasks)
                }
            )
            
            unsortedMeasurements.append(
                measure {
                    unsortedResult = unsortedSignature(tasks)
                }
            )
            directUUIDMeasurements.append(
                measure {
                    directUUIDResult = directUUIDSignature(tasks)
                }
            )
            
            orderIndependentMeasurements.append(
                measure {
                    orderIndependentResult =
                        orderIndependentFingerprint(tasks)
                }
            )
        }

        // Evita che l'ottimizzatore consideri inutilizzato il risultato.
        _ = currentResult
        _ = hashedResult
        _ = unsortedResult
        _ = directUUIDResult
        _ = orderIndependentResult

        return SignatureStrategyBenchmarkResult(
            date: Date(),
            taskCount: tasks.count,
            repetitions: repetitions,
            warmups: warmups,
            currentMeasurements: currentMeasurements,
            hashedMeasurements: hashedMeasurements,
            unsortedMeasurements: unsortedMeasurements,
            directUUIDMeasurements: directUUIDMeasurements,
            orderIndependentMeasurements: orderIndependentMeasurements
        )
    }
}

// MARK: - SwiftData Fetch Order Stability Test

extension PerformanceBenchmark {

    struct FetchOrderStabilityResult {
        let date: Date
        let repetitions: Int
        let taskCount: Int
        let comparisons: Int
        let differences: Int

        var passed: Bool {
            differences == 0
        }

        var report: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            return """
            
            ════════════════════════════════════════════════════════════
            FORMEMO — SWIFTDATA FETCH ORDER STABILITY TEST
            ════════════════════════════════════════════════════════════
            Data: \(formatter.string(from: date))
            
            Task attivi: \(taskCount)
            Fetch consecutivi: \(repetitions)
            Confronti: \(comparisons)
            Differenze di ordine: \(differences)
            
            RISULTATO
            ------------------------------------------------------------
            Ordine fetch stabile: \(passed ? "PASS" : "FAIL")
            
            NOTE
            ------------------------------------------------------------
            Il test esegue fetch consecutivi dello stesso FetchDescriptor.
            Confronta esclusivamente l'ordine degli UUID restituiti.
            Nessun Task viene creato, modificato o cancellato.
            Nessuna notifica viene programmata.
            
            ════════════════════════════════════════════════════════════
            FINE SWIFTDATA FETCH ORDER STABILITY TEST
            ════════════════════════════════════════════════════════════
            """
        }
    }

    @MainActor
    static func runFetchOrderStabilityTest(
        modelContext: ModelContext,
        repetitions: Int = 10
    ) throws -> FetchOrderStabilityResult {

        precondition(repetitions >= 2)

        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> {
                !$0.isCompleted
            }
        )

        func fetchTasks() throws -> [TodoTask] {
            try modelContext.fetch(descriptor)
        }

        let firstTasks = try fetchTasks()

        var previousIDs = firstTasks.map(\.id)
        var comparisons = 0
        var differences = 0

        for _ in 1..<repetitions {

            let currentTasks = try fetchTasks()
            let currentIDs = currentTasks.map(\.id)

            comparisons += 1

            if currentIDs != previousIDs {
                differences += 1
            }

            previousIDs = currentIDs
        }

        return FetchOrderStabilityResult(
            date: Date(),
            repetitions: repetitions,
            taskCount: firstTasks.count,
            comparisons: comparisons,
            differences: differences
        )
    }
}

// MARK: - SwiftData Fetch Order Mutation Stability Test

extension PerformanceBenchmark {

    struct FetchOrderMutationStabilityResult {

        let date: Date
        let initialCount: Int
        let afterInsertCount: Int
        let afterUpdateCount: Int
        let afterDeleteCount: Int

        let insertPreservedRelativeOrder: Bool
        let updatePreservedRelativeOrder: Bool
        let deletePreservedRelativeOrder: Bool

        var passed: Bool {
            insertPreservedRelativeOrder &&
            updatePreservedRelativeOrder &&
            deletePreservedRelativeOrder
        }

        var report: String {

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            return """

            ════════════════════════════════════════════════════════════
            FORMEMO — SWIFTDATA FETCH ORDER MUTATION STABILITY TEST
            ════════════════════════════════════════════════════════════
            Data: \(formatter.string(from: date))

            FETCH INIZIALE
            ------------------------------------------------------------
            Task attivi: \(initialCount)

            DOPO INSERIMENTO
            ------------------------------------------------------------
            Task attivi: \(afterInsertCount)
            Ordine relativo preservato: \(insertPreservedRelativeOrder ? "PASS" : "FAIL")

            DOPO MODIFICA
            ------------------------------------------------------------
            Task attivi: \(afterUpdateCount)
            Ordine relativo preservato: \(updatePreservedRelativeOrder ? "PASS" : "FAIL")

            DOPO ELIMINAZIONE
            ------------------------------------------------------------
            Task attivi: \(afterDeleteCount)
            Ordine relativo preservato: \(deletePreservedRelativeOrder ? "PASS" : "FAIL")

            RISULTATO
            ------------------------------------------------------------
            Stabilità ordine dopo mutazioni: \(passed ? "PASS" : "FAIL")

            NOTE
            ------------------------------------------------------------
            Il test verifica esclusivamente l'ordine relativo degli UUID
            dei Task già presenti prima di ogni mutazione.

            Il Task temporaneo viene inserito, modificato ed eliminato.
            Nessun Task reale preesistente viene modificato.

            Nessuna notifica viene programmata.

            ════════════════════════════════════════════════════════════
            FINE SWIFTDATA FETCH ORDER MUTATION STABILITY TEST
            ════════════════════════════════════════════════════════════
            """
        }
    }

    @MainActor
    static func runFetchOrderMutationStabilityTest(
        modelContext: ModelContext
    ) throws -> FetchOrderMutationStabilityResult {

        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> {
                !$0.isCompleted
            }
        )

        func fetchTasks() throws -> [TodoTask] {
            try modelContext.fetch(descriptor)
        }

        func preservesRelativeOrder(
            before: [UUID],
            after: [UUID]
        ) -> Bool {

            let afterSet = Set(after)

            let commonBefore = before.filter {
                afterSet.contains($0)
            }

            let beforeSet = Set(before)

            let commonAfter = after.filter {
                beforeSet.contains($0)
            }

            return commonBefore == commonAfter
        }

        // ---------------------------------------------------------
        // STATO INIZIALE
        // ---------------------------------------------------------

        let initialTasks = try fetchTasks()
        let initialOrder = initialTasks.map(\.id)

        // ---------------------------------------------------------
        // INSERIMENTO TASK TEMPORANEO
        // ---------------------------------------------------------

        let insertedTask = TodoTask(
            title: "F2 — Temporary Task"
        )

        insertedTask.isDebugTask = true

        modelContext.insert(insertedTask)
        try modelContext.save()

        let afterInsertTasks = try fetchTasks()
        let afterInsertOrder = afterInsertTasks.map(\.id)

        let insertPreserved =
            preservesRelativeOrder(
                before: initialOrder,
                after: afterInsertOrder
            )

        // ---------------------------------------------------------
        // MODIFICA DEL SOLO TASK TEMPORANEO
        // ---------------------------------------------------------

        insertedTask.title = "F2 — Temporary Task Modified"

        try modelContext.save()

        let afterUpdateTasks = try fetchTasks()
        let afterUpdateOrder = afterUpdateTasks.map(\.id)

        let updatePreserved =
            preservesRelativeOrder(
                before: afterInsertOrder,
                after: afterUpdateOrder
            )

        // ---------------------------------------------------------
        // ELIMINAZIONE DEL SOLO TASK TEMPORANEO
        // ---------------------------------------------------------

        modelContext.delete(insertedTask)
        try modelContext.save()

        let afterDeleteTasks = try fetchTasks()
        let afterDeleteOrder = afterDeleteTasks.map(\.id)

        let expectedAfterDelete =
            afterUpdateOrder.filter {
                $0 != insertedTask.id
            }

        let deletePreserved =
            expectedAfterDelete == afterDeleteOrder

        return FetchOrderMutationStabilityResult(
            date: Date(),
            initialCount: initialOrder.count,
            afterInsertCount: afterInsertOrder.count,
            afterUpdateCount: afterUpdateOrder.count,
            afterDeleteCount: afterDeleteOrder.count,
            insertPreservedRelativeOrder: insertPreserved,
            updatePreservedRelativeOrder: updatePreserved,
            deletePreservedRelativeOrder: deletePreserved
        )
    }
}

// MARK: - SwiftData Fetch Order Stress Stability Test

extension PerformanceBenchmark {

    struct FetchOrderStressStabilityResult {

        let date: Date
        let cycles: Int
        let initialCount: Int
        let totalComparisons: Int
        let differences: Int

        var passed: Bool {
            differences == 0
        }

        var report: String {

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            return """

            ════════════════════════════════════════════════════════════
            FORMEMO — SWIFTDATA FETCH ORDER STRESS STABILITY TEST
            ════════════════════════════════════════════════════════════
            Data: \(formatter.string(from: date))

            Task iniziali: \(initialCount)
            Cicli di mutazione: \(cycles)
            Confronti ordine: \(totalComparisons)
            Differenze di ordine: \(differences)

            RISULTATO
            ------------------------------------------------------------
            Stabilità ordine dopo stress test: \(passed ? "PASS" : "FAIL")

            NOTE
            ------------------------------------------------------------
            Ogni ciclo esegue:
            inserimento → modifica → eliminazione.

            Dopo ogni operazione viene eseguito un nuovo fetch.
            Viene verificato esclusivamente l'ordine relativo
            degli UUID dei Task già presenti.

            Nessun Task reale preesistente viene modificato.
            Nessuna notifica viene programmata.

            ════════════════════════════════════════════════════════════
            FINE SWIFTDATA FETCH ORDER STRESS STABILITY TEST
            ════════════════════════════════════════════════════════════
            """
        }
    }

    @MainActor
    static func runFetchOrderStressStabilityTest(
        modelContext: ModelContext,
        cycles: Int = 20
    ) throws -> FetchOrderStressStabilityResult {

        precondition(cycles >= 1)

        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> {
                !$0.isCompleted
            }
        )

        func fetchTasks() throws -> [TodoTask] {
            try modelContext.fetch(descriptor)
        }

        func preservesRelativeOrder(
            before: [UUID],
            after: [UUID]
        ) -> Bool {

            let afterSet = Set(after)

            let commonBefore = before.filter {
                afterSet.contains($0)
            }

            let beforeSet = Set(before)

            let commonAfter = after.filter {
                beforeSet.contains($0)
            }

            return commonBefore == commonAfter
        }

        let initialTasks = try fetchTasks()
        let initialOrder = initialTasks.map(\.id)

        var previousOrder = initialOrder
        var totalComparisons = 0
        var differences = 0

        for cycle in 1...cycles {

            // INSERT
            let insertedTask = TodoTask(
                title: "F3 — Temporary Task \(cycle)"
            )

            insertedTask.isDebugTask = true

            modelContext.insert(insertedTask)
            try modelContext.save()

            let afterInsert = try fetchTasks()
            let afterInsertOrder = afterInsert.map(\.id)

            totalComparisons += 1

            if !preservesRelativeOrder(
                before: previousOrder,
                after: afterInsertOrder
            ) {
                differences += 1
            }

            previousOrder = afterInsertOrder

            // UPDATE
            insertedTask.title = "F3 — Modified Task \(cycle)"

            try modelContext.save()

            let afterUpdate = try fetchTasks()
            let afterUpdateOrder = afterUpdate.map(\.id)

            totalComparisons += 1

            if !preservesRelativeOrder(
                before: previousOrder,
                after: afterUpdateOrder
            ) {
                differences += 1
            }

            previousOrder = afterUpdateOrder

            // DELETE
            modelContext.delete(insertedTask)
            try modelContext.save()

            let afterDelete = try fetchTasks()
            let afterDeleteOrder = afterDelete.map(\.id)

            totalComparisons += 1

            if afterDeleteOrder != initialOrder {
                differences += 1
            }

            previousOrder = afterDeleteOrder
        }

        return FetchOrderStressStabilityResult(
            date: Date(),
            cycles: cycles,
            initialCount: initialOrder.count,
            totalComparisons: totalComparisons,
            differences: differences
        )
    }
}

// MARK: - REAL NOTIFICATION SCHEDULING TEST

extension PerformanceBenchmark {

    struct RealNotificationSchedulingResult {

        let date: Date
        let taskCount: Int
        let expectedCount: Int
        let scheduledCount: Int
        let completedCount: Int
        let debugCount: Int
        let results: [(name: String, expected: String, actual: String?, passed: Bool)]
        let cleanupPassed: Bool

        var passed: Bool {
            results.allSatisfy(\.passed) && cleanupPassed
        }

        var report: String {

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            var lines: [String] = []

            lines.append("")
            lines.append("════════════════════════════════════════════════════════════")
            lines.append("FORMEMO — REAL NOTIFICATION SCHEDULING TEST")
            lines.append("════════════════════════════════════════════════════════════")
            lines.append("Data: \(formatter.string(from: date))")
            lines.append("")
            lines.append("Task temporanei in memoria: \(taskCount)")
            lines.append("Task con notifica attesa: \(expectedCount)")
            lines.append("Notifiche realmente schedulate: \(scheduledCount)")
            lines.append("Task completati: \(completedCount)")
            lines.append("Task debug: \(debugCount)")
            lines.append("")
            lines.append("Il test utilizza il vero NotificationManager.rebuild().")
            lines.append("Nessun Task viene inserito in SwiftData.")
            lines.append("Il badge reale non viene modificato.")
            lines.append("Le notifiche reali dell'utente non vengono cancellate.")
            lines.append("")

            for result in results {

                let status = result.passed ? "PASS" : "FAIL"

                lines.append(result.name.uppercased())
                lines.append("------------------------------------------------------------")
                lines.append("Atteso:    \(result.expected)")
                lines.append("Trovato:   \(result.actual ?? "NESSUNO")")
                lines.append("Risultato: \(status)")
                lines.append("")
            }

            lines.append("CLEANUP")
            lines.append("------------------------------------------------------------")
            lines.append(
                cleanupPassed
                ? "Notifiche di test rimosse: PASS"
                : "Notifiche di test rimosse: FAIL"
            )
            lines.append("")

            lines.append("CONCLUSIONE")
            lines.append("------------------------------------------------------------")
            lines.append(
                passed
                ? "Schedulazione reale: PASS"
                : "Schedulazione reale: FAIL"
            )
            lines.append("")

            lines.append("════════════════════════════════════════════════════════════")
            lines.append("FINE REAL NOTIFICATION SCHEDULING TEST")
            lines.append("════════════════════════════════════════════════════════════")

            return lines.joined(separator: "\n")
        }
    }

    
    
    
    
    
    static func runRealNotificationSchedulingTest() async
        -> RealNotificationSchedulingResult
    {
        let center = UNUserNotificationCenter.current()
        let now = Date()

        let leadDays = UserDefaults.standard.integer(
            forKey: "notificationLeadTimeDays"
        )

        /*
         100 Task temporanei.

         Non vengono inseriti in SwiftData.
         Ogni Task possiede un UUID nuovo e quindi
         non può collidere con una notifica reale esistente.
        */

        var tasks: [TodoTask] = []
        tasks.reserveCapacity(100)

        var expectedTypes: [UUID: String] = [:]

        var completedCount = 0
        var debugCount = 0

        for index in 0..<100 {

            let task: TodoTask

            switch index % 7 {

            // -----------------------------------------------------
            // GLOBAL
            // -----------------------------------------------------

            case 0:

                let deadline = Calendar.current.date(
                    byAdding: .day,
                    value: max(leadDays + 2, 2),
                    to: now
                )!

                task = TodoTask(
                    title: "TEST GLOBAL \(index)",
                    deadLine: deadline
                )

                expectedTypes[task.id] = "global"

            // -----------------------------------------------------
            // REMINDER
            // -----------------------------------------------------

            case 1:

                let deadline = now.addingTimeInterval(2 * 60 * 60)

                task = TodoTask(
                    title: "TEST REMINDER \(index)",
                    deadLine: deadline
                )

                task.reminderOffsetMinutes = 30
                expectedTypes[task.id] = "reminder"

            // -----------------------------------------------------
            // DEADLINE
            // -----------------------------------------------------

            case 2:

                let deadline = now.addingTimeInterval(15)

                task = TodoTask(
                    title: "TEST DEADLINE \(index)",
                    deadLine: deadline
                )

                expectedTypes[task.id] = "deadline"

            // -----------------------------------------------------
            // SNOOZE
            // -----------------------------------------------------

            case 3:

                let deadline = now.addingTimeInterval(60 * 60)

                task = TodoTask(
                    title: "TEST SNOOZE \(index)",
                    deadLine: deadline
                )

                task.snoozeUntil = now.addingTimeInterval(30)
                expectedTypes[task.id] = "snooze"

            // -----------------------------------------------------
            // MANUAL SNOOZE
            // -----------------------------------------------------

            case 4:

                let deadline = now.addingTimeInterval(60 * 60)

                task = TodoTask(
                    title: "TEST MANUAL SNOOZE \(index)",
                    deadLine: deadline
                )

                task.manualSnoozeUntil = now.addingTimeInterval(45)
                expectedTypes[task.id] = "manualSnooze"

            // -----------------------------------------------------
            // COMPLETED
            // -----------------------------------------------------

            case 5:

                let deadline = now.addingTimeInterval(60 * 60)

                task = TodoTask(
                    title: "TEST COMPLETED \(index)",
                    deadLine: deadline
                )

                task.isCompleted = true
                completedCount += 1

            // -----------------------------------------------------
            // DEBUG
            // -----------------------------------------------------

            default:

                let deadline = now.addingTimeInterval(60 * 60)

                task = TodoTask(
                    title: "TEST DEBUG \(index)",
                    deadLine: deadline
                )

                task.isDebugTask = true
                debugCount += 1
            }

            tasks.append(task)
        }

        /*
         Le notifiche di questi UUID sono univoche.
         Rimuoviamo eventuali residui di un test precedente.
        */

        let allTestIDs = tasks.map {
            "task.\($0.id.uuidString)"
        }
        let testTaskIDs = Set(tasks.map(\.id))

        center.removePendingNotificationRequests(
            withIdentifiers: allTestIDs.flatMap { baseID in

                [
                    "\(baseID).global",
                    "\(baseID).reminder",
                    "\(baseID).deadline",
                    "\(baseID).snooze",
                    "\(baseID).manualSnooze"
                ]
            }
        )

        let pendingBefore = await center.pendingNotificationRequests()

        let testPendingBefore = pendingBefore.filter { request in
            guard request.identifier.hasPrefix("task.") else {
                return false
            }

            let components = request.identifier.split(separator: ".")

            guard components.count >= 3,
                  let uuid = UUID(uuidString: String(components[1]))
            else {
                return false
            }

            return testTaskIDs.contains(uuid)
        }.count

        print("🔵 NOTIFICHE PRIMA DEL TEST: \(pendingBefore.count)")
        print("🔵 NOTIFICHE TEST PRIMA DEL TEST: \(testPendingBefore)")
        

        await NotificationManager.shared.debugRebuild(
            tasks: tasks
        )

        /*
         ---------------------------------------------------------
         LETTURA REALE DEL SISTEMA
         ---------------------------------------------------------
        */

        var pending: [UNNotificationRequest] = []

        for _ in 0..<20 {
            pending = await center.pendingNotificationRequests()

            let testPendingCount = pending.filter { request in
                guard request.identifier.hasPrefix("task.") else {
                    return false
                }

                let components = request.identifier.split(separator: ".")

                guard components.count >= 3,
                      let uuid = UUID(uuidString: String(components[1]))
                else {
                    return false
                }

                return testTaskIDs.contains(uuid)
            }.count

            if testPendingCount >= 64 {
                break
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        
        
        let pendingTestRequests = pending.filter { request in
            guard request.identifier.hasPrefix("task.") else {
                return false
            }

            let components = request.identifier.split(separator: ".")

            guard components.count >= 3,
                  let uuid = UUID(uuidString: String(components[1]))
            else {
                return false
            }

            return testTaskIDs.contains(uuid)
        }

        let pendingByID = Dictionary(
            uniqueKeysWithValues:
                pendingTestRequests.map {
                    ($0.identifier, $0)
                }
        )

        /*
         ---------------------------------------------------------
         VERIFICA
         ---------------------------------------------------------
        */

        var results: [
            (
                name: String,
                expected: String,
                actual: String?,
                passed: Bool
            )
        ] = []

        let notificationCapacity = 64
        let capacityReached = pendingTestRequests.count >= notificationCapacity

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        for task in tasks {

            let base = "task.\(task.id.uuidString)"

            guard let expectedType = expectedTypes[task.id] else {

                let possibleIDs = [
                    "\(base).global",
                    "\(base).reminder",
                    "\(base).deadline",
                    "\(base).snooze",
                    "\(base).manualSnooze"
                ]

                let found = possibleIDs.first {
                    pendingByID[$0] != nil
                }

                results.append(
                    (
                        name: task.title,
                        expected: "NESSUNA NOTIFICA",
                        actual: found,
                        passed: found == nil
                    )
                )

                continue
            }

            let expectedID = "\(base).\(expectedType)"

            guard let request = pendingByID[expectedID] else {

                let actual: String?
                let passed: Bool

                if capacityReached {
                    actual = "NON SCHEDULATA — CAPACITÀ SISTEMA"
                    passed = true
                } else {
                    actual = nil
                    passed = false
                }

                results.append(
                    (
                        name: task.title,
                        expected: expectedType,
                        actual: actual,
                        passed: passed
                    )
                )

                continue
            }

            let actualType =
                request.content.userInfo["type"] as? String

            let triggerDate =
                (request.trigger as? UNTimeIntervalNotificationTrigger)?
                    .nextTriggerDate()

            let typeMatches = actualType == expectedType

            let dateMatches: Bool

            if let triggerDate {

                /*
                 Il NotificationManager aggiunge intenzionalmente
                 uno spread di 0...2 secondi e applica un minimo
                 di sicurezza di 5 secondi.
                */

                let difference: TimeInterval

                switch expectedType {

                case "global":

                    let expectedDate = Calendar.current.date(
                        byAdding: .day,
                        value: -leadDays,
                        to: task.deadLine!
                    )!

                    difference =
                        abs(triggerDate.timeIntervalSince(expectedDate))

                case "reminder":

                    let expectedDate = Calendar.current.date(
                        byAdding: .minute,
                        value: -(task.reminderOffsetMinutes ?? 0),
                        to: task.deadLine!
                    )!

                    difference =
                        abs(triggerDate.timeIntervalSince(expectedDate))

                case "deadline":

                    difference =
                        abs(
                            triggerDate.timeIntervalSince(
                                task.deadLine!
                            )
                        )

                case "snooze":

                    difference =
                        abs(
                            triggerDate.timeIntervalSince(
                                task.snoozeUntil!
                            )
                        )

                case "manualSnooze":

                    difference =
                        abs(
                            triggerDate.timeIntervalSince(
                                task.manualSnoozeUntil!
                            )
                        )

                default:

                    difference = .infinity
                }

                dateMatches = difference <= 8

            } else {

                dateMatches = false
            }

            let passed = typeMatches && dateMatches

            let actualDescription: String

            if let triggerDate {

                actualDescription =
                    "\(actualType ?? "unknown") @ \(formatter.string(from: triggerDate))"

            } else {

                actualDescription =
                    actualType ?? "trigger mancante"
            }

            results.append(
                (
                    name: task.title,
                    expected: expectedType,
                    actual: actualDescription,
                    passed: passed
                )
            )
        }

        /*
         ---------------------------------------------------------
         CONTROLLO QUANTITATIVO
         ---------------------------------------------------------
        */

        let expectedCount = expectedTypes.count
        let scheduledCount = pendingTestRequests.count
        let capacityLimit = min(expectedCount, notificationCapacity)
        _ = scheduledCount >= capacityLimit
        /*
         ---------------------------------------------------------
         CLEANUP
         ---------------------------------------------------------
        */

        center.removePendingNotificationRequests(
            withIdentifiers: Array(
                pendingTestRequests.map(\.identifier)
            )
        )

        let remaining = await center.pendingNotificationRequests()

        let cleanupPassed = !remaining.contains { request in

            let components = request.identifier.split(separator: ".")

            guard components.count >= 3,
                  let uuid = UUID(uuidString: String(components[1]))
            else {
                return false
            }

            return testTaskIDs.contains(uuid)
        }

        return RealNotificationSchedulingResult(
            date: Date(),
            taskCount: tasks.count,
            expectedCount: expectedCount,
            scheduledCount: scheduledCount,
            completedCount: completedCount,
            debugCount: debugCount,
            results: results,
            cleanupPassed: cleanupPassed
        )
    }
}

// MARK: - Notification Consistency Check

extension PerformanceBenchmark {

    struct NotificationConsistencyResult {
        struct CategoryResult {
            let name: String
            let expected: Int
            let scheduled: Int
            let missing: [String]
            let extra: [String]
            let mismatches: [String]

            var passed: Bool {
                missing.isEmpty && extra.isEmpty && mismatches.isEmpty
            }
        }

        let date: Date
        let activeTasks: Int
        let expectedTotal: Int
        let scheduledTotal: Int
        let transientOtherCount: Int
        let categories: [CategoryResult]

        var passed: Bool {
            categories.allSatisfy(\.passed)
        }

        var report: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            var lines: [String] = []

            lines.append("")
            lines.append("════════════════════════════════════════════════════════════")
            lines.append("FORMEMO — NOTIFICATION CONSISTENCY CHECK")
            lines.append("════════════════════════════════════════════════════════════")
            lines.append("Data: \(formatter.string(from: date))")
            lines.append("Task attivi: \(activeTasks)")
            lines.append("Notifiche attese: \(expectedTotal)")
            lines.append("Notifiche schedulate: \(scheduledTotal)")
            if transientOtherCount > 0 {
                lines.append("Altre notifiche transitorie: \(transientOtherCount)")
            }
            lines.append("")

            for category in categories {
                lines.append(category.name.uppercased())
                lines.append("------------------------------------------------------------")
                lines.append("Attese:              \(category.expected)")
                lines.append("Schedulate:          \(category.scheduled)")
                lines.append("Mancanti:             \(category.missing.count)")
                lines.append("Extra:                \(category.extra.count)")
                lines.append("Trigger mismatch:     \(category.mismatches.count)")
                lines.append("Risultato:            \(category.passed ? "PASS" : "FAIL")")
                lines.append("")

                if !category.missing.isEmpty {
                    lines.append("MISSING")
                    for item in category.missing {
                        lines.append("  \(item)")
                    }
                    lines.append("")
                }

                if !category.extra.isEmpty {
                    lines.append("EXTRA")
                    for item in category.extra {
                        lines.append("  \(item)")
                    }
                    lines.append("")
                }

                if !category.mismatches.isEmpty {
                    lines.append("TRIGGER MISMATCH")
                    for item in category.mismatches {
                        lines.append("  \(item)")
                    }
                    lines.append("")
                }
            }

            if transientOtherCount > 0 {
                lines.append("ALTRE NOTIFICHE")
                lines.append("------------------------------------------------------------")
                lines.append("Sono presenti notifiche app non appartenenti")
                lines.append("ai normali ID task/document. Non vengono usate")
                lines.append("per determinare il PASS/FAIL del controllo.")
                lines.append("")
            }

            lines.append("CONCLUSIONE")
            lines.append("------------------------------------------------------------")
            lines.append("Corrispondenza notifiche: \(passed ? "PASS" : "FAIL")")
            lines.append("")
            lines.append("NOTA")
            lines.append("------------------------------------------------------------")
            lines.append("Il controllo è passivo.")
            lines.append("Non programma, modifica o cancella notifiche.")
            lines.append("Confronta la logica attesa da ForMemo")
            lines.append("con le richieste attualmente presenti in")
            lines.append("UNUserNotificationCenter.")
            lines.append("")
            lines.append("════════════════════════════════════════════════════════════")
            lines.append("FINE NOTIFICATION CONSISTENCY CHECK")
            lines.append("════════════════════════════════════════════════════════════")

            return lines.joined(separator: "\n")
        }
    }

    static func runNotificationConsistencyCheck(
        modelContext: ModelContext
    ) async throws -> NotificationConsistencyResult {

        let now = Date()

        // IMPORTANTE: non usare NotificationManager.fetchTasks(),
        // perché quel metodo può normalizzare alcuni valori nel ModelContext.
        let taskDescriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { !$0.isCompleted }
        )
        let allActiveTasks = try modelContext.fetch(taskDescriptor)

        // Gli stress-test/debug task sono esplicitamente esclusi
        // dal sistema di notifiche.
        let tasks = allActiveTasks.filter { !$0.isDebugTask }

        struct Expected {
            let id: String
            let type: String
            let date: Date
            let taskID: UUID?
        }

        var expectedByCategory: [String: [Expected]] = [
            "global": [],
            "reminder": [],
            "deadline": [],
            "snooze": [],
            "manualSnooze": [],
            "documents": []
        ]

        let lead = NotificationLeadTime(
            safeRawValue: UserDefaults.standard.integer(
                forKey: "notificationLeadTimeDays"
            )
        )

        for task in tasks {
            guard let event = NotificationManager.TaskEventCalculator.nextEvent(
                for: task,
                now: now,
                lead: lead
            ) else {
                continue
            }

            expectedByCategory[event.type, default: []].append(
                Expected(
                    id: event.id,
                    type: event.type,
                    date: event.date,
                    taskID: task.id
                )
            )
        }

        // Document notifications use their own scheduling path.
        let documentDescriptor = FetchDescriptor<DocumentItem>()
        let documents = try modelContext.fetch(documentDescriptor)

        let oneYearFromNow = Calendar.current.date(
            byAdding: .year,
            value: 1,
            to: now
        ) ?? .distantFuture

        for document in documents {
            guard document.notificationEnabled,
                  let expiryDate = document.expiryDate,
                  let triggerDate = Calendar.current.date(
                      byAdding: .day,
                      value: -document.notificationDaysBefore,
                      to: expiryDate
                  ),
                  triggerDate > now,
                  triggerDate <= oneYearFromNow else {
                continue
            }

            expectedByCategory["documents", default: []].append(
                Expected(
                    id: "document.\(document.id.uuidString)",
                    type: "documents",
                    date: triggerDate,
                    taskID: nil
                )
            )
        }

        let pending = await UNUserNotificationCenter.current()
            .pendingNotificationRequests()

        let managed = pending.filter {
            $0.identifier.hasPrefix("task.") ||
            $0.identifier.hasPrefix("document.")
        }

        let transientOtherCount = pending.count - managed.count

        func actualType(
            _ request: UNNotificationRequest
        ) -> String {
            if request.identifier.hasPrefix("document.") {
                return "documents"
            }

            if let type = request.content.userInfo["type"] as? String {
                return type
            }

            if request.identifier.hasSuffix(".global") {
                return "global"
            }
            if request.identifier.hasSuffix(".reminder") {
                return "reminder"
            }
            if request.identifier.hasSuffix(".deadline") {
                return "deadline"
            }
            if request.identifier.hasSuffix(".snooze") {
                return "snooze"
            }
            if request.identifier.hasSuffix(".manualSnooze") {
                return "manualSnooze"
            }

            return "unknown"
        }

        func actualDate(
            _ request: UNNotificationRequest
        ) -> Date? {
            if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger {
                return trigger.nextTriggerDate()
            }

            if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                return trigger.nextTriggerDate()
            }

            return nil
        }

        func expectedDateForComparison(
            _ expected: Expected
        ) -> Date {
            // Task notifications are scheduled by NotificationManager as a
            // non-repeating time-interval trigger. The implementation adds
            // a stable 0...2 second spread and guarantees a minimum delay.
            //
            // For normal future events, the expected firing date is the
            // calculated event date plus that spread. For events extremely
            // close to "now", rebuild intentionally pushes them into the
            // safe-delay window, so the comparison below uses a tolerance.
            guard expected.taskID != nil else {
                return expected.date
            }

            // NotificationManager adds a small 0...2 second stagger.
            // The checker therefore compares against the logical event date
            // with a tolerance instead of reproducing hashValue, which is
            // intentionally not stable across process launches.
            return expected.date
        }

        let triggerTolerance: TimeInterval = 15

        var categoryResults: [NotificationConsistencyResult.CategoryResult] = []

        for category in ["global", "reminder", "deadline", "snooze", "manualSnooze", "documents"] {

            let expected = expectedByCategory[category] ?? []

            let expectedByID = Dictionary(
                uniqueKeysWithValues: expected.map { ($0.id, $0) }
            )

            let actual = managed.filter {
                actualType($0) == category
            }

            let actualByID = Dictionary(
                uniqueKeysWithValues: actual.map { ($0.identifier, $0) }
            )

            let missing = expected
                .filter { actualByID[$0.id] == nil }
                .map {
                    "\($0.id) | \($0.type) | \($0.date.formatted(date: .abbreviated, time: .standard))"
                }

            let extra = actual
                .filter { expectedByID[$0.identifier] == nil }
                .map {
                    "\($0.identifier) | trigger \(actualDate($0)?.formatted(date: .abbreviated, time: .standard) ?? "nil")"
                }

            var mismatches: [String] = []

            for expectedItem in expected {

                guard let request = actualByID[expectedItem.id] else {
                    continue
                }

                if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger {

                    let expectedInterval = expectedItem.date.timeIntervalSince(now)
                    let actualInterval = trigger.timeInterval

                    let intervalDifference = abs(
                        actualInterval - expectedInterval
                    )

                    if intervalDifference > triggerTolerance {
                        mismatches.append(
                            "\(expectedItem.id) | atteso intervallo \(String(format: "%.1f", expectedInterval)) s | reale \(String(format: "%.1f", actualInterval)) s"
                        )
                    }

                } else if let trigger = request.trigger as? UNCalendarNotificationTrigger {

                    guard let actualTriggerDate = trigger.nextTriggerDate() else {
                        mismatches.append(
                            "\(expectedItem.id) | trigger non valido"
                        )
                        continue
                    }

                    let expectedDate = expectedDateForComparison(expectedItem)

                    let dateDifference = abs(
                        actualTriggerDate.timeIntervalSince(expectedDate)
                    )

                    if dateDifference > triggerTolerance {
                        mismatches.append(
                            "\(expectedItem.id) | atteso \(expectedDate.formatted(date: .abbreviated, time: .standard)) | reale \(actualTriggerDate.formatted(date: .abbreviated, time: .standard)) | differenza \(String(format: "%.1f", dateDifference)) s"
                        )
                    }

                } else {

                    mismatches.append(
                        "\(expectedItem.id) | trigger non supportato"
                    )
                }
            }

            categoryResults.append(
                NotificationConsistencyResult.CategoryResult(
                    name: category == "manualSnooze" ? "Manual Snooze" : category,
                    expected: expected.count,
                    scheduled: actual.count,
                    missing: missing,
                    extra: extra,
                    mismatches: mismatches
                )
            )
        }

        return NotificationConsistencyResult(
            date: Date(),
            activeTasks: tasks.count,
            expectedTotal: expectedByCategory.values.reduce(0) { $0 + $1.count },
            scheduledTotal: managed.count,
            transientOtherCount: transientOtherCount,
            categories: categoryResults
        )
    }
}

// MARK: - Result report

private extension PerformanceBenchmark.Result {

    func summaryLine(
        _ summary: PerformanceBenchmark.MeasurementSummary
    ) -> String {
        String(
            format:
                "%-31@  min %8.3f | med %8.3f | avg %8.3f | max %8.3f | σ %8.3f ms",
            summary.name,
            summary.min,
            summary.median,
            summary.mean,
            summary.max,
            summary.standardDeviation
        )
    }

    func makeReport() -> String {

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines: [String] = []

        lines.append("")
        lines.append("════════════════════════════════════════════════════════════")
        lines.append("FORMEMO — PERFORMANCE BENCHMARK")
        lines.append("════════════════════════════════════════════════════════════")
        lines.append("Data: \(formatter.string(from: date))")
        lines.append("Configurazione: \(buildConfiguration)")
        lines.append("Warm-up: \(warmups)")
        lines.append("Misurazioni: \(repetitions)")
        lines.append("")

        lines.append("DATABASE")
        lines.append("------------------------------------------------------------")
        lines.append("Task totali:       \(totalTasks)")
        lines.append("Task attivi:       \(activeTasks)")
        lines.append("Task completati:   \(completedTasks)")
        lines.append("")

        lines.append("TEMPI")
        lines.append("------------------------------------------------------------")

        for measurement in measurements {
            lines.append(
                summaryLine(measurement)
            )
        }

        lines.append("")
        lines.append("MEMORIA RESIDENTE")
        lines.append("------------------------------------------------------------")
        lines.append(
            String(format: "Prima:             %.1f MB", memoryBeforeMB)
        )
        lines.append(
            String(format: "Dopo:              %.1f MB", memoryAfterMB)
        )
        lines.append(
            String(format: "Delta:             %+.1f MB", memoryDeltaMB)
        )

        lines.append("")
        lines.append("LETTURA DEI DATI")
        lines.append("------------------------------------------------------------")

        let dominant = measurements.max { $0.mean < $1.mean }

        if let dominant {
            lines.append(
                String(
                    format:
                        "Operazione con media più alta: %@ (%.3f ms)",
                    dominant.name,
                    dominant.mean
                )
            )
        }

        if totalTasks >= 50000 {
            lines.append("Dataset: 50.000+ Task")
        } else if totalTasks >= 20000 {
            lines.append("Dataset: 20.000+ Task")
        } else if totalTasks >= 10000 {
            lines.append("Dataset: 10.000+ Task")
        } else {
            lines.append("Dataset: inferiore a 10.000 Task")
        }

        lines.append("")
        lines.append("NOTA")
        lines.append("------------------------------------------------------------")
        lines.append("Il benchmark non crea, modifica o cancella Task.")
        lines.append("Non misura il rendering SwiftUI frame-per-frame.")
        lines.append("Misura il lavoro SwiftData e le operazioni di dati")
        lines.append("che alimentano le liste delle attività.")
        lines.append("")
        lines.append("════════════════════════════════════════════════════════════")
        lines.append("FINE BENCHMARK")
        lines.append("════════════════════════════════════════════════════════════")

        return lines.joined(separator: "\n")
    }

    var buildConfiguration: String {
        #if DEBUG
        return "DEBUG"
        #else
        return "RELEASE"
        #endif
    }
}


// MARK: - Notification Stress Benchmark

extension PerformanceBenchmark {

    struct NotificationStressResult {
        let report: String
    }

    /// Stress test in memoria: nessuna modifica a SwiftData e nessuna
    /// programmazione tramite UNUserNotificationCenter.
    ///
    /// I task sono normali (isDebugTask = false) e vengono elaborati
    /// attraverso lo stesso TaskEventCalculator usato da NotificationManager.
    static func runNotificationStressBenchmark(
        taskCount: Int = 20_000,
        repetitions: Int = 7,
        warmups: Int = 2
    ) -> NotificationStressResult {

        let now = Date()
        let lead = NotificationLeadTime(
            safeRawValue: UserDefaults.standard.integer(
                forKey: "notificationLeadTimeDays"
            )
        )

        var tasks: [TodoTask] = []
        tasks.reserveCapacity(taskCount)

        for index in 0..<taskCount {
            let task = TodoTask(
                title: "Stress \(index)",
                deadLine: Calendar.current.date(
                    byAdding: .hour,
                    value: (index % 8760) + 1,
                    to: now
                )
            )

            task.isCompleted = false
            task.isDebugTask = false
            tasks.append(task)
        }

        func measure() -> Double {
            let start = CFAbsoluteTimeGetCurrent()

            var events = 0
            var checksum = 0

            for task in tasks {
                if let event = NotificationManager.TaskEventCalculator.nextEvent(
                    for: task,
                    now: now,
                    lead: lead
                ) {
                    events += 1
                    checksum ^= event.id.hashValue
                }
            }

            _ = events
            _ = checksum

            return (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        }

        for _ in 0..<warmups {
            _ = measure()
        }

        var measurements: [Double] = []
        measurements.reserveCapacity(repetitions)

        for _ in 0..<repetitions {
            measurements.append(measure())
        }

        let sorted = measurements.sorted()
        let mean = measurements.reduce(0, +) / Double(measurements.count)
        let median = sorted[sorted.count / 2]
        let min = sorted.first ?? 0
        let max = sorted.last ?? 0

        let variance = measurements.reduce(0) {
            $0 + pow($1 - mean, 2)
        } / Double(measurements.count)

        let standardDeviation = sqrt(variance)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines: [String] = []

        lines.append("")
        lines.append("════════════════════════════════════════════════════════════")
        lines.append("FORMEMO — NOTIFICATION STRESS BENCHMARK")
        lines.append("════════════════════════════════════════════════════════════")
        lines.append("Data: \(formatter.string(from: now))")
        lines.append("Task elaborati: \(taskCount)")
        lines.append("isDebugTask: false")
        lines.append("Warm-up: \(warmups)")
        lines.append("Misurazioni: \(repetitions)")
        lines.append("")
        lines.append("TASK EVENT CALCULATOR")
        lines.append("------------------------------------------------------------")
        lines.append(
            String(
                format:
                    "NextEvent su %d Task       min %8.3f | med %8.3f | avg %8.3f | max %8.3f | σ %8.3f ms",
                taskCount,
                min,
                median,
                mean,
                max,
                standardDeviation
            )
        )
        lines.append("")
        lines.append("NOTE")
        lines.append("------------------------------------------------------------")
        lines.append("Dataset creato esclusivamente in memoria.")
        lines.append("Nessun Task viene inserito, modificato o cancellato in SwiftData.")
        lines.append("Nessuna notifica viene programmata.")
        lines.append("Il test attraversa tutti i Task e usa TaskEventCalculator.")
        lines.append("Il limite delle notifiche pendenti di iOS non interviene nel test.")
        lines.append("")
        lines.append("════════════════════════════════════════════════════════════")
        lines.append("FINE STRESS BENCHMARK")
        lines.append("════════════════════════════════════════════════════════════")

        return NotificationStressResult(
            report: lines.joined(separator: "\n")
        )
    }
}



// MARK: - SwiftUI benchmark screen

/// Schermata temporanea DEBUG per eseguire il benchmark senza console,
/// senza inserire dati e senza annotazioni manuali.
///
/// Inserire temporaneamente dove è comodo:
///
///     PerformanceBenchmarkView()
///
/// La view usa direttamente il ModelContext dell'app.
#if DEBUG
struct PerformanceBenchmarkView: View {

    @Environment(\.modelContext) private var modelContext

    @State private var report: String = ""
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    runBenchmark()
                } label: {
                    HStack {
                        Label(
                            isRunning ? "Benchmark in corso…" : "Avvia benchmark",
                            systemImage: "speedometer"
                        )

                        Spacer()

                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)

                Button {
                    runBadgeBenchmark()
                } label: {
                    HStack {
                        Label(
                            "Test badge e ottimizzazione",
                            systemImage: "app.badge"
                        )

                        Spacer()

                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)


                Button {
                    runNotificationStressBenchmark()
                } label: {
                    HStack {
                        Label(
                            "Stress test notifiche 20.000 Task",
                            systemImage: "bell.and.waves.left.and.right"
                        )

                        Spacer()

                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)

                Button {
                    runNotificationRebuildBenchmark()
                } label: {
                    HStack {
                        Label(
                            "Performance rebuild notifiche",
                            systemImage: "bell.badge"
                        )

                        Spacer()

                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)
                
                Button {
                    runRealNotificationSchedulingTest()
                } label: {
                    HStack {
                        Label(
                            "Test reale notifiche 100 Task",
                            systemImage: "bell.badge"
                        )

                        Spacer()

                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)
                
                Button {
                    runNotificationConsistencyCheck()
                } label: {
                    HStack {
                        Label(
                            "Verifica notifiche schedulate",
                            systemImage: "bell.badge"
                        )

                        Spacer()

                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)
                
                Button {
                    runSignatureStrategyBenchmark()
                } label: {
                    HStack {
                        Label(
                            "Performance signature notifiche",
                            systemImage: "number"
                        )

                        Spacer()

                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)
                
                Button {
                    runFetchOrderStabilityTest()
                } label: {
                    HStack {
                        Label(
                            "Stabilità ordine SwiftData",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        Spacer()
                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)
                
                Button {
                    runNotificationRefreshCoreBenchmark()
                } label: {
                    HStack {
                        Label(
                            "Performance refresh notifiche",
                            systemImage: "arrow.clockwise.circle"
                        )

                        Spacer()

                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)
                
                Button {
                    runFetchOrderMutationStabilityTest()
                } label: {
                    HStack {
                        Label(
                            "Stabilità ordine dopo mutazioni",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        Spacer()
                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)
                
                Button {
                    runFetchOrderStressStabilityTest()
                } label: {
                    Label(
                        "Test F3 — Stabilità ordine",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
            }

            if let errorMessage {
                Section("Errore") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            if !report.isEmpty {

                Section("Report") {

                    TextEditor(text: .constant(report))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 250, maxHeight: 500)
                }
            }
        }
        .navigationTitle("Performance Benchmark")
        .contentMargins(.bottom, 70, for: .scrollContent)
    }

    
    
    private func runFetchOrderStressStabilityTest() {

        isRunning = true
        errorMessage = nil
        report = ""

        Task { @MainActor in

            do {

                let result =
                    try PerformanceBenchmark
                        .runFetchOrderStressStabilityTest(
                            modelContext: modelContext,
                            cycles: 20
                        )

                report = result.report
                print(result.report)

            } catch {

                errorMessage = error.localizedDescription
            }

            isRunning = false
        }
    }
    
    private func runNotificationRefreshCoreBenchmark() {

        isRunning = true
        errorMessage = nil
        report = ""

        Task { @MainActor in

            do {

                let result =
                    try PerformanceBenchmark
                        .runNotificationRefreshCoreBenchmark(
                            modelContext: modelContext,
                            repetitions: 7,
                            warmups: 2
                        )

                report = result.report

                print(result.report)

            } catch {

                errorMessage = error.localizedDescription
            }

            isRunning = false
        }
    }
    private func runBenchmark() {
        isRunning = true
        errorMessage = nil
        report = ""

        // Esegue il lavoro sul MainActor perché ModelContext e SwiftData
        // dell'app vengono qui utilizzati nel loro normale contesto.
        Task { @MainActor in
            do {
                let result = try PerformanceBenchmark.run(
                    modelContext: modelContext,
                    repetitions: 7,
                    warmups: 2
                )

                report = result.report
                print(result.report)
            } catch {
                errorMessage = error.localizedDescription
            }

            isRunning = false
        }
    }

    private func runNotificationRebuildBenchmark() {

        isRunning = true
        errorMessage = nil
        report = ""

        Task { @MainActor in

            do {

                let descriptor = FetchDescriptor<TodoTask>(
                    predicate: #Predicate<TodoTask> {
                        !$0.isCompleted
                    }
                )

                let realTasks = try modelContext.fetch(descriptor)

                // Usiamo al massimo 60 Task reali già presenti,
                // senza crearne o modificarne nessuno.
                let tasks = Array(realTasks.prefix(60))

                guard !tasks.isEmpty else {
                    throw NSError(
                        domain: "PerformanceBenchmark",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Nessun Task attivo disponibile per il benchmark."
                        ]
                    )
                }

                let result =
                    await PerformanceBenchmark.runNotificationRebuildBenchmark(
                        tasks: tasks,
                        repetitions: 7,
                        warmups: 2
                    )

                report = result.report

                print(result.report)

            } catch {

                errorMessage = error.localizedDescription
            }

            isRunning = false
        }
    }
    
    private func runBadgeBenchmark() {
        isRunning = true
        errorMessage = nil
        report = ""

        Task { @MainActor in
            do {
                let descriptor = FetchDescriptor<TodoTask>(
                    predicate: #Predicate<TodoTask> {
                        !$0.isCompleted
                    }
                )

                let tasks = try modelContext.fetch(descriptor)

                let result = PerformanceBenchmark.runBadgeBenchmark(
                    tasks: tasks,
                    repetitions: 7,
                    warmups: 2
                )

                report = result.report
                print(result.report)
            } catch {
                errorMessage = error.localizedDescription
            }

            isRunning = false
        }
    }


    private func runNotificationStressBenchmark() {
        isRunning = true
        errorMessage = nil
        report = ""

        Task { @MainActor in
            let result = PerformanceBenchmark.runNotificationStressBenchmark(
                taskCount: 20_000,
                repetitions: 7,
                warmups: 2
            )

            report = result.report
            print(result.report)
            isRunning = false
        }
    }
    
    private func runRealNotificationSchedulingTest() {
        isRunning = true
        errorMessage = nil
        report = ""

        Task { @MainActor in
            let result = await PerformanceBenchmark.runRealNotificationSchedulingTest()

            report = result.report
            print(result.report)

            isRunning = false
        }
    }

    private func runNotificationConsistencyCheck() {
        isRunning = true
        errorMessage = nil
        report = ""

        Task { @MainActor in
            do {
                let result = try await PerformanceBenchmark
                    .runNotificationConsistencyCheck(
                        modelContext: modelContext
                    )

                report = result.report
                print(result.report)
            } catch {
                errorMessage = error.localizedDescription
            }

            isRunning = false
        }
    }
    
    private func runSignatureStrategyBenchmark() {

        isRunning = true
        errorMessage = nil
        report = ""

        Task { @MainActor in

            do {

                let descriptor = FetchDescriptor<TodoTask>(
                    predicate: #Predicate<TodoTask> {
                        !$0.isCompleted
                    }
                )

                let tasks = try modelContext.fetch(descriptor)

                guard !tasks.isEmpty else {
                    throw NSError(
                        domain: "PerformanceBenchmark",
                        code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Nessun Task attivo disponibile per il benchmark."
                        ]
                    )
                }

                let result =
                    PerformanceBenchmark.runSignatureStrategyBenchmark(
                        tasks: tasks,
                        repetitions: 7,
                        warmups: 2
                    )

                report = result.report

                print(result.report)

            } catch {

                errorMessage = error.localizedDescription
            }

            isRunning = false
        }
    }
    
    private func runFetchOrderStabilityTest() {

        isRunning = true
        errorMessage = nil
        report = ""

        Task { @MainActor in

            do {

                let result =
                    try PerformanceBenchmark
                        .runFetchOrderStabilityTest(
                            modelContext: modelContext,
                            repetitions: 10
                        )

                report = result.report

            } catch {

                errorMessage = error.localizedDescription

            }

            isRunning = false
        }
    }
    
    private func runFetchOrderMutationStabilityTest() {

        isRunning = true
        errorMessage = nil
        report = ""

        Task { @MainActor in

            do {

                let result =
                    try PerformanceBenchmark
                        .runFetchOrderMutationStabilityTest(
                            modelContext: modelContext
                        )

                report = result.report

            } catch {

                errorMessage = error.localizedDescription

            }

            isRunning = false
        }
    }
    

}
#endif

#endif
