import SwiftUI
import SwiftData
import UserNotifications
import CoreData
import AppIntents
import os
import CoreLocation
import AuthenticationServices

#if canImport(AppKit)
import AppKit
#endif

@main
struct ForMemoApp: App {
    
    // MARK: - App Storage
    
    @AppStorage("completeTaskFromNotification")
    private var completeTaskFromNotification: String?
    
    @AppStorage("snoozeTaskFromNotification")
    private var snoozeTaskFromNotification: Data?
    
    @AppStorage("badgeIncludeExpired")
    private var badgeIncludeExpired: Bool = true
    
    let settings = AppSettings.shared
    
    
    
    // MARK: - Environment
    
    @Environment(\.scenePhase)
    private var scenePhase
    
    @State
    private var appSettings = AppSettings.shared
    
    
    // MARK: - App Delegate
    
    @UIApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate
    
    
    // MARK: - Persistence

    private let container: ModelContainer

    
    // MARK: - CloudKit Debounce
    
    private static var lastRemoteChange = Date.distantPast

    
    
    // MARK: - Init
    
    init() {
        CrashDetector.markLaunchStarted()
        LaunchCoordinator.shared.launchDate = Date()
        
        let defaults = UserDefaults.standard

        if defaults.object(forKey: "badgeIncludeExpired") == nil {
            defaults.set(true, forKey: "badgeIncludeExpired")
        }

        if defaults.object(forKey: "showAppBadge") == nil {
            defaults.set(true, forKey: "showAppBadge")
        }

        if defaults.object(forKey: "badgeMode") == nil {

            let leadObject = defaults.object(forKey: "notificationLeadTimeDays")

            // 🔥 Compatibility with previous versions:
            // old versions implicitly used global badge mode
            if let lead = leadObject as? Int,
               lead != -1 {

                defaults.set(1, forKey: "badgeMode")

            } else {

                defaults.set(0, forKey: "badgeMode")
            }
        }

        // 🔥 SINGLE LOCAL-FIRST STORE
        // Local database is the source of truth.
        // CloudKit only syncs the same persistent store.
        StoreMigrationManager.prepareMigrationIfNeeded()
        StoreMigrationManager.performMigrationIfNeeded()
        let sharedContainer = Persistence.makeModelContainer(
            cloudKitEnabled: true
        )

        self.container = sharedContainer

        let appSettings = AppSettings.shared

        NotificationManager.shared.modelContainer = sharedContainer

        
        CloudSettingsSync.shared.start()

        
        Task { @MainActor in
            let context = sharedContainer.mainContext

//            AttachmentMigration.runIfNeeded(
//                context: context
//            )

            WalletMigrationService.runIfNeeded(
                context: context
            )

            WalletAsset.normalizePersistedKinds(
                in: context
            )

            DebugLog.writeDatabaseSnapshot(
                context: context
            )
            
            
            VaultAutoFillManager.shared.synchronize(using: context)
            if appSettings.autoDeleteCompletedAttachments {
                try? AttachmentMaintenanceManager.shared.performAutomaticCleanup(
                    context: context,
                    retentionDays: appSettings.attachmentRetentionDays
                )
            }

            // 1️⃣ Setup notifiche (PRIMA DI TUTTO)
            await NotificationManager.shared.configure()
            
            // 🔥 REGISTRA APP SHORTCUTS
            AppShortcuts.updateAppShortcutParameters()
            
            // 2️⃣ Applica azioni da notifiche (app chiusa/background)
            NotificationActionProcessor.shared.processAll(using: context)
            
            // 3️⃣ Aggiorna subito UI
            NotificationCenter.default.post(
                name: .attachmentsShouldRefresh,
                object: nil
            )
     
            // 5️⃣ Final notification rebuild
            NotificationManager.shared.refresh(force: true)
            CrashDetector.markLaunchCompleted()
        }
        
        // 6️⃣ CloudKit observer
        startRemoteChangeObserver()
    }
    
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            TaskTabView()
                .onReceive(NotificationCenter.default.publisher(for: .snoozeRejectedDueToDeadline)) { _ in
                    
                    NotificationCenter.default.post(
                        name: .attachmentsShouldRefresh,
                        object: nil
                    )
                }
#if canImport(AppKit)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    NotificationManager.shared.refresh(force: true)
                }
