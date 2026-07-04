import SwiftUI
import EventKit
import SwiftData
import CoreData
import CoreLocation


enum SoundPickerContext: Identifiable {
    case task
    case location

    var id: String {
        switch self {
        case .task:
            return "task"
        case .location:
            return "location"
        }
    }
}

struct SettingsView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self)
    private var settings

    
#if DEBUG
    @State private var hasTestData: Bool = false
    @State private var areTestTasksCompleted: Bool = false
    @State private var debugKeepGenerateMode: Bool = false
#endif
    @State private var showQuickGuide = false
    @State private var showFAQ = false
    @State private var showCustomizationView = false
    @State private var showDataManagement = false
    @State private var showOtherSettings = false
    @State private var showSiri = false
    @State private var showRecentlyDeleted = false
    @State private var showDeleteAllAlert = false


    @AppStorage("siriShortConfirmation")
    private var siriShortConfirmation: Bool = false

    
    private var autoDeleteCompletedAttachments: Bool {
        get { settings.autoDeleteCompletedAttachments }
        set { settings.autoDeleteCompletedAttachments = newValue }
    }

    private var attachmentRetentionDays: Int {
        get { settings.attachmentRetentionDays }
        set { settings.attachmentRetentionDays = newValue }
    }

    private var recentlyDeletedRetentionDays: Int {
        get { settings.recentlyDeletedRetentionDays }
        set { settings.recentlyDeletedRetentionDays = newValue }
    }
    
    @State private var isNotificationEnabled: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var soundPickerContext: SoundPickerContext?
    @State private var showDisclaimer = false
    @AppStorage("notificationSoundName")
    private var notificationSoundName: String = ""
    @AppStorage("locationNotificationSoundName")
    private var locationNotificationSoundName: String = ""



    private var locationRadius: Int {
        get { settings.locationRadius }
        set { settings.locationRadius = newValue }
    }
    
    
    private var backgroundColor1Hex: String {
        settings.backgroundColor1Hex
    }

    private var backgroundColor2Hex: String {
        settings.backgroundColor2Hex
    }
    
    @State private var showLocationPermissionAlert = false
    @State private var showImportReminders = false
    @State private var locationAuthorizationStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus

    func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isNotificationEnabled =
                settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            }
        }
    }
    var body: some View {
        let _ = backgroundColor1Hex
        let _ = backgroundColor2Hex
        let iconWidth: CGFloat = 28
        NavigationStack {
            ZStack {
                AppGlassBackground()
                List {
                    
                    // MARK: - Account
                    Section("Account and info") {
                        HStack(spacing: 12){
                            Image(systemName: "person.circle").foregroundStyle(.blue)
                                .frame(width: iconWidth)
                            Text("Signed in with Apple ID")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        Button {
                            showDisclaimer = true
                        } label: {
                            Label {
                                Text("Disclaimer")
                                    .tint(.primary)
                            } icon: {
                                Image(systemName: "exclamationmark.shield")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                            }
                        }
                        .sheet(isPresented: $showDisclaimer) {
                            DisclaimerView()
                        }
                        
                    }
                    .listRowBackground(Color(.systemBackground).opacity(0.3))
                    
                    Section("Help") {
                        Button {
                            showQuickGuide = true
                        } label: {
                            Label {
                                Text("Quick Guide")
                                    .tint(.primary)
                            } icon: {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                            }
                        }
                        Button {
                            showFAQ = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "text.book.closed")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                                Text("FAQ")
                                    .tint(.primary)
                            }
                        }
                    }
                    .listRowBackground(Color(.systemBackground).opacity(0.3))
                    
                    // MARK: - General
                    Section("General") {
                        Button {
                            showOtherSettings = true
                        } label: {
                            Label {
                                Text("General")
                                    .tint(.primary)
                            } icon: {
                                Image(systemName: "gear")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                            }
                        }
                        
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.shield")
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                                
                                Text("Permissions")
                                    .tint(.primary)
                            }
                        }
                        
                        Button {
                            openLanguageSettings()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "globe")
                                    .frame(width: iconWidth)
                                Text("Language")
                                    .tint(.primary)
                                Spacer()
                                Text(Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? "")
                                    .foregroundStyle(.blue).opacity(0.7)
                            }
                        }
                        NavigationLink {
                            BackgroundCustomizationView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "paintpalette")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                                
                                Text("Background")
                                    .foregroundStyle(.primary)
                            }
                        }

                        HStack(spacing: 12){
                            Image(systemName: "paintbrush")
                                .foregroundStyle(.blue)
                                .frame(width: iconWidth)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Theme")
                                
                                Text("Optimized for Dark Mode")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Picker(
                                "",
                                selection: Binding(
                                    get: { settings.selectedTheme },
                                    set: { settings.selectedTheme = $0 }
                                )
                            ) {
                                ForEach(AppTheme.allCases) { theme in
                                    Text(theme.description).tag(theme)
                                }
                            }
                            .foregroundStyle(.blue)
                            .pickerStyle(.menu)
                            .opacity(0.7)
                        }
                    }
                    .listRowBackground(Color(.systemBackground).opacity(0.3))
                    
                    // MARK: - Tasks & Appearance
                    Section("Tasks & Appearance") {
                        
                        Button {
                            showCustomizationView = true
                        } label: {
                            Label {
                                Text("Customize List")
                                    .tint(.primary)
                            } icon: {
                                Image(systemName: "list.bullet.circle")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                            }
                        }
                        
                        LabeledContent {
                            Picker(
                                "",
                                selection: Binding(
                                    get: { settings.navigationApp },
                                    set: { settings.navigationApp = $0 }
                                )
                            ) {
                                ForEach(NavigationApp.availableApps){ app in
                                    Text(app.title).tag(app)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .opacity(0.7)
                        } label: {
                            Label("Navigation app", systemImage: "iphone.badge.location")
                        }
                        
                        if locationAuthorizationStatus == .authorizedAlways
                            || locationAuthorizationStatus == .authorizedWhenInUse {
                            
                            Toggle(
                                isOn: Binding(
                                    get: { settings.showWeatherForecast },
                                    set: { newValue in

                                        settings.showWeatherForecast = newValue

                                        if newValue {
                                            Task {
                                                await WeatherManager.shared.refresh()
                                            }
                                        }
                                    }
                                )
                            ) {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Weather Forecast")
                                        
                                        Text("Weather data provided by Open-Meteo")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "cloud.sun")
                                        .foregroundStyle(.blue)
                                        .frame(width: iconWidth)
                                }
                            }
                        }
                    }
                    .listRowBackground(Color(.systemBackground).opacity(0.3))
                    
                    // MARK: - Notifications
                    Section {
                        
                        Button {
                            openNotificationSettings()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isNotificationEnabled ? "bell.badge" : "bell.badge.slash")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                                Text("Notifications")
                                    .tint(.primary)
                            }
                        }
                        
                        NavigationLink {
                            NotificationView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.badge")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                                
                                Text("Scheduled Notifications")
                                    .tint(.primary)
                            }
                        }
                        
                        Button {
                            soundPickerContext = .task
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                                
                                Text("Sound")
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                Text(notificationSoundName.isEmpty ? "Default" : notificationSoundName)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!isNotificationEnabled)
                        
                        
                        Group {
                            Toggle(
                                "Location Reminders",
                                isOn: Binding(
                                    get: { settings.locationRemindersEnabled },
                                    set: handleLocationReminderToggle
                                )
                            )
                            
                            
                            if settings.locationRemindersEnabled {
                                VStack(alignment: .leading, spacing: 8) {
                                    
                                    HStack(spacing: 12) {
                                        Image(systemName: "location.circle")
                                            .foregroundStyle(.blue)
                                            .frame(width: iconWidth)
                                        
                                        Text("Trigger Distance")
                                            .foregroundStyle(.primary)
                                    }
                                    HStack{
                                        Spacer()
                                        Text(String(localized:"\(locationRadius)     meters"))
                                        Stepper(
                                            "",
                                            value: Binding(
                                                get: { settings.locationRadius },
                                                set: { settings.locationRadius = $0 }
                                            ),
                                            in: 100...500,
                                            step: 50
                                        )
                                        .labelsHidden()
                                    }
                                }
                                Button {
                                    soundPickerContext = .location
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "sensor.tag.radiowaves.forward")
                                            .foregroundStyle(.blue)
                                            .frame(width: iconWidth)
                                        
                                        Text("Location sound")
                                            .foregroundStyle(.primary)
                                        
                                        Spacer()
                                        
                                        Text(locationNotificationSoundName.isEmpty ? "Default" : locationNotificationSoundName)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(!isNotificationEnabled)
                            }
                        }
                        .alert("Enable Location Access", isPresented: $showLocationPermissionAlert) {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("Location reminders require \"Always Allow\" location access. Please enable it in Settings.")
                        }
                        
