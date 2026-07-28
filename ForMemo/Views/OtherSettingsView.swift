import SwiftUI
import SwiftData

struct OtherSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Environment(AppSettings.self)
    private var settings

    @AppStorage("badgeIncludeExpired") private var badgeIncludeExpired: Bool = true
    @AppStorage("badgeIncludeExpiredMigrated") private var badgeIncludeExpiredMigrated: Bool = false
    
    @State private var path = NavigationPath()
    
    @State private var showShort = false
    
    var body: some View {
        ZStack {
            AppGlassBackground()

            Form {
                Section(
                    header: Text(String(localized: "Open at launch"))
                ) {
                    
                    Picker(
                        String(localized: "View"),
                        selection: Binding(
                            get: { settings.startupTab },
                            set: { settings.startupTab = $0 }
                        )
                    ) {
                        Text("Automatic")
                            .tag(-1)

                        Text("Dashboard")
                            .tag(10)

                        Text(String(localized: "List"))
                            .tag(1)

                        Text(String(localized: "\(settings.taskWeekDays) days"))
                            .tag(4)

                        Text(String(localized: "Calendar"))
                            .tag(3)

                        Text(String(localized: "Wallet"))
                            .tag(6)

                        Text("Trips")
                            .tag(7)

                        Text(String(localized: "Documents"))
                            .tag(8)
                    }
                    .pickerStyle(.navigationLink)
                  
                }
                
                
                
                Section(
                    header: Text(String(localized: "Notification and badge time"))
                ) {
                    Picker(
                        "Notify global",
                        selection: Binding(
                            get: { settings.notificationLeadTimeDays },
                            set: { newValue in

                                settings.notificationLeadTimeDays = newValue

                                if newValue == -1 {
                                    settings.badgeMode = 0
                                }

                                NotificationManager.shared.refresh(force: true)
                            }
                        )
                    ) {
                        ForEach(NotificationLeadTime.allCases) { value in
                            Text(value.title).tag(value.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    
                  Text(
                    settings.notificationLeadTimeDays == -1
                        ? String(localized: "You’ll receive a notification only at the exact time of the task. Since global notifications are disabled, the app badge updates only when tasks become overdue.")
                        : String(localized: "You’ll receive a notification \(settings.notificationLeadTimeDays) day(s) before the deadline and another at the time it’s due. You can choose below whether the app badge updates at the deadline or already with the global notification.")
                    )
                    .foregroundStyle(.secondary)
                    .font(.footnote)

                    Picker(
                        "Badge updates",
                        selection: Binding(
                            get: { settings.badgeMode },
                            set: { settings.badgeMode = $0 }
                        )
                    ) {

                        Text("At deadline")
                            .tag(0)

                        Text("With global notification")
                            .tag(1)
                    }
                    .pickerStyle(.menu)
                    .disabled(settings.notificationLeadTimeDays == -1)
                    
                    Toggle(
                        "Show app badge",
                        isOn: Binding(
                            get: { settings.showAppBadge },
                            set: { settings.showAppBadge = $0 }
                        )
                    )

                }
                Section("Deletion") {
                    
                    Toggle(
                        "Confirm task deletion",
                        isOn: Binding(
                            get: { settings.confirmTaskDeletion },
                            set: { settings.confirmTaskDeletion = $0 }
                        )
                    )
                }
                
                Section("Recurring Tasks") {

                    Toggle(
                        "Keep history of recurring tasks",
                        isOn: Binding(
                            get: { settings.keepRecurringTaskHistory },
                            set: { settings.keepRecurringTaskHistory = $0 }
                        )
                    )

                    Text(
                        "When enabled, completing a recurring task saves the completed occurrence and automatically schedules the next one. When disabled, the task is simply moved to the next occurrence without creating a completed record."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                
            }
            .onChange(of: badgeIncludeExpired) { oldValue, newValue in
                // Questa logica viene eseguita non appena il valore cambia
                NotificationManager.shared.refresh(force: true)
            }
            .onChange(of: settings.showAppBadge) { _, _ in
                NotificationManager.shared.refresh(force: true)
            }
            .onChange(of: settings.notificationLeadTimeDays) { _, newValue in

                CloudSettingsSync.shared
                    .syncNotificationLeadTimeDays(newValue)

                NotificationManager.shared.refresh(force: true)
            }
            .onChange(of: settings.badgeMode) { _, newValue in

                CloudSettingsSync.shared
                    .syncBadgeMode(newValue)

                UNUserNotificationCenter.current()
                    .removeAllPendingNotificationRequests()

                NotificationManager.shared.refresh(force: true)
            }
            .navigationTitle("")
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.primary)
                            .font(.title2)
                    }
                }
            }
        }
        .onAppear {
            // 🔄 Migration: old behavior disabled expired tasks in badge
            if !badgeIncludeExpiredMigrated {
                if badgeIncludeExpired == false {
                    badgeIncludeExpired = true
                }
                badgeIncludeExpiredMigrated = true
            }
        }
    }
}
