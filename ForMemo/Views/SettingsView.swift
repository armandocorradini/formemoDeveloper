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
    @State private var showLocationIntroAlert = false

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
                                    showLocationIntroAlert = true
                                } else {
                                    locationRemindersEnabled = false
                                }
                            }
                        ))

                        if locationRemindersEnabled {
                            HStack(spacing: 12) {
                                Image(systemName: "location.circle")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                                Text("Trigger Distance")
                                    .tint(.primary)
                                Spacer()
                                Text("\(locationRadius) m")
                                    .foregroundStyle(.secondary)
                            }

                            Stepper(
                                "",
                                value: $locationRadius,
                                in: 100...500,
                                step: 50
                            )

                            Button {
                                soundPickerContext = .location
                                showSoundPicker = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "location.fill")
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
                        Text("To use location reminders, please allow Always access to your location in Settings.")
                    }
                    .alert("Location Reminders", isPresented: $showLocationIntroAlert) {
                        Button("Continue") {
                            let status = CLLocationManager().authorizationStatus

                            switch status {
                            case .notDetermined:
                                LocationReminderManager.shared.requestPermissionIfNeeded()

                            case .authorizedAlways:
                                locationRemindersEnabled = true

                            case .authorizedWhenInUse, .denied, .restricted:
                                showLocationPermissionAlert = true
                                locationRemindersEnabled = false

                            @unknown default:
                                locationRemindersEnabled = false
                            }
                        }
                        Button("Cancel", role: .cancel) {
                            locationRemindersEnabled = false
                        }
                    } message: {
                        Text("Get reminders when you arrive at a place.")
                    }

                    #if DEBUG
                    Button {
                        Task {
                            let center = UNUserNotificationCenter.current()
                            let requests = await center.pendingNotificationRequests()

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

                                let type: String = {
                                    if id.contains(".deadline") { return "⏱ DEADLINE" }
                                    if id.contains(".global") { return "🌍 GLOBAL" }
                                    if id.contains(".reminder") { return "🔔 REMINDER" }
                                    if id.contains(".snooze") { return "⏰ SNOOZE" }

                                    // 🔵 fallback detection (GLOBAL via title)
                                    if title.contains("Manca") || title.contains("days") {
                                        return "🌍 GLOBAL"
                                    }

                                    return "❓ UNKNOWN"
                                }()

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
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Notifications must be enabled in system settings to receive alerts and sounds.")
                }

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
                    
                } header: {
                    Text("Siri & Shortcuts")
                }
                
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
                } header: {
                    Text("Completed Tasks")
                } footer: {
                    Text("Attachments of completed tasks are automatically removed after the selected period. To-do tasks are not affected.")
                }
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
                } footer: {
                    Text("Items in Recently Deleted are permanently removed after the selected period. You can restore them before that.")
                }

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
                }
                .onAppear {
                    hasTestData = DebugTools.hasTestTasks(context: modelContext)
                    areTestTasksCompleted = DebugTools.areTestTasksCompleted(context: modelContext)
                }
#endif
            }
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
                }
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

// MARK: - FAQ View
struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}
struct FAQSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [FAQItem]
}

struct FAQView: View {
    
