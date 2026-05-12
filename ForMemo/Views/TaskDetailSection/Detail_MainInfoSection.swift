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

    private var shouldShowHighlight: Bool {
        guard highlightEnabled else {
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

    @AppStorage("tasklist.highlightEnabled")
    private var highlightEnabled: Bool = true

    @AppStorage("tasklist.highlightColor")
    private var highlightColorHex: String = Color.red.toHex() ?? ""

    private var highlightColor: Color {
        Color(hex: highlightColorHex) ?? .red
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 0) {
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
                    .lineLimit(1...10)
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
                .font(.headline)
                .foregroundStyle(.secondary)

                Toggle(isOn: Binding(
                    get: { task.isCompleted },
                    set: { newValue in
                        if newValue == true, task.recurrenceRule != nil {
                            task.completeRecurringTask(in: modelContext)
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
                )) {
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
                                .foregroundColor(.secondary)
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