#if DEBUG
                        Button {
                            Task {
                                let center = UNUserNotificationCenter.current()
                                let requests: [UNNotificationRequest] =
                                await center.pendingNotificationRequests()
                                
                                print("🔔 DEBUG NOTIFICATIONS START ------------------")
                                
                                var seenDates: [Date: [String]] = [:]
                                
                                for req in requests {
                                    
                                    let id = req.identifier
                                    let title = req.content.title
                                    let body = req.content.body
                                    
                                    var pipelineInfo: [String] = []
                                    
                                    if id.contains(".global") {
                                        pipelineInfo.append("Prossimo: GLOBAL")
                                        pipelineInfo.append("Poi: REMINDER → DEADLINE")
                                    } else if id.contains(".reminder") {
                                        pipelineInfo.append("Prossimo: REMINDER")
                                        pipelineInfo.append("Poi: DEADLINE")
                                    } else if id.contains(".deadline") {
                                        pipelineInfo.append("Prossimo: DEADLINE")
                                        pipelineInfo.append("GLOBAL non valida o passata")
                                    } else if id.contains(".snooze") {
                                        pipelineInfo.append("Prossimo: SNOOZE")
                                    }
                                    
                                    
                                    var triggerInfo = "unknown"
                                    
                                    if let t = req.trigger as? UNCalendarNotificationTrigger,
                                       let next = t.nextTriggerDate() {
                                        let formatter = DateFormatter()
                                        formatter.dateStyle = .medium
                                        formatter.timeStyle = .short
                                        triggerInfo = "📅 \(formatter.string(from: next))"
                                        seenDates[next, default: []].append(id)
                                    } else if let t = req.trigger as? UNTimeIntervalNotificationTrigger {
                                        triggerInfo = "⏱ in \(Int(t.timeInterval))s"
                                    } else if let t = req.trigger as? UNLocationNotificationTrigger {
                                        let region = t.region
                                        if let circular = region as? CLCircularRegion {
                                            let name = region.identifier.isEmpty ? "unknown" : region.identifier
                                            triggerInfo = "📍 \(name) | lat: \(circular.center.latitude), lon: \(circular.center.longitude), radius: \(Int(circular.radius))m"
                                        } else {
                                            let name = region.identifier.isEmpty ? "unknown" : region.identifier
                                            triggerInfo = "📍 \(name) | location trigger"
                                        }
                                    }
                                    
                                    var type = "❓ UNKNOWN"
                                    
                                    if id.contains(".deadline") {
                                        type = "⏰ DEADLINE"
                                    } else if id.contains(".global") {
                                        type = "⏱️ GLOBAL"
                                    } else if id.contains(".reminder") {
                                        type = "🔔 REMINDER"
                                    } else if id.contains(".snooze") {
                                        type = "⏲️ SNOOZE"
                                    } else if title.contains("Manca") || title.contains("days") {
                                        type = "⏱️ GLOBAL"
                                    }
                                    
                                    print("🔎 RAW ID:", id)
                                    
                                    print("""
ID: \(id)
Tipo: \(type)
Titolo: \(title)
Task: \(body)
Attivazione: \(triggerInfo)
➡️ Notifica attiva (PROSSIMA per il task)
📊 Pipeline:
\(pipelineInfo.joined(separator: "\n"))
------------------
""")
                                    print("ℹ️ Sistema: 1 notifica per task (le altre verranno schedulate dopo)")
                                }
                                
                                print("🔍 COLLISIONS ------------------")
                                for (date, ids) in seenDates where ids.count > 1 {
                                    print("⚠️ Same trigger date:", date)
                                    ids.forEach { print("   -> \($0)") }
                                }
                                print("🔍 END COLLISIONS --------------")
                                
                                print("🔔 DEBUG NOTIFICATIONS END --------------------")
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "waveform.path.ecg.magnifyingglass")
                                    .foregroundStyle(.red)
                                    .frame(width: iconWidth)
                                
                                Text("Debug Notifications")
                                    .foregroundStyle(.red)
                            }
                        }
