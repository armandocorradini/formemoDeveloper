import SwiftUI
import EventKit
import SwiftData
import CoreData
import CoreLocation


// MARK: - SoundPickerContext
enum SoundPickerContext {
    case task
    case location
}

// MARK: - SettingsView
struct SettingsView: View {
    
    @Environment(\.modelContext) private var modelContext

#if DEBUG
    @State private var hasTestData: Bool = false
    @State private var areTestTasksCompleted: Bool = false
#endif

    
    @AppStorage("navigationApp")
    private var navigationAppRaw: String = NavigationApp.appleMaps.rawValue
    @State private var showQuickGuide = false
    @State private var showFAQ = false
    @State private var showCustomizationView = false
    @State private var showDataManagement = false
    @State private var showOtherSettings = false
    @State private var showSiri = false
    @State private var showRecentlyDeleted = false

    @State private var showDeleteAllAlert = false
    
    private var navigationApp: NavigationApp {
        NavigationApp(rawValue: navigationAppRaw) ?? .appleMaps
    }
    
    @AppStorage("selectedTheme") private var selectedTheme: AppTheme = .system
    @AppStorage("startupTab") private var startupTab: Int = 1
    
    @AppStorage("autoDeleteCompletedAttachments")
    private var autoDeleteCompletedAttachments: Bool = false
    @AppStorage("siriShortConfirmation")
    private var siriShortConfirmation: Bool = false
    
    @AppStorage("siriAutoReminderEnabled")
    private var siriAutoReminderEnabled: Bool = true
    
    @AppStorage("attachmentRetentionDays")
    private var attachmentRetentionDays: Int = 30

    @AppStorage("recentlyDeletedRetentionDays")
    private var recentlyDeletedRetentionDays: Int = 30
    
    @State private var isNotificationEnabled: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var showSoundPicker = false
    @State private var soundPickerContext: SoundPickerContext = .task
    
    @State private var showDisclaimer = false
    
    @AppStorage("notificationSoundName")
    private var notificationSoundName: String = ""

    @AppStorage("locationNotificationSoundName")
    private var locationNotificationSoundName: String = ""
    
    @AppStorage("locationRemindersEnabled")
    private var locationRemindersEnabled: Bool = false
    @AppStorage("locationRadius")
    private var locationRadius: Int = 150

    @State private var showLocationPermissionAlert = false

    @State private var showImportReminders = false
    @State private var showCalendarImport = false
    @State private var showCSV = false
    @State private var showCalendarSelection = false

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
        
