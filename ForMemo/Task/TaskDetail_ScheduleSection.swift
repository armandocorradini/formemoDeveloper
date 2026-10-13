import SwiftUI
import os
import AlarmKit

// MARK: - ScheduleSection
//
// Recurrence is intentionally NOT handled here.
// TaskDetailView owns the complete recurrence UI so that Schedule does not
// contain a duplicate "Repeat" section.

struct ScheduleSection: View {

    @Bindable var task: TodoTask
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingAlarmAuthorizationAlert = false
    @State private var alarmAuthorizationAvailable =
        ForMemoAlarmManager.shared.authorizationState() == .authorized

    let notificationLeadTimeDays: Int
    let validationMessage: String?
    let showingDeleteDeadlineAlert: Binding<Bool>
    let saveTask: () -> Void
    
    let saveAndWaitForScheduling: () async -> Void
    let isSynchronizing: Binding<Bool>
    
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

                    Toggle(
                        String(localized: "Alarm"),
                        isOn: Binding(
                            get: { task.alarmEnabled },
                            set: { newValue in
                                Task { @MainActor in
                                    if newValue {
                                        do {
                                            let isAuthorized = try await ForMemoAlarmManager.shared.requestAuthorization()
                                            alarmAuthorizationAvailable = isAuthorized
                                            guard isAuthorized else {
                                                showingAlarmAuthorizationAlert = true
                                                return
                                            }

                                            isSynchronizing.wrappedValue = true
                                            task.alarmEnabled = true
                                            await saveAndWaitForScheduling()
                                        } catch {
                                            alarmAuthorizationAvailable =
                                                ForMemoAlarmManager.shared.authorizationState() == .authorized
                                            AppLogger.notifications.error(
                                                "AlarmKit authorization failed: \(error.localizedDescription)"
                                            )
                                            showingAlarmAuthorizationAlert = true
                                        }
                                    } else {
                                        // Keep a configured alarm enabled if its permission was revoked.
                                        // The tap opens the explanation instead of deleting the saved setting.
                                        guard !(task.alarmEnabled && !alarmAuthorizationAvailable) else {
                                            showingAlarmAuthorizationAlert = true
                                            return
                                        }

                                        isSynchronizing.wrappedValue = true
                                        task.alarmEnabled = false
                                        await saveAndWaitForScheduling()
                                    }

                                    isSynchronizing.wrappedValue = false
                                }
                            }
                        )
                    )
                    .tint(task.alarmEnabled && !alarmAuthorizationAvailable ? .gray : .green)
                    .padding(.vertical, 10)
                    .alert(
                        "Alarm Unavailable",
                        isPresented: $showingAlarmAuthorizationAlert
                    ) {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("AlarmKit access is not enabled. Check your alarm permissions in Settings.")
                    }

                    Text(String(localized: "AlarmFootnote"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 5)

                    Divider()

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
                    .padding(.top, 5)

                    if let msg = validationMessage {
                        Text(msg)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.red)
                            .padding(.vertical, 10)
                    }
                }
            }

        }
        .listRowBackground(
            Color(.systemBackground).opacity(0.3)
        )
        .onAppear {
            alarmAuthorizationAvailable =
                ForMemoAlarmManager.shared.authorizationState() == .authorized
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            alarmAuthorizationAvailable =
                ForMemoAlarmManager.shared.authorizationState() == .authorized
        }
        .onChange(of: task.deadLine) { _, _ in
            validateReminder()
        }
    }
}