#endif
                    }
                    header: {
                        Text("Notifications")
                    } footer: {
                        Text("Notifications must be enabled in system settings to receive alerts and sounds.")
                    }
                    .listRowBackground(Color(.systemBackground).opacity(0.3))
                    
                    Section {
                        
                        Button {
                            showSiri = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "waveform.circle")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                                Text("Use with Siri")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        Toggle(
                            "Add reminders automatically",
                            isOn: Binding(
                                get: { settings.siriAutoReminderEnabled },
                                set: { settings.siriAutoReminderEnabled = $0 }
                            )
                        )
                        
                        Toggle(isOn: $siriShortConfirmation) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Short confirmation")
                                Text("Siri replies briefly after creating a task.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                    }
                    header: {
                        Text("Siri & Shortcuts")
                    }
                    .listRowBackground(Color(.systemBackground).opacity(0.3))
                    
                    Section {
                        Toggle(
                            "Auto-delete attachments",
                            isOn: Binding(
                                get: { settings.autoDeleteCompletedAttachments },
                                set: { settings.autoDeleteCompletedAttachments = $0 }
                            )
                        )
                        
                        Stepper(
                            "Delete after \(attachmentRetentionDays) days",
                            value: Binding(
                                get: { settings.attachmentRetentionDays },
                                set: { settings.attachmentRetentionDays = $0 }
                            ),
                            in: 1...90,
                            step: 1
                        )
                        .disabled(!autoDeleteCompletedAttachments)
                        .foregroundStyle(autoDeleteCompletedAttachments ? .primary : .secondary)
                        
                        Button(role: .destructive) {
                            showDeleteAllAlert = true
                        } label: {
                            Text("Delete all attachments now")
                        }
                        .alert(
                            "Are you sure? This cannot be undone.",
                            isPresented: $showDeleteAllAlert
                        ) {
                            Button("Cancel", role: .cancel) { }
                            
                            Button("Delete", role: .destructive) {
                                Task {
                                    let context = modelContext
                                    try? AttachmentMaintenanceManager.shared
                                        .deleteAllCompletedTaskAttachments(context: context)
                                }
                            }
                        } message: {
                            Text("This permanently removes all attachments. This action cannot be undone.")
                        }
                    }
                    header: {
                        Text("Completed Tasks")
                    } footer: {
                        Text("Attachments of completed tasks are automatically removed after the selected period. To-do tasks are not affected.")
                    }
                    .listRowBackground(Color(.systemBackground).opacity(0.3))
                    Section {
                        
                        NavigationLink {
                            OverviewView()
                        } label: {
                            Label {
                                Text("Overview")
                                    .tint(.primary)
                            } icon: {
                                Image(systemName: "line.3.horizontal.button.angledtop.vertical.right")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                            }
                        }
                        
                        NavigationLink {
                            ImportExportSettingsView()
                        } label: {
                            Label {
                                Text("Import & Export")
                                    .tint(.primary)
                            } icon: {
                                Image(systemName: "arrow.left.arrow.right")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                            }
                        }

                        NavigationLink {
                            BackupRestoreView()
                        } label: {
                            Label {
                                Text("Backup & Restore")
                                    .tint(.primary)
                            } icon: {
                                Image(systemName: "externaldrive.badge.icloud")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                            }
                        }

                        Button {
                            showRecentlyDeleted = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                                Text("Recently Deleted")
                                    .tint(.primary)
                            }
                        }
                        Stepper(
                            "Delete after \(recentlyDeletedRetentionDays) days",
                            value: Binding(
                                get: { settings.recentlyDeletedRetentionDays },
                                set: { settings.recentlyDeletedRetentionDays = $0 }
                            ),
                            in: 1...90,
                            step: 1
                        )
                        .foregroundStyle(.secondary)
                    } header: {
                        Text("Data Management")
                    }
                    footer: {
                        Text("Items in Recently Deleted are permanently removed after the selected period. You can restore them before that.")
                    }
                    .listRowBackground(Color(.systemBackground).opacity(0.3))
                    

                    Section("Support") {
                        NavigationLink {
                            ExportDiagnosticsView()
                        } label: {
                            Label {
                                Text("Diagnostics")
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "waveform.path.ecg.magnifyingglass")
                                    .foregroundStyle(.orange)
                                    .frame(width: iconWidth)
                            }
                        }
                    }
                    .listRowBackground(Color(.systemBackground).opacity(0.3))
                    Section {
                        Button(role: .destructive) {
                            showDataManagement = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "trash.circle")
                                    .foregroundStyle(.red)
                                    .frame(width: iconWidth)
                                
                                Text("Erase all Data")
                                    .foregroundStyle(.red)
                            }
                        }
                    } footer: {
                        Text("This permanently deletes all tasks, attachments, and data from this device. This action cannot be undone.")
                    }
                    
                    