    @State private var searchText: String = ""
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - DATA
    private let sections: [FAQSection] = [

        // MARK: - GENERAL
        FAQSection(title: String(localized: "General"), items: [
            FAQItem(
                question: String(localized:"What features does this app offer?"),
                answer: String(localized:"ForMemo lets you create, organize, and manage tasks in a simple and intuitive way.\n\nYou can quickly create tasks, even with Siri. Attachments (photos, documents, audio) can be added directly within the app.\n\nWhen you set a due date, the app automatically schedules a notification: at the due time or in advance (from 1 to 7 days), based on your settings. You can also add a custom reminder and a location-based notification.\n\nWith reminders, you can choose when to be notified or, using Siri, let them be set automatically.\n\nYou can associate a location with a task and receive a notification when you arrive, with the option to open navigation apps to reach it.\n\nThe app offers customization options, light and dark mode, and different viewing layouts.\n\nYou can import tasks from Calendar, Apple Reminders, or CSV files, and export them to Calendar, CSV, or ICS format.\n\nAvailable in English, Italian, French, German, and Spanish.\n\nYour data stays on your device (or iCloud, if enabled). No account required and no tracking.")
            ),
            FAQItem(
                question: String(localized:"How does task creation work?"),
                answer: String(localized:"You can create tasks manually or with Siri. When using Siri, you are guided step by step: first what to add, then when, and finally which reminder to set. The app saves the task using the information you provide.")
            ),
            FAQItem(
                question: String(localized:"How are tags assigned automatically?"),
                answer: String(localized:"This feature applies only to tasks created with Siri. The app analyzes the task title using a multilingual keyword system. Each category has its own keywords, and the best match is applied automatically.")
            ),
            FAQItem(
                question: String(localized:"Does the app work offline?"),
                answer: String(localized:"Yes. All features work offline and data is stored locally on your device.")
            ),
            FAQItem(
                question: String(localized:"How do recurring tasks work?"),
                answer: String(localized:"You can set tasks to repeat daily, weekly, monthly, or yearly. When you complete a recurring task, the app automatically creates the next one based on the selected frequency, so you don’t need to recreate it manually. You can modify or stop recurrence at any time.")
            )
        ]),

        // MARK: - NOTIFICATIONS
        FAQSection(title: String(localized: "Notifications & Reminders"), items: [
            FAQItem(
                question: String(localized:"How are notifications managed?"),
                answer: String(localized:"The app schedules a notification at the task’s due time. In Settings, you can enable an automatic early notification (from 1 to 7 days before), applied to every task. You can also add a custom reminder for each task. You can also associate a location with a task and receive a notification when you arrive at that place. Only one notification is active at a time, and when it fires, the system automatically schedules the next one. Recurring tasks follow the same logic for each occurrence.")
            ),
            FAQItem(
                question: String(localized:"Why am I not receiving notifications?"),
                answer: String(localized:"Check system permissions, Focus modes, and app settings. Notifications are only scheduled when valid and allowed.")
            ),
            FAQItem(
                question: String(localized:"Why did a notification disappear?"),
                answer: String(localized:"It may no longer be relevant. If a task changes, old notifications are removed and replaced with updated ones if needed.")
            ),
            FAQItem(
                question: String(localized:"Why do I receive fewer notifications than expected?"),
                answer: String(localized:"The app avoids duplicates, past alerts, and night-time notifications to reduce noise.")
            ),
            // --- ADDED FAQItems ---
            FAQItem(
                question: String(localized:"Why are my notifications not working?"),
                answer: String(localized:"Make sure notifications are enabled in iOS Settings, Focus modes are not blocking alerts, and the task has a valid date or reminder. The app only schedules notifications when they are meaningful.")
            ),
            FAQItem(
                question: String(localized:"Why do notifications seem inconsistent?"),
                answer: String(localized:"Notifications are updated dynamically. If a task changes, old notifications are removed and replaced with new ones, which can make them appear different.")
            ),
            FAQItem(
                question: String(localized:"Why do I receive notifications at unexpected times?"),
                answer: String(localized:"Notification times depend on the task date, reminder settings, and system adjustments. The app avoids past or invalid times and schedules only valid future alerts.")
            )
        ]),

        // MARK: - SNOOZE
        FAQSection(title: String(localized: "Snooze"), items: [
            FAQItem(
                question: String(localized:"How does snooze work?"),
                answer: String(localized:"Snooze delays a notification. The current alert is removed and a new one is scheduled for the selected time.")
            ),
            FAQItem(
                question: String(localized:"Why does snooze seem to disappear?"),
                answer: String(localized:"Snooze is temporary. Once its time passes or the task changes, it is no longer shown.")
            ),
            FAQItem(
                question: String(localized:"Why did my snooze not trigger?"),
                answer: String(localized:"Snooze follows specific rules. For reminders and early notifications, snooze is ignored if it would go beyond the task’s deadline. For deadline notifications, snooze is always applied and triggers at the selected time. If a snooze seems missing, it was ignored to respect the deadline.")
            )
        ]),

        // MARK: - BADGE
        FAQSection(title: String(localized: "Badges & Indicators"), items: [
            FAQItem(
                question: String(localized:"How is the app badge calculated?"),
                answer: String(localized:"The badge shows only tasks that need attention, based on their timing and your settings.")
            ),
            FAQItem(
                question: String(localized:"Why does the badge change suddenly?"),
                answer: String(localized:"The badge is dynamic and updates based on time, deadlines, and task status.")
            ),
            FAQItem(
                question: String(localized:"What do badges in task rows mean?"),
                answer: String(localized:"They indicate the task status, for example if it is approaching its deadline, but only if a priority is set.")
            ),
            // --- ADDED FAQItems ---
            FAQItem(
                question: String(localized:"Why is the badge not updating?"),
                answer: String(localized:"The badge updates automatically based on task changes and time. If it seems incorrect, try reopening the app or checking your notification settings.")
            ),
            FAQItem(
                question: String(localized:"Why is the badge different from what I expect?"),
                answer: String(localized:"The badge shows the number of overdue tasks (tasks whose deadline has passed). Snoozing a notification does not remove a task from the badge, because the deadline does not change. The badge updates automatically when a task becomes due, even if the app is closed.")
            ),
            // --- BEGIN NEW FAQItems ---
            FAQItem(
                question: String(localized:"Why are some tasks highlighted in red?"),
                answer: String(localized:"Tasks with critical priority that are due today or overdue can be highlighted to draw your attention. This helps you quickly identify the most urgent tasks.")
            ),
            FAQItem(
                question: String(localized:"Can I disable the red highlight for critical tasks?"),
                answer: String(localized:"Yes. You can enable or disable this behavior in Customize > Visible elements by turning off the highlight option for critical tasks.")
            )
            // --- END NEW FAQItems ---
        ]),

        // MARK: - LOCATION
        FAQSection(title: String(localized: "Location Reminders"), items: [
            FAQItem(
                question: String(localized:"How do location reminders work?"),
                answer: String(localized:"The app reminds you when you arrive at a place. It focuses on the most relevant tasks based on distance and timing.")
            ),
            FAQItem(
                question: String(localized:"Why is a location task not monitored?"),
                answer: String(localized:"iOS limits monitored regions, so only top-priority tasks are active.")
            ),
            FAQItem(
                question: String(localized:"Why does a location reminder not trigger?"),
                answer: String(localized:"Check permissions, accuracy, and whether the task is actively monitored.")
            ),
            // --- ADDED FAQItem ---
            FAQItem(
                question: String(localized:"Why does location reminder not trigger when I arrive?"),
                answer: String(localized:"Location accuracy, permissions, or system limits may affect this. Make sure location access is set to Always and that the task is actively monitored.")
            )
        ]),

        // MARK: - SIRI & AUTOMATIONS
        FAQSection(title: String(localized: "Siri & Automations"), items: [
            FAQItem(
                question: String(localized:"What is “Add reminders automatically”?"),
                answer: String(localized:"When using Siri, if “Add reminders automatically” is enabled, Siri adds a reminder automatically based on the task. If disabled, Siri will ask you which reminder to set.")
            )
        ]),

        // MARK: - ATTACHMENTS / COMPLETED TASKS
        FAQSection(title: String(localized: "Completed Tasks & Attachments"), items: [
            FAQItem(
                question: String(localized:"Can I add attachments to tasks?"),
                answer: String(localized:"Yes. You can attach files, images, documents, and record audio.")
            ),
            FAQItem(
                question: String(localized:"Are attachments deleted automatically?"),
                answer: String(localized:"Only attachments of completed tasks are deleted automatically if the option is enabled in settings.")
            ),
            FAQItem(
                question: String(localized:"After how many days are attachments deleted?"),
                answer: String(localized:"You can choose after how many days attachments of completed tasks are automatically removed.")
            ),
            FAQItem(
                question: String(localized:"Can I delete all attachments at once?"),
                answer: String(localized:"Yes. You can manually delete all attachments of completed tasks from settings.")
            )
        ]),

        // MARK: - DATA
        FAQSection(title: String(localized: "Data & Recovery"), items: [
            FAQItem(
                question: String(localized:"What is Recently Deleted?"),
                answer: String(localized:"Deleted items are temporarily stored and can be restored before permanent removal.")
            ),
            FAQItem(
                question: String(localized:"Why do things change automatically?"),
                answer: String(localized:"The app reacts to time, task updates, and system events to keep everything consistent.")
            )
        ])
    ]
    
