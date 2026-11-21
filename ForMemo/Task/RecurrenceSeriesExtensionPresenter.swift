import SwiftUI
import SwiftData
import os

/// Receives committed recurring-occurrence completions and presents the offer
/// outside the tab container, so no changes to TaskTabView are required.
struct RecurrenceSeriesExtensionPresenter: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @State private var pendingRecurrenceExtensionTask: TodoTask?

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .recurrenceOccurrenceCompleted
                )
            ) { notification in
                guard let taskID = notification.object as? UUID else {
                    AppLogger.persistence.error(
                        "[RecurrenceExtension] Received signal with invalid object type: \(String(describing: notification.object), privacy: .public)"
                    )
                    return
                }

                AppLogger.persistence.debug(
                    "[RecurrenceExtension] Presenter received signal task=\(taskID.uuidString, privacy: .public)"
                )

                // Allow the completing view to begin its dismissal before presenting.
                Task { @MainActor in
                    await Task.yield()

                    guard pendingRecurrenceExtensionTask == nil else {
                        AppLogger.persistence.debug(
                            "[RecurrenceExtension] Presentation skipped: another extension sheet is already pending; incoming task=\(taskID.uuidString, privacy: .public)"
                        )
                        return
                    }

                    let taskIDValue = taskID
                    let descriptor = FetchDescriptor<TodoTask>(
                        predicate: #Predicate<TodoTask> { candidate in
                            candidate.id == taskIDValue
                        }
                    )

                    do {
                        guard let completedTask = try modelContext.fetch(descriptor).first else {
                            AppLogger.persistence.error(
                                "[RecurrenceExtension] Task not found in presenter ModelContext task=\(taskID.uuidString, privacy: .public)"
                            )
                            return
                        }

                        let isFinal = try RecurrenceEngine.isFinalPlannedOccurrence(
                            completedTask,
                            in: modelContext
                        )

                        guard isFinal else {
                            AppLogger.persistence.debug(
                                "[RecurrenceExtension] Task is not the final materialized occurrence task=\(taskID.uuidString, privacy: .public) completed=\(completedTask.isCompleted) hasRule=\(completedTask.recurrenceRule != nil) hasRecurrenceID=\(completedTask.recurrenceID != nil) occurrenceIndex=\(completedTask.occurrenceIndex ?? -1)"
                            )
                            return
                        }

                        AppLogger.persistence.debug(
                            "[RecurrenceExtension] Final occurrence confirmed; scheduling presentation task=\(taskID.uuidString, privacy: .public)"
                        )
                        pendingRecurrenceExtensionTask = completedTask
                    } catch {
                        AppLogger.persistence.error(
                            "[RecurrenceExtension] Final occurrence check failed task=\(taskID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }
            .fullScreenCover(
                item: $pendingRecurrenceExtensionTask,
                onDismiss: {
                    AppLogger.persistence.debug(
                        "[RecurrenceExtension] Extension sheet dismissed"
                    )
                }
            ) { task in
                RecurrenceSeriesExtensionSheet(task: task)
                    .onAppear {
                        AppLogger.persistence.debug(
                            "[RecurrenceExtension] Extension sheet appeared task=\(task.id.uuidString, privacy: .public)"
                        )
                    }
            }
    }
}

private struct RecurrenceSeriesExtensionSheet: View {
    private enum ExtensionMode: String {
        case count
        case endDate
    }

    private enum ExtensionRequest {
        case count(Int)
        case endDate(Date)
    }

    private enum ActiveAlert: Identifiable {
        case confirmation(additionalOccurrences: Int, capped: Bool)
        case error(String)

        var id: String {
            switch self {
            case .confirmation:
                return "confirmation"
            case .error(let message):
                return "error-\(message)"
            }
        }
    }

    let task: TodoTask

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var extensionMode: ExtensionMode = .count
    @State private var additionalOccurrences: Int
    @State private var extensionEndDate: Date
    @State private var pendingExtensionRequest: ExtensionRequest?
    @State private var activeAlert: ActiveAlert?
    @State private var isExtending = false

    private var maximumAdditionalOccurrences: Int {
        RecurrenceEngine.maximumGeneratedFutureOccurrences
    }

    private var minimumExtensionEndDate: Date {
        let nextDate = RecurrenceEngine.nextScheduledOccurrenceDate(
            after: task,
            in: modelContext
        ) ?? RecurrenceEngine.nextScheduledOccurrenceDate(after: task)
            ?? task.deadLine
            ?? .now
        return Calendar.current.startOfDay(for: nextDate)
    }

    init(task: TodoTask) {
        self.task = task
        _additionalOccurrences = State(
            initialValue: min(2, RecurrenceEngine.maximumGeneratedFutureOccurrences)
        )
        _extensionMode = State(
            initialValue: task.recurrenceCount == nil && task.recurrenceEndDate != nil
                ? .endDate
                : .count
        )
        let firstAdditionalDate = RecurrenceEngine.nextScheduledOccurrenceDate(after: task)
            ?? task.deadLine
            ?? .now
        let initialEndDate: Date
        if let existingEndDate = task.recurrenceEndDate,
           Calendar.current.startOfDay(for: existingEndDate)
                >= Calendar.current.startOfDay(for: firstAdditionalDate) {
            initialEndDate = existingEndDate
        } else {
            initialEndDate = firstAdditionalDate
        }
        _extensionEndDate = State(initialValue: initialEndDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(task.title)
                        .font(.headline)
                    Text("The last scheduled occurrence in this series is complete. You can extend the same series without changing past occurrences.")
                }

                Section("Continue this series") {
                    Picker("Extension method", selection: $extensionMode) {
                        
                        Text("End date")
                            .tag(ExtensionMode.endDate)
                        
                        Text("Additional occurrences")
                            .tag(ExtensionMode.count)

                    }
                    .pickerStyle(.segmented)

                    switch extensionMode {
                    case .count:
                        HStack {
                            Text("Additional occurrences")
                            Spacer()
                            AcceleratingStepper(
                                selection: $additionalOccurrences,
                                range: 1...maximumAdditionalOccurrences
                            )
                        }

                    case .endDate:
                        DatePicker(
                            "End date",
                            selection: $extensionEndDate,
                            in: minimumExtensionEndDate...,
                            displayedComponents: .date
                        )
                        Text("Occurrences will be generated through the selected date. If more than \(RecurrenceGenerationConfiguration.maximumOccurrencesPerOperation) are required, you can choose to create the first \(RecurrenceGenerationConfiguration.maximumOccurrencesPerOperation).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("The recurrence rule and interval will be preserved. Past tasks and their completion status will remain unchanged.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .contentMargins(.bottom, 70, for: .scrollContent)
            .navigationTitle("Series end")
            
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExtending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Extend") { requestExtension() }
                        .disabled(isExtending)
                }
            }
            .overlay {
                if isExtending {
                    ProgressView("Extending series…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .confirmation(let count, let capped):
                    let message: Text = capped
                        ? Text("This extension requires more than \(RecurrenceGenerationConfiguration.maximumOccurrencesPerOperation) occurrences. Only the first \(RecurrenceGenerationConfiguration.maximumOccurrencesPerOperation) additional occurrences will be created.")
                        : Text("This extension will create \(count) additional occurrences.")

                    return Alert(
                        title: Text("Extend series?"),
                        message: message,
                        primaryButton: .default(Text("Extend"), action: performPendingExtension),
                        secondaryButton: .cancel(Text("Cancel"), action: {
                            pendingExtensionRequest = nil
                        })
                    )

                case .error(let message):
                    return Alert(
                        title: Text("Unable to extend series"),
                        message: Text(message),
                        dismissButton: .default(Text("OK"), action: {
                            activeAlert = nil
                        })
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if Calendar.current.startOfDay(for: extensionEndDate) < minimumExtensionEndDate {
                extensionEndDate = minimumExtensionEndDate
            }
        }
    }

    @MainActor
    private func requestExtension() {
        guard !isExtending else { return }

        do {
            let request: ExtensionRequest
            let requestedCount: Int
            let isCapped: Bool

            switch extensionMode {
            case .count:
                request = .count(additionalOccurrences)
                requestedCount = additionalOccurrences
                isCapped = false

            case .endDate:
                let preview = try RecurrenceEngine.previewExtension(
                    after: task,
                    until: extensionEndDate,
                    in: modelContext
                )
                request = .endDate(extensionEndDate)
                requestedCount = preview.additionalOccurrences
                isCapped = preview.exceedsOperationLimit
            }

            guard requestedCount > 0 else {
                activeAlert = .error(
                    String(localized: "Choose an end date that includes at least one additional occurrence.")
                )
                return
            }

            pendingExtensionRequest = request

            // Match initial recurrence creation: ask before generating large
            // batches, and make the cap explicit before any model mutation.
            if requestedCount > RecurrenceGenerationConfiguration.confirmationThreshold || isCapped {
                activeAlert = .confirmation(
                    additionalOccurrences: min(requestedCount, maximumAdditionalOccurrences),
                    capped: isCapped
                )
            } else {
                performPendingExtension()
            }
        } catch let error as RecurrenceEngine.ExtensionError {
            presentPreviewError(error)
        } catch {
            AppLogger.persistence.error(
                "Recurrence extension preview failed: \(error.localizedDescription)"
            )
            activeAlert = .error(
                String(localized: "The series could not be extended. No changes were saved.")
            )
        }
    }

    @MainActor
    private func performPendingExtension() {
        guard !isExtending, let request = pendingExtensionRequest else { return }
        activeAlert = nil
        isExtending = true

        Task { @MainActor in
            do {
                let createdOccurrences: [TodoTask]
                switch request {
                case .count(let count):
                    createdOccurrences = try RecurrenceEngine.extendSeries(
                        after: task,
                        by: count,
                        in: modelContext
                    )

                case .endDate(let endDate):
                    createdOccurrences = try RecurrenceEngine.extendSeries(
                        after: task,
                        until: endDate,
                        in: modelContext
                    )
                }

                try modelContext.save()
                modelContext.processPendingChanges()

                _ = await ForMemoAlarmManager.shared.synchronize(
                    tasks: createdOccurrences, in: modelContext
                )
                await NotificationManager.shared.refreshAndWait(force: true)

                NotificationCenter.default.post(
                    name: .taskDidChange,
                    object: nil
                )

                pendingExtensionRequest = nil
                dismiss()
            } catch let error as RecurrenceEngine.ExtensionError {
                modelContext.rollback()
                AppLogger.persistence.error(
                    "Recurrence extension failed: \(String(describing: error))"
                )
                presentPreviewError(error)
            } catch {
                modelContext.rollback()
                AppLogger.persistence.error(
                    "Recurrence extension failed: \(error.localizedDescription)"
                )
                activeAlert = .error(
                    String(localized: "The series could not be extended. No changes were saved.")
                )
            }

            isExtending = false
        }
    }

    @MainActor
    private func presentPreviewError(_ error: RecurrenceEngine.ExtensionError) {
        switch error {
        case .invalidExtension:
            activeAlert = .error(
                String(localized: "Choose an end date that includes at least one additional occurrence.")
            )
        case .invalidSeries, .notFinalOccurrence, .maximumReached:
            activeAlert = .error(
                String(localized: "The series could not be extended. No changes were saved.")
            )
        }
    }
}
