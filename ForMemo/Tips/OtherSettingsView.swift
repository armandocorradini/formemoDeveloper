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

    private func startupTabTitle(for tag: Int) -> String {
        if tag == -1 {
            return String(localized: "Automatic")
        }
        if let tab = AppTab(rawValue: tag) {
            return tab.title(using: settings)
        }
        return String(localized: "Tab")
    }

    var body: some View {
        ZStack {
            AppGlassBackground()

            Form {
                Section(
                    header: Text(String(localized: "Open at launch"))
                ) {
                    
                    NavigationLink {
                        StartupTabSelectionView()
                    } label: {
                        HStack {
                            Text(String(localized: "View"))
                            Spacer()
                            Text(startupTabTitle(for: settings.startupTab))
                                .foregroundStyle(.secondary)
                        }
                    }
                  
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


private struct StartupTabSelectionView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var showHiddenStartupTabAlert = false
    @State private var hiddenStartupTabName = ""
    @State private var showAutomaticUnavailableAlert = false

    var body: some View {
        List {
            Section {
                Button {
                    guard settings.showDashboardTab && settings.showTasksTab else {
                        showAutomaticUnavailableAlert = true
                        return
                    }
                    settings.startupTab = -1
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        startupOptionLabel("Automatic", tag: -1)
                        Text("Dashboard if activities exist; otherwise Activities.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(
                    settings.showDashboardTab && settings.showTasksTab
                        ? Color.primary
                        : Color.secondary
                )
                .buttonStyle(.plain)

                startupOption("Dashboard", tag: AppTab.dashboard.rawValue)
                startupOption(String(localized: "list_tab"), tag: AppTab.tasks.rawValue)
                startupOption(String(localized: "\(settings.taskWeekDays) days"), tag: AppTab.today.rawValue)
                startupOption(String(localized: "Calendar"), tag: AppTab.calendar.rawValue)
                startupOption(String(localized: "Day"), tag: AppTab.day.rawValue)
                startupOption(String(localized: "Wallet"), tag: AppTab.wallet.rawValue)
                startupOption("Checklists", tag: AppTab.trips.rawValue)
                startupOption(String(localized: "Documents"), tag: AppTab.documents.rawValue)
                startupOption(String(localized: "Notes"), tag: AppTab.notes.rawValue)
                startupOption(String(localized: "Map"), tag: AppTab.map.rawValue)
                startupOption(String(localized: "Weather Forecast"), tag: AppTab.forecast.rawValue)
                startupOption(String(localized: "Vault"), tag: AppTab.vault.rawValue)
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppGlassBackground() }
        .navigationTitle("Open at launch")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Tab Is Hidden", isPresented: $showHiddenStartupTabAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(hiddenStartupTabName) is hidden. Make it visible in Tab Visibility before setting it as the startup tab.")
        }
        .alert("Automatic Startup Unavailable", isPresented: $showAutomaticUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Automatic startup requires both Dashboard and List to be visible. Open Tab Visibility and make both tabs visible first.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TabVisibilitySettingsView()
                } label: {
                    Image(systemName: "square.on.square.dashed")
                }
                .accessibilityLabel(Text("Choose Visible Tabs"))
            }
        }
    }

    private func startupOption(_ title: String, tag: Int) -> some View {
        Button {
            guard isVisible(tag) else {
                hiddenStartupTabName = title
                showHiddenStartupTabAlert = true
                return
            }
            settings.startupTab = tag
            dismiss()
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(isVisible(tag) ? Color.primary : Color.secondary)
                Spacer()
                if settings.startupTab == tag {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func startupOptionLabel(_ title: String, tag: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            if settings.startupTab == tag {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
    }

    private func isVisible(_ tag: Int) -> Bool {
        guard let tab = AppTab(rawValue: tag) else { return true }
        return tab.isVisible(using: settings)
    }
}
