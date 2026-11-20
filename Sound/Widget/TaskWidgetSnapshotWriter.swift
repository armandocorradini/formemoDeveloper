import Foundation
import SwiftData
import WidgetKit

extension TaskWidgetSnapshotStore {
    /// Coalesces closely spaced refresh requests into one snapshot calculation/write.
    /// Use direct refresh(from:) only when the snapshot must be written immediately,
    /// such as when the app enters the background.
    @MainActor
    static func scheduleRefresh(
        from context: ModelContext,
        delay: Duration = .milliseconds(400)
    ) {
        let clock = ContinuousClock()
        let requestedDeadline = clock.now.advanced(by: delay)

        // Keep the first deadline in a burst instead of pushing it forward
        // on every remote-change event. This bounds the wait even if CloudKit
        // continues emitting changes.
        let deadline = scheduledRefreshDeadline ?? requestedDeadline
        scheduledRefreshDeadline = deadline


        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = Task { @MainActor in
            do {
                try await clock.sleep(until: deadline)
                try Task.checkCancellation()
                scheduledRefreshDeadline = nil
                scheduledRefreshTask = nil
                refresh(from: context)
            } catch is CancellationError {
                // A newer request superseded this refresh.
            } catch {
                // No action is needed if the scheduled sleep fails.
            }
        }
    }

    @MainActor
    static func refresh(from context: ModelContext) {
        let descriptor = FetchDescriptor<TodoTask>()

        do {
            let allTasks = try context.fetch(descriptor)
            let calendar = Calendar.current
            let now = Date()
            let startOfToday = calendar.startOfDay(for: now)

            let overduePreviousDaysCount = allTasks.reduce(into: 0) { count, task in
                guard
                    !task.isCompleted,
                    let deadline = task.deadLine,
                    deadline < startOfToday
                else {
                    return
                }
                count += 1
            }

            // Keep every open task with a deadline in the shared snapshot.
            // The widget filters this stable data for the date of each timeline entry,
            // so day changes and deadline styling do not require the app to run.
            let snapshotTasks = allTasks
                .filter { !$0.isCompleted && $0.deadLine != nil }
                .sorted { first, second in
                    guard let firstDate = first.deadLine,
                          let secondDate = second.deadLine else {
                        return first.deadLine != nil
                    }
                    if firstDate != secondDate {
                        return firstDate < secondDate
                    }
                    let titleComparison = first.title.localizedCaseInsensitiveCompare(
                        second.title
                    )
                    if titleComparison != .orderedSame {
                        return titleComparison == .orderedAscending
                    }
                    // Stable final tie-breaker prevents equivalent tasks from
                    // changing array order between fetches and causing false diffs.
                    return first.id.uuidString < second.id.uuidString
                }
                .map { task in
                    TaskWidgetItem(
                        id: task.id,
                        title: task.title,
                        deadline: task.deadLine,
                        isCompleted: task.isCompleted,
                        priorityRaw: task.priorityRaw
                    )
                }

            let weather = WeatherManager.shared.weather(for: now)
            let weatherSymbolName = weather.map {_ in 
                WeatherManager.shared.representativeSymbol(for: now)
            }

            let snapshot = TaskWidgetSnapshot(
                generatedAt: now,
                tasks: snapshotTasks,
                overduePreviousDaysCount: overduePreviousDaysCount,
                weatherSymbolName: weatherSymbolName,
                weatherMinTemperature: weather?.minTemperature,
                weatherMaxTemperature: weather?.maxTemperature
            )

            guard let defaults = UserDefaults(
                suiteName: TaskWidgetSnapshotStore.appGroupID
            ) else {
                return
            }

            // generatedAt is intentionally excluded: it changes on every refresh
            // but is not displayed by either widget.
            if let existingSnapshot = TaskWidgetSnapshotStore.load() {
                var changedFields: [String] = []
                if existingSnapshot.tasks != snapshot.tasks {
                    changedFields.append("tasks")
                }
                if existingSnapshot.overduePreviousDaysCount != snapshot.overduePreviousDaysCount {
                    changedFields.append("overduePreviousDaysCount")
                }
                if existingSnapshot.weatherSymbolName != snapshot.weatherSymbolName {
                    changedFields.append("weatherSymbolName")
                }
                if existingSnapshot.weatherMinTemperature != snapshot.weatherMinTemperature {
                    changedFields.append("weatherMinTemperature")
                }
                if existingSnapshot.weatherMaxTemperature != snapshot.weatherMaxTemperature {
                    changedFields.append("weatherMaxTemperature")
                }

                guard !changedFields.isEmpty else {
                    return
                }
            }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            defaults.set(data, forKey: "todayTasksSnapshot")

            WidgetCenter.shared.reloadTimelines(ofKind: "ForMemoWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "ForMemoAgendaWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "ForMemoCalendarTasksWidget")
        } catch {
            #if DEBUG
            print("ForMemo widget snapshot update failed: \(error)")
            #endif
        }
    }
}

extension TaskWidgetSnapshotStore {
    /// Updates only the weather fields in the existing shared snapshot.
    /// Task data remains unchanged; if no snapshot exists yet, the regular
    /// context-based refresh will populate it when available.
    @MainActor
    static func updateWeather(
        symbolName: String?,
        minTemperature: Int?,
        maxTemperature: Int?
    ) {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: "todayTasksSnapshot")
        else {
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let existingSnapshot = try decoder.decode(TaskWidgetSnapshot.self, from: data)

            // Weather refreshes can be frequent; do not persist or reload timelines
            // when the values already displayed by the widgets are unchanged.
            guard existingSnapshot.weatherSymbolName != symbolName
                    || existingSnapshot.weatherMinTemperature != minTemperature
                    || existingSnapshot.weatherMaxTemperature != maxTemperature else {
                return
            }

            let updatedSnapshot = TaskWidgetSnapshot(
                generatedAt: existingSnapshot.generatedAt,
                tasks: existingSnapshot.tasks,
                overduePreviousDaysCount: existingSnapshot.overduePreviousDaysCount,
                weatherSymbolName: symbolName,
                weatherMinTemperature: minTemperature,
                weatherMaxTemperature: maxTemperature
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            defaults.set(try encoder.encode(updatedSnapshot), forKey: "todayTasksSnapshot")
            WidgetCenter.shared.reloadTimelines(ofKind: "ForMemoWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "ForMemoAgendaWidget")
        } catch {
            #if DEBUG
            print("ForMemo widget weather snapshot update failed: \(error)")
            #endif
        }
    }
}
