import SwiftUI

// MARK: - ScheduleSection
//
// Recurrence is intentionally NOT handled here.
// TaskDetailView owns the complete recurrence UI so that Schedule does not
// contain a duplicate "Repeat" section.

struct ScheduleSection: View {

    @Bindable var task: TodoTask

    let notificationLeadTimeDays: Int
    let validationMessage: String?
    let showingDeleteDeadlineAlert: Binding<Bool>
    let saveTask: () -> Void
    let validateReminder: () -> Void

    var body: some View {
        Section("Schedule") {

            Toggle(
                "Set deadline",
                isOn: Binding(
                    get: { task.deadLine != nil },
                    set: { newValue in

                        if newValue {
                            task.deadLine = .now
                            task.snoozeUntil = nil
                            saveTask()

                        } else {
                            showingDeleteDeadlineAlert.wrappedValue = true
                        }
                    }
                )
            )

            if let deadline = task.deadLine {

                HStack {

                    VStack(alignment: .leading, spacing: 2) {

                        Text(
                            deadline
                                .formatted(.dateTime.weekday(.wide))
                                .capitalized
                        )
                        .padding(.horizontal, 20)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )

                        DatePicker(
                            "",
                            selection: Binding(
                                get: { task.deadLine ?? .now },
                                set: { newDate in
                                    task.deadLine = newDate
                                    task.snoozeUntil = nil
                                    saveTask()
                                }
                            ),
                            displayedComponents: [
                                .date,
                                .hourAndMinute
                            ]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .fixedSize(
                            horizontal: true,
                            vertical: false
                        )
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 25
                            )
                            .stroke(
                                deadline < .now
                                ? Color.red
                                : Color.clear,
                                lineWidth: 2
                            )
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {

                    ReminderScrubberControl(
                        reminderOffsetMinutes: Binding(
                            get: {
                                task.reminderOffsetMinutes
                            },
                            set: { newValue in
                                task.reminderOffsetMinutes = newValue
                                task.snoozeUntil = nil
                                validateReminder()
                                saveTask()
                            }
                        ),
                        notificationLeadTimeDays:
                            notificationLeadTimeDays
                    )

                    if let msg = validationMessage {
                        Text(msg)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.red)
                            .padding(.top, 8)
                    }
                }
            }

            Picker(
                "Priority",
                selection: Binding(
                    get: { task.priority },
                    set: { newValue in
                        task.priority = newValue
                        saveTask()
                    }
                )
            ) {
                ForEach(TaskPriority.allCases) { item in
                    if let icon = item.systemImage {
                        Label(
                            item.localizedTitle,
                            systemImage: icon
                        )
                        .tag(item)
                    } else {
                        Text(item.localizedTitle)
                            .tag(item)
                    }
                }
            }
            .pickerStyle(.menu)
        }
        .listRowBackground(
            Color(.systemBackground).opacity(0.3)
        )
        .onChange(of: task.deadLine) { _, newValue in
            validateReminder()

            if newValue == nil {
                task.recurrenceRule = nil
                task.recurrenceInterval = 1
                task.recurrenceEndDate = nil
                task.recurrenceCount = nil
                saveTask()
            }
        }
    }
}
