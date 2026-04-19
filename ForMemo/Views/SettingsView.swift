import SwiftUI
import EventKit
import SwiftData
import CoreData


// MARK: - SettingsView
struct SettingsView: View {
    
    @Environment(\.modelContext) private var modelContext

    
    @AppStorage("navigationApp")
    private var navigationAppRaw: String = NavigationApp.appleMaps.rawValue
    @State private var showQuickGuide = false
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
    
    @State private var showDisclaimer = false
    
    @AppStorage("notificationSoundName")
    private var notificationSoundName: String = ""
    
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
                        Label("Navigation app", systemImage: "map")
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
                        }
                    }
                    .buttonStyle(.plain)
                    Toggle(
                        "Add reminders automatically",
                        isOn: $siriAutoReminderEnabled
                    )
                    
                    Toggle(
                        "Short confirmation",
                        isOn: $siriShortConfirmation
                    )
                    
                } header: {
                    Text("Siri & Shortcuts")
                } footer: {
                    Text(
                        "Siri replies briefly after creating a task."
                    )
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
                }
            }

            .fullScreenCover(isPresented: $showSoundPicker) {
                NotificationSoundPickerView()
            }
            .fullScreenCover(isPresented: $showQuickGuide) {
                // BackupView()
                AppQuickGuideView()
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
        
        let descriptor = FetchDescriptor<DeletedItem>()
        
        guard let items = try? modelContext.fetch(descriptor) else { return }
        
        for item in items {
            
            let deletedAt = item.deletedAt
            
            if deletedAt < cutoff {
                
                // 🔥 delete file if exists
                if let trashName = item.trashFileName,
                   let trashDir = TaskAttachment.trashDirectory {
                    
                    let url = trashDir.appendingPathComponent(trashName)
                    try? FileManager.default.removeItem(at: url)
                }
                
                modelContext.delete(item)
            }
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