    // MARK: - FILTER
    
    private var filteredSections: [FAQSection] {
        if searchText.isEmpty { return sections }
        
        return sections.compactMap { section in
            let filteredItems = section.items.filter {
                $0.question.localizedCaseInsensitiveContains(searchText)
                || $0.answer.localizedCaseInsensitiveContains(searchText)
            }
            return filteredItems.isEmpty ? nil : FAQSection(title: section.title, items: filteredItems)
        }
    }
    
    // MARK: - HIGHLIGHT
    
    private func highlight(_ text: String) -> Text {
        guard !searchText.isEmpty else { return Text(text) }
        
        var attributed = AttributedString(text)
        
        if let range = attributed.range(of: searchText, options: .caseInsensitive) {
            attributed[range].foregroundColor = .blue
            attributed[range].font = .body.bold()
        }
        
        return Text(attributed)
    }
    
    // MARK: - UI
    var body: some View {
        List {
            ForEach(filteredSections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        DisclosureGroup {
                            Text(item.answer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        } label: {
                            highlight(item.question)
                                .font(.body)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: String(localized:"Search FAQ"))
        .navigationTitle(String(localized:"Help"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "Done")) {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - DETAIL VIEW

struct FAQDetailView: View {
    
    let item: FAQItem
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                Text(item.question)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(item.answer)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(String(localized:"FAQ"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
