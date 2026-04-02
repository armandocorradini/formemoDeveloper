import SwiftUI
import SwiftData
import UserNotifications

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
    
    @AppStorage("attachmentRetentionDays")
    private var attachmentRetentionDays: Int = 30
    
    @State private var isNotificationEnabled: Bool = false
    
    @State private var showSoundPicker = false
    
    @State private var showDisclaimer = false
    
    @AppStorage("notificationSoundName")
    private var notificationSoundName: String = ""
    
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
            
            ZStack {
                // 1. IL GRADIENTE (Sotto a tutto)
                LinearGradient(colors: [backColor1, backColor2],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                .ignoresSafeArea()
                
                // 2. IL MATERIAL (Effetto vetro)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                
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
                    
                    
                    // MARK: - Preferences
                    Section("Preferences") {
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
                                    Text(theme.description).tag(theme)  //
                                    
                                }
                            }
                            .foregroundStyle(.blue)
                            .pickerStyle(.menu)
                            .opacity(0.7)
                        }
                        Button {
                            showCustomizationView = true
                        } label: {
                            Label {
                                Text("Customize list")
                                    .tint(.primary)
                            } icon: {
                                Image(systemName: "list.bullet.circle")//app.badge")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                            }
                        }
                        Button {
                            openNotificationSettings()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isNotificationEnabled ? "bell.badge" : "bell.badge.slash").tint(.blue)
                                    .frame(width: iconWidth)
                                Text("Notifications & Reminders").tint(.primary)
                            }
                        }
                        //                        .listRowSeparator(.hidden)
                        Button {
                            showSoundPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isNotificationEnabled ? "music.note" : "music.note.slash")
                                    .foregroundStyle(.blue)
                                    .frame(width: iconWidth)
                                //                                    .frame(width: 24)
                                // Testo principale sempre leggibile
                                Text("Sound")
                                    .foregroundStyle(isNotificationEnabled ? .primary : .secondary)
                                    .opacity(0.7)
                                
                                Spacer()
                                
                                // Valore a destra
                                Text(notificationSoundName.isEmpty ? "Default" : notificationSoundName)
                                    .foregroundStyle(isNotificationEnabled ? .primary : .secondary)
                                    .opacity(0.7)
                            }
                        }
                        
                        .buttonStyle(.plain)
                        
                        .disabled(!isNotificationEnabled)
                        
                        .onAppear {
                            UNUserNotificationCenter.current().getNotificationSettings { settings in
                                Task { @MainActor in
                                    self.isNotificationEnabled =
                                    settings.authorizationStatus == .authorized
                                    || settings.authorizationStatus == .provisional
                                }
                            }
                        }
                        // 2. Fondamentale: controlla ogni volta che torni dalle Impostazioni (o riapri l'app)
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                            checkNotificationStatus()
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
                            Label("Navigator", systemImage: "map")
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
                                
                                Text("Ask to Siri")
                                    .foregroundStyle(.primary)
                                    .padding(.leading, 6)
                            }
                        }
                        
                        Toggle(
                            "Reduce Siri confirmation message",
                            isOn: $siriShortConfirmation
                        )
                        
                    } header: {
                        Text("Siri")
                    } footer: {
                        Text(
                            "When enabled, Siri will reply only with \"Done\" after creating a task."
                        )
                    }
                    
                    
                    
                    Section("Attachment Maintenance") {
                        
                        Toggle(
                            "Enable automatic deletion",
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
                            Text("Delete all attachments of completed tasks now")
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
                            Text("This action will permanently remove all attachments of completed tasks. This cannot be undone.")
                        }                    }
                    
                    .padding(.top,15)
                    
                    Section("Data Management") {
                        Button {
                            showDataManagement = true
                        } label: {
                            
                            HStack(spacing: 12) {
                                Image(systemName: "trash.circle")
                                    .foregroundStyle(.blue) //
                                    .frame(width: iconWidth)
                                
                                Text("Erase all Data")
                                    .tint(.red)
                                    .padding(.leading,6)
                            }
                        }
                    }
                }
                
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .scrollContentBackground(.hidden)
                .fullScreenCover(isPresented: $showSoundPicker) {
                    NotificationSoundPickerView()
                }            .fullScreenCover(isPresented: $showQuickGuide) {
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
