import SwiftUI
import SwiftData

// MARK: - mainInfoSection

 struct MainInfoSection: View {
    @Bindable var task: TodoTask
    let rowModel: TaskRowDisplayModel
    let iconStyle: TaskIconStyle
    let saveTask: () -> Void
    let dismiss: DismissAction
    let modelContext: ModelContext

    @Environment(AppSettings.self)
    private var settings

    private var shouldShowHighlight: Bool {
        guard settings.highlightEnabled else {
            return false
        }

        guard task.priority.systemImage == "flame" else {
            return false
        }

        guard !task.isCompleted else {
            return false
        }

        let deadline = task.deadLine ?? .distantFuture

        return deadline < .now || Calendar.current.isDateInToday(deadline)
    }

    private var highlightColor: Color {
        Color(hex: settings.highlightColorHex) ?? .red
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 0) {
                    if shouldShowHighlight {
                        Rectangle()
                            .fill(highlightColor)
                            .frame(width: 1.3)
                            .frame(height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .padding(.trailing, 12)
                    }

                    TaskIconContent(
                        model: rowModel,
                        iconStyle: iconStyle,
                        showAttachments: false,
                        showLocation: false
                    )
                    .padding(.trailing, 10)

                    TextField(
                        "Title",
                        text: $task.title,
                        axis: .vertical
                    )
                    .lineLimit(1...2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .onSubmit(saveTask)
                    .font(.headline)
                    .strikethrough(task.isCompleted, color: .secondary)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                }

                TextField(
                    "Description",
                    text: $task.taskDescription,
                    axis: .vertical
                )
                .onSubmit(saveTask)
                .font(.body)
                .foregroundStyle(.primary).opacity(0.7)

                Divider()
                
                Toggle(isOn: Binding(
                    get: { task.isCompleted },
                    set: { newValue in
                        if newValue == true, task.recurrenceRule != nil {
                            task.completeRecurringTask(
                                in: modelContext,
                                options: settings.recurringTaskOptions
                            )
                        } else {
                            task.isCompleted = newValue
                            task.completedAt = newValue ? .now : nil
                            task.snoozeUntil = nil
                        }

                        saveTask()

                        if newValue == true {
                            dismiss()
                        }
                    }
                ))
                {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Completed")

                            if task.recurrenceRule != nil {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }

                        if let completedDate = task.completedAt {
                            Text("at \(completedDate.formatted(date: .numeric, time: .shortened))")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        if task.recurrenceRule != nil {
                            Text("Recurring task")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .tint(.green)
            }
        }
        .listRowBackground(Color(.systemBackground).opacity(0.3))
    }
}
