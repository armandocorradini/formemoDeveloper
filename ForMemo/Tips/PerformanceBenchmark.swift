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
                    Text(report)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    Button {
                        UIPasteboard.general.string = report
                    } label: {
                        Label("Copia report", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .navigationTitle("Performance Benchmark")
        .contentMargins(.bottom, 70, for: .scrollContent)
    }

    private func runBenchmark() {
        isRunning = true
        errorMessage = nil

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
}
#endif

#endif
