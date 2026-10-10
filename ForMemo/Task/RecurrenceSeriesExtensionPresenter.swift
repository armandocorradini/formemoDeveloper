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
                    return
                }

                // Wait for the completing view to finish its dismissal before
                // presenting, especially when completion starts in TaskDetailView.
                Task { @MainActor in
                    await Task.yield()

                    guard pendingRecurrenceExtensionTask == nil else {
                        return
                    }

                    let taskIDValue = taskID
                    let descriptor = FetchDescriptor<TodoTask>(
                        predicate: #Predicate<TodoTask> { candidate in
                            candidate.id == taskIDValue
                        }
                    )

                    do {
                        guard let completedTask = try modelContext.fetch(descriptor).first,
                              try RecurrenceEngine.isFinalPlannedOccurrence(
                                completedTask,
                                in: modelContext
                              ) else {
                            return
                        }

                        pendingRecurrenceExtensionTask = completedTask
                    } catch {
                        AppLogger.persistence.error(
                            "Final recurrence occurrence check failed: \(error.localizedDescription)"
                        )
                    }
                }
            }
            .sheet(item: $pendingRecurrenceExtensionTask) { task in
                RecurrenceSeriesExtensionSheet(task: task)
            }
    }
}

private struct RecurrenceSeriesExtensionSheet: View {
    let task: TodoTask

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var additionalOccurrences: Int
    @State private var isExtending = false
    @State private var errorMessage: String?

    private var maximumAdditionalOccurrences: Int {
        max(1, RecurrenceEngine.maximumGeneratedTasks - (task.occurrenceIndex ?? 1))
    }

    init(task: TodoTask) {
        self.task = task
        let currentIndex = max(1, task.occurrenceIndex ?? 1)
        let available = max(1, RecurrenceEngine.maximumGeneratedTasks - currentIndex)
        _additionalOccurrences = State(
            initialValue: min(currentIndex, available)
        )
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
                    Stepper(value: $additionalOccurrences, in: 1...maximumAdditionalOccurrences) {
                        HStack {
                            Text("Additional occurrences")
                            Spacer()
                            Text(additionalOccurrences.formatted())
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("The recurrence rule and interval will be preserved. Past tasks and their completion status will remain unchanged.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Series completed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExtending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Extend") { extendSeries() }
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
            .alert("Unable to extend series", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "The series could not be extended. No changes were saved.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    private func extendSeries() {
        guard !isExtending else { return }
        isExtending = true

        Task { @MainActor in
            do {
                let createdOccurrences = try RecurrenceEngine.extendSeries(
                    after: task,
                    by: additionalOccurrences,
                    in: modelContext
                )

                try modelContext.save()
                modelContext.processPendingChanges()

                _ = await ForMemoAlarmManager.shared.synchronize(
                    tasks: createdOccurrences
                )
                await NotificationManager.shared.refreshAndWait(force: true)

                NotificationCenter.default.post(
                    name: .taskDidChange,
                    object: nil
                )

                dismiss()
            } catch {
                modelContext.rollback()
                AppLogger.persistence.error(
                    "Recurrence extension failed: \(error.localizedDescription)"
                )
                errorMessage = "The series could not be extended. No changes were saved."
            }

            isExtending = false
        }
    }
}