#endif
                .environment(appSettings)
                .preferredColorScheme(appSettings.selectedTheme.colorScheme)
                .onContinueUserActivity(ASCredentialExchangeActivity) { activity in

                    Task {

                        guard let token = activity.userInfo?[ASCredentialImportToken] as? UUID else {
                            AppLogger.app.error("Credential Exchange: import token missing")
                            return
                        }

                        do {

                            let manager = ASCredentialImportManager()

                            let exportedData = try await manager.importCredentials(
                                token: token
                            )

                            let mapper = AppleCredentialImportMapper()

                            let records = try mapper.map(exportedData)

                            let result = try await VaultImportService.shared.importRecords(
                                records,
                                in: container.mainContext
                            )

                            AppLogger.app.info(
                                "Credential Exchange: processed \(result.processed) records"
                            )

                        } catch {

                            AppLogger.app.error(
                                "Credential Exchange import failed: \(error.localizedDescription)"
                            )
                        }
                    }
                }
        }
        
        .modelContainer(container)
        .onChange(of: scenePhase) {
            
            switch scenePhase {
                
            case .active:
                Task { @MainActor in
                    AppLogger.notifications.info("🟢 App became active")
                    
                    // 🔥 AUTO-FIX LOCATION PERMISSIONS
                    let status = CLLocationManager().authorizationStatus

                    if status != .authorizedAlways {
                        let wasEnabled = UserDefaults.standard.bool(forKey: "locationRemindersEnabled")
                        
                        if wasEnabled {
                            UserDefaults.standard.set(false, forKey: "locationRemindersEnabled")
                            
                            NotificationCenter.default.post(
                                name: .locationPermissionAutoDisabled,
                                object: nil
                            )
                        }
                    }
                    
                    LocationReminderManager.shared.requestPermissionIfNeeded()
                    
                    let context = container.mainContext
                    
//                    DebugLog.writeDatabaseSnapshot(
//                        context: context
//                    )
                    
                    // 1️⃣ Applica azioni notifiche
                    NotificationActionProcessor.shared.processAll(using: context)
 

                    // 2️⃣ 🔥 CLEANUP RECENTLY DELETED (task + attachments)
                    cleanupRecentlyDeleted(context: context)
                
                    
                    // 3️⃣ UI refresh
                    NotificationCenter.default.post(
                        name: .attachmentsShouldRefresh,
                        object: nil
                    )
                    
                    // 4️⃣ refresh notifiche (con piccolo delay SAFE)
                    NotificationManager.shared.refresh(force: true)
                }
            case .inactive:
                
                try? container.mainContext.save()
                
            case .background:
//                VaultLock.shared.lock()
                try? container.mainContext.save()
                
            @unknown default:
                break
            }
        }
    }
    
    
    // MARK: - 🔥 CLOUDKIT REALTIME (VERO)
    
    private func startRemoteChangeObserver() {
        print("REMOTE CHANGE")
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in

                let now = Date()

                guard now.timeIntervalSince(Self.lastRemoteChange) > 2 else {
                    return
                }

                Self.lastRemoteChange = now
                // 🔥 CloudKit remote change
#if DEBUG
                AppLogger.notifications.debug("📡 CloudKit push ricevuto")
#endif

                NotificationManager.shared.refreshFromCloudKit()

                let context = self.container.mainContext

//                if DiagnosticsOptions.attachmentDatabase {
//                    DebugLog.writeDatabaseSnapshot(
//                        context: context
//                    )
//                }
                
                NotificationActionProcessor.shared.processAll(
                    using: context
                )
                VaultAutoFillManager.shared.synchronize(using: context)

                // ✅ trigger UI
                NotificationCenter.default.post(
                    name: .attachmentsShouldRefresh,
                    object: nil
                )
            }
        }
    }
    
    
    
    // MARK: - Badge
    
    @MainActor
    private func updateBadge(using context: ModelContext) {
        
        let center = UNUserNotificationCenter.current()
        
        guard appSettings.showAppBadge else {
            center.setBadgeCount(0)
            return
        }
        
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate {
                !$0.isCompleted && $0.deadLine != nil
            }
        )
        
        let tasks = (try? context.fetch(descriptor)) ?? []
        

        let count = TaskBadgePolicy.badgeCount(
            tasks: tasks,
            referenceDate: .now
        )
        
        center.setBadgeCount(count)
    }
    // MARK: - 🔥 CLEANUP RECENTLY DELETED
    @MainActor
    private func cleanupRecentlyDeleted(context: ModelContext) {
        
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -settings.recentlyDeletedRetentionDays,
            to: .now
        ) else {
            AppLogger.persistence.error("Unable to calculate Recently Deleted cutoff date")
            return
        }
        
        let descriptor = FetchDescriptor<DeletedItem>()
        
        var deletedSomething = false
        
        guard let items = try? context.fetch(descriptor) else { return }

        for item in items {
            
            let deletedAt = item.deletedAt
            
            if deletedAt < cutoff {
                
                // 🔥 delete file if exists
                if let trashName = item.trashFileName,
                   let trashDir = TaskAttachment.trashDirectory {
                    
                    try? FileManager.default.removeItem(
                        at: trashDir.appendingPathComponent(trashName)
                    )
                }
                
                context.delete(item)
                deletedSomething = true
            }
        }
        
        if deletedSomething {
            try? context.save()
        }
    }
}


extension Notification.Name {
    static let locationPermissionAutoDisabled = Notification.Name("locationPermissionAutoDisabled")

}
