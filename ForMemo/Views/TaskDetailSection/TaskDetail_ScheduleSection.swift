import SwiftUI

// MARK: - scheduleSection aggiornato
 
struct ScheduleSection: View {
    @Bindable var task: TodoTask
    @Binding var selectedRecurrence: RecurrenceUI

    let notificationLeadTimeDays: Int
    let validationMessage: String?
    let showingDeleteDeadlineAlert: Binding<Bool>
    let saveTask: () -> Void
    let validateReminder: () -> Void

    var body: some View {
        Section("Schedule") {

            Toggle("Set deadline",
                   isOn: Binding(
                    get: { task.deadLine != nil },
                    set: { newValue in
                        if newValue {
                            task.deadLine = .now
                            task.snoozeUntil = nil
                        } else {
                            showingDeleteDeadlineAlert.wrappedValue = true
                        }
                    }
                   )
            )

            if let deadline = task.deadLine {

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deadline.formatted(.dateTime.weekday(.wide)).capitalized)
                            .padding(.horizontal, 20)

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
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .overlay {
                            RoundedRectangle(cornerRadius: 25)
                                .stroke((deadline < .now ? Color.red : Color.clear), lineWidth: 2)
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {

                    ReminderScrubberControl(
                        reminderOffsetMinutes: Binding(
                            get: { task.reminderOffsetMinutes },
                            set: { newValue in
                                task.reminderOffsetMinutes = newValue
                                task.snoozeUntil = nil
                                validateReminder()
                            }
                        ),
                        notificationLeadTimeDays: notificationLeadTimeDays
                    )

                    if let msg = validationMessage {
                        Text(msg)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.red)
                            .padding(.top, 8)
                    }
                }
                .onAppear { validateReminder() }
                .onChange(of: task.deadLine) { _, _ in validateReminder() }
            }

            if task.deadLine != nil {

                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                    Text("Repeat")
                    Spacer()
                    Picker("", selection: $selectedRecurrence) {
                        ForEach(RecurrenceUI.allCases) { option in
                            Text(LocalizedStringKey(option.localizationKey)).tag(option)
                        }
                    }
                    .labelsHidden()
                }
                .onChange(of: selectedRecurrence) { _, newValue in
                    if newValue == .none {
                        task.recurrenceRule = nil
                    } else {
                        task.recurrenceRule = newValue.rawValue
                        task.recurrenceInterval = 1
                    }
                    saveTask()
                }

                if selectedRecurrence != .none {
                    Stepper(
                        "",
                        value: Binding(
                            get: { task.recurrenceInterval },
                            set: { newValue in
                                task.recurrenceInterval = newValue
                                saveTask()
                            }
                        ),
                        in: 1...30
                    )
                }
            }

            Picker("Priority",
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
                        Label(item.localizedTitle, systemImage: icon)
                            .tag(item)
                    } else {
                        Text(item.localizedTitle)
                            .tag(item)
                    }
                }
            }
            .pickerStyle(.menu)
        }
        .listRowBackground(Color(.systemBackground).opacity(0.3))
    }
}