#if DEBUG
                    Section("Debug") {
                        Toggle("Always Generate", isOn: $debugKeepGenerateMode)
                        Button {
                            withAnimation(.none) {
                                if debugKeepGenerateMode {
                                    DebugTools.generateTasks(context: modelContext)
                                } else if !hasTestData {
                                    DebugTools.generateTasks(context: modelContext)
                                } else if !areTestTasksCompleted {
                                    DebugTools.completeTasks(context: modelContext)
                                } else {
                                    DebugTools.deleteTasks(context: modelContext)
                                }
                            }
                            hasTestData = DebugTools.hasTestTasks(context: modelContext)
                            areTestTasksCompleted = DebugTools.areTestTasksCompleted(context: modelContext)
                        } label: {
                            if debugKeepGenerateMode {
                                Text("Genera")
                            } else if !hasTestData {
                                Text("Genera")
                            } else if !areTestTasksCompleted {
                                Text("Completa")
                            } else {
                                Text("Elimina")
                            }
                        }
                        Button(role: .destructive) {
                            DebugTools.resetPreferences()
                            
                            print("🧹 Preferences reset")
                            
                            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                exit(0)
                            }
                        } label: {
                            Text("Reset Preferences")
                                .foregroundStyle(.red)
                        }
                    }
                    .listRowBackground(Color(.systemBackground).opacity(0.3))
                    .onAppear {
                        hasTestData = DebugTools.hasTestTasks(context: modelContext)
                        areTestTasksCompleted = DebugTools.areTestTasksCompleted(context: modelContext)
                    }