        let iconWidth: CGFloat = 28
        NavigationStack {
            List {
                
                // MARK: - Account
                Section("Account and info") {
                    HStack(spacing: 12){
                        Image(systemName: "person.circle").foregroundStyle(.blue)
                            .frame(width: iconWidth)
                        Text("Signed in with Apple ID")
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
                        // Usiamo il componente Label per separare i colori
                        HStack(spacing: 12) {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.blue) //
                                .frame(width: iconWidth)
                            
                            Text("Quick Guide")
                                .tint(.primary)
                                .padding(.leading,6)
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
                                .padding(.leading,6)
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

                    
                    HStack(spacing: 12){
                        Image(systemName: "paintbrush").foregroundStyle(.blue)
                            .frame(width: iconWidth)
                        Text("Theme")
                        Spacer()
                        Picker("", selection: $selectedTheme) {
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
                            Text("Customize")
                                .tint(.primary)
                        } icon: {
                            Image(systemName: "list.bullet.circle")
                                .foregroundStyle(.blue)
                                .frame(width: iconWidth)
                        }
                    }
                    
                    LabeledContent {
                        Picker("", selection: $navigationAppRaw) {
                            ForEach(NavigationApp.allCases) { app in
                                Text(app.title).tag(app.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .opacity(0.7)
                    } label: {
                        Label("Navigation app", systemImage: "iphone.badge.location")
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
                        showSoundPicker = true
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
                        Toggle("Location Reminders", isOn: Binding(
                            get: { locationRemindersEnabled },
                            set: { newValue in
                                if newValue {

                                    let status = CLLocationManager().authorizationStatus

                                    switch status {

                                    case .authorizedAlways:
                                        locationRemindersEnabled = true

                                    case .notDetermined:
                                        LocationReminderManager.shared.requestPermissionIfNeeded()
                                        locationRemindersEnabled = false

                                    case .authorizedWhenInUse:

                                        showLocationPermissionAlert = true
                                        locationRemindersEnabled = false

                                    case .denied, .restricted:
                                        showLocationPermissionAlert = true
                                        locationRemindersEnabled = false

                                    @unknown default:
                                        locationRemindersEnabled = false
                                    }

                                } else {
                                    locationRemindersEnabled = false
                                }
                            }
                        ))

                        if locationRemindersEnabled {
                            VStack(alignment: .leading, spacing: 8) {
                                
                                HStack(spacing: 12) {
                                    Image(systemName: "location.circle")
                                        .foregroundStyle(.blue)
                                        .frame(width: iconWidth)
                                    
                                    Text("Trigger Distance")
                                        .foregroundStyle(.primary)
                                    
                                    
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                HStack{
                                    Spacer()
                                    
                                    Text(String(localized:"\(locationRadius)     meters"))
//                                        .padding(.trailing,4)
                                    Stepper(
                                        "",
                                        value: $locationRadius,
                                        in: 100...500,
                                        step: 50
                                    )
                                    .labelsHidden()
                                }
                            }
                            Button {
                                soundPickerContext = .location
                                showSoundPicker = true
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
                            Image(systemName: "ladybug")
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
                                .padding(.leading, 6)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Toggle(
                        "Add reminders automatically",
                        isOn: $siriAutoReminderEnabled
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
                        isOn: $autoDeleteCompletedAttachments
                    )
                    
                    Stepper(
                        "Delete after \(attachmentRetentionDays) days",
                        value: $attachmentRetentionDays,
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
                    Button {
                        showRecentlyDeleted = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.blue)
                                .frame(width: iconWidth)
                            
                            Text("Recently Deleted")
                                .tint(.primary)
                                .padding(.leading, 6)
                        }
                    }
                    Stepper(
                        "Delete after \(recentlyDeletedRetentionDays) days",
                        value: $recentlyDeletedRetentionDays,
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
                    Button {
                        withAnimation(.none) {
                            if !hasTestData {
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
                        if !hasTestData {
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
                        Text("Reset Preferences Reset PreferencesReset PreferencesReset PreferencesReset PreferencesReset Preferences")
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
            .contentMargins(.bottom, 55, for: .scrollContent)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [backColor1, backColor2],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    
                    MeshGradient(
                        width: 3,
                        height: 3,
                        points: [
                            [0, 0], [0.5, 0], [1, 0],
                            [0, 0.5], [0.5, 0.5], [1, 0.5],
                            [0, 1], [0.5, 1], [1, 1]
                        ],
                        colors: [
                            .cyan.opacity(0.1), .blue.opacity(0.05), .blue.opacity(0.1),
                            .clear, .clear, .clear,
                            .blue.opacity(0.1), .clear, .cyan.opacity(0.1)
                        ]
                    )
                    .opacity(0.3)
                    .ignoresSafeArea()
                    
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                }
            }
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

            .fullScreenCover(isPresented: $showSoundPicker) {
                NotificationSoundPickerView(context: soundPickerContext)
            }
            .fullScreenCover(isPresented: $showQuickGuide) {
                // BackupView()
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
        }
    }
    // MARK: - Helpers

    private func syncLocationPermission() {

        let hasPermission =
            CLLocationManager().authorizationStatus == .authorizedAlways

        locationRemindersEnabled = hasPermission
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    private func openLanguageSettings() {
        // iOS non permette aprire direttamente la lingua,
        // quindi apriamo le impostazioni generali
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    @MainActor
    private func cleanupRecentlyDeleted() {
        
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -recentlyDeletedRetentionDays,
            to: .now
        )!
        
        let descriptor = FetchDescriptor<DeletedItem>(
            predicate: #Predicate { $0.deletedAt <= cutoff }
        )
        
        guard let items = try? modelContext.fetch(descriptor) else { return }
        
        for item in items {
            
            // 🔥 delete file if exists
            if let trashName = item.trashFileName,
               let trashDir = TaskAttachment.trashDirectory {
                
                let url = trashDir.appendingPathComponent(trashName)
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

@MainActor
func createTestReminder() async {
    
    do {
        let access = RemindersAccess()
        try await access.requestAccess()
        
        let store = access.getStore()
        
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Test \(appName)"
        
        // 🔥 usa calendario dedicato
        reminder.calendar = getOrCreateForMemoCalendar(store: store)
        
        try store.save(reminder, commit: true)
        
        print("✅ Reminder created in \(appName) list")
        
    } catch {
        print("❌ Error:", error.localizedDescription)
    }
}

func getOrCreateForMemoCalendar(store: EKEventStore) -> EKCalendar {
    
    let calendars = store.calendars(for: .reminder)
    
    if let existing = calendars.first(where: { $0.title == "\(appName)" }) {
        UserDefaults.standard.set(existing.calendarIdentifier, forKey: "ForMemoCalendarID")
        return existing
    }
    
    let calendar = EKCalendar(for: .reminder, eventStore: store)
    calendar.title = "\(appName)"
    calendar.source = store.defaultCalendarForNewReminders()?.source
    
    try? store.saveCalendar(calendar, commit: true)
    
    UserDefaults.standard.set(calendar.calendarIdentifier, forKey: "ForMemoCalendarID")
    
    return calendar
}

struct CalendarPickerLoaderView: View {
    
    @Binding var calendars: [EKCalendar]
    let onSelect: (EKCalendar) -> Void
    
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            
            Group {
                if isLoading {
                    ProgressView("Loading calendars...")
                } else {
                    CalendarPickerView(
                        calendars: calendars,
                        onSelect: onSelect
                    )
                }
            }
            .task {
                await load()
            }
        }
    }
    
    private func load() async {
        
        let engine = CalendarExportEngine()
        
        do {
            try await engine.requestAccess()
            
            let all = engine.availableCalendars()
            
            await MainActor.run {
                calendars = all
                isLoading = false
            }
            
        } catch {
            await MainActor.run {
                isLoading = false
            }
        }
    }
}
