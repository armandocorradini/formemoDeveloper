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

                VStack(alignment: .leading, spacing: 10) {

                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.blue)

                        Text(String(localized: "Repeat"))
                        
                        if selectedRecurrence == .none {
                            Spacer()

                            Picker("", selection: $selectedRecurrence) {
                                ForEach(RecurrenceUI.allCases) { option in
                                    Text({
                                        let plural = task.recurrenceInterval > 1

                                        switch option {
                                        case .daily:
                                            return plural
                                            ? String(localized: "days")
                                            : String(localized: "day")

                                        case .weekly:
                                            return plural
                                            ? String(localized: "weeks")
                                            : String(localized: "week")

                                        case .monthly:
                                            return plural
                                            ? String(localized: "months")
                                            : String(localized: "month")

                                        case .yearly:
                                            return plural
                                            ? String(localized: "years")
                                            : String(localized: "year")

                                        case .none:
                                            return String(localized: "recurrence.none")
                                        }
                                    }())
                                    .tag(option)
                                }
                            }
                            .labelsHidden()
                            .fixedSize(horizontal: true, vertical: false)
                            .tint(.secondary)
                        }
                    }

                    HStack(spacing: 18) {

                        if selectedRecurrence != .none {

                            Text(String(localized: "Every"))
                                .foregroundStyle(.primary)
                                .padding(.trailing, 2)

                            Menu {
                                ForEach(1...365, id: \.self) { value in
                                    Button("\(value)") {
                                        task.recurrenceInterval = value
                                        saveTask()
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if task.recurrenceInterval != 1 {
                                        Text("\(task.recurrenceInterval)")
                                            .monospacedDigit()
                                            .foregroundStyle(.primary)
                                    }

                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                                .tint(.primary)
                            }
                            .tint(.primary)
                        }

                        if selectedRecurrence != .none {
                            Picker("", selection: $selectedRecurrence) {
                                ForEach(RecurrenceUI.allCases) { option in
                                    Text({
                                        let plural = task.recurrenceInterval > 1

                                        switch option {
                                        case .daily:
                                            return plural
                                            ? String(localized: "days")
                                            : String(localized: "day")

                                        case .weekly:
                                            return plural
                                            ? String(localized: "weeks")
                                            : String(localized: "week")

                                        case .monthly:
                                            return plural
                                            ? String(localized: "months")
                                            : String(localized: "month")

                                        case .yearly:
                                            return plural
                                            ? String(localized: "years")
                                            : String(localized: "year")

                                        case .none:
                                            return String(localized: "recurrence.none")
                                        }
                                    }())
                                    .tag(option)
                                }
                            }
                            .labelsHidden()
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                            .padding(.leading, 6)
                            .tint(.primary)
                        }
                    }
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