#endif
                }
            }

            .contentMargins(.bottom, 70, for: .scrollContent)

            .scrollContentBackground(.hidden)
            .task {
                cleanupRecentlyDeleted()
                checkNotificationStatus()
            }
            .navigationTitle("Settings")

            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                checkNotificationStatus()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    checkNotificationStatus()
                    cleanupRecentlyDeleted()
                    syncLocationPermission()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .locationPermissionChanged
                )
            ) { _ in
                syncLocationPermission()
            }
            .fullScreenCover(item: $soundPickerContext) { context in
                NotificationSoundPickerView(context: context)
            }
            .fullScreenCover(isPresented: $showQuickGuide) {
                AppQuickGuideView()
            }
            .fullScreenCover(isPresented: $showFAQ) {
                NavigationStack {
                    FAQView()
                }
            }
            .fullScreenCover(isPresented: $showDataManagement) {
                ResetAppView()
            }
            .fullScreenCover(isPresented: $showCustomizationView) {
                NavigationStack {TaskListAppearanceView()}
            }
            .fullScreenCover(isPresented: $showOtherSettings) {
                NavigationStack {
                    OtherSettingsView()
                }
            }
            .fullScreenCover(isPresented: $showSiri) {
                NavigationStack {
                    ShortList()
                }
            }
            .fullScreenCover(isPresented: $showImportReminders) {
                RemindersImportView()
            }
            .fullScreenCover(isPresented: $showRecentlyDeleted) {
                NavigationStack {
                    RecentlyDeletedView()
                }
            }
            .id(backgroundColor1Hex + backgroundColor2Hex)
        }
        
    }
    // MARK: - Helpers
    private func syncLocationPermission() {
        let status = CLLocationManager().authorizationStatus

        locationAuthorizationStatus = status

        let hasPermission =
            status == .authorizedAlways
        settings.locationRemindersEnabled = hasPermission
    }
    
    private func handleLocationReminderToggle(_ newValue: Bool) {

        if !newValue {
            settings.locationRemindersEnabled = false
            return
        }

        let status = CLLocationManager().authorizationStatus

        switch status {

        case .authorizedAlways:
            settings.locationRemindersEnabled = true

        case .notDetermined:
            LocationReminderManager.shared.requestPermissionIfNeeded()
            settings.locationRemindersEnabled = false

        case .authorizedWhenInUse:
            showLocationPermissionAlert = true
            settings.locationRemindersEnabled = false

        case .denied, .restricted:
            showLocationPermissionAlert = true
            settings.locationRemindersEnabled = false

        @unknown default:
            settings.locationRemindersEnabled = false
        }
    }
    
    
    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    private func openLanguageSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    @MainActor
    private func cleanupRecentlyDeleted() {
        DebugLog.writeAttachmentEvent("")
        DebugLog.writeAttachmentEvent("════════════════════════════════════")
        DebugLog.writeAttachmentEvent("SETTINGS CLEANUP START")
        Thread.callStackSymbols.forEach {
            DebugLog.writeAttachmentEvent($0)
        }
        
        
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -recentlyDeletedRetentionDays,
            to: .now
        ) else {
            return
        }
        
        DebugLog.writeAttachmentEvent("Retention: \(recentlyDeletedRetentionDays)")
        DebugLog.writeAttachmentEvent("Cutoff: \(cutoff)")
        
        let descriptor = FetchDescriptor<DeletedItem>(
            predicate: #Predicate { $0.deletedAt <= cutoff }
        )
        guard let items = try? modelContext.fetch(descriptor) else { return }
        
        DebugLog.writeAttachmentEvent("Deleted items found: \(items.count)")
        
        for item in items {
            if let trashName = item.trashFileName,
               let trashDir = TaskAttachment.trashDirectory {
                let url = trashDir.appendingPathComponent(trashName)
                
                let fm = FileManager.default

                DebugLog.writeAttachmentEvent("DELETE TRASH FILE")
                DebugLog.writeAttachmentEvent("Trash name: \(trashName)")
                DebugLog.writeAttachmentEvent("Path: \(url.path)")
                DebugLog.writeAttachmentEvent("Exists: \(fm.fileExists(atPath: url.path))")
                
                
                try? FileManager.default.removeItem(at: url)
            }
            modelContext.delete(item)
        }
        try? modelContext.save()
    }
}

// MARK: - App Theme
enum AppTheme: Int, CaseIterable, Identifiable {
    case system = 0, light = 1, dark = 2
    var id: Int { rawValue }
    var description: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }
}

extension AppTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}


