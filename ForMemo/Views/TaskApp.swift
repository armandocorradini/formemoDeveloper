import SwiftUI
import SwiftData
import UserNotifications
import CoreData
import AppIntents
import os
import CoreLocation


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
        defaults.synchronize()


        DebugLog.writeAppLaunch()
        print(DebugLog.logURL)
        DebugLog.write("TEST")

        // 🔥 SINGLE LOCAL-FIRST STORE
        // Local database is the source of truth.
        // CloudKit only syncs the same persistent store.
        let sharedContainer = Persistence.makeModelContainer(
            cloudKitEnabled: true
        )

        self.container = sharedContainer

        let appSettings = AppSettings.shared

        DebugLog.write(
            "☁️ CLOUDKIT: App started with SINGLE LOCAL-FIRST container"
        )

        NotificationManager.shared.modelContainer = sharedContainer

        
        CloudSettingsSync.shared.start()
        
        DebugLog.writeCloudKitEvent(
            "CloudSettingsSync started"
        )
        
        Task { @MainActor in
            let context = sharedContainer.mainContext

            // 🔥 SINGLE LOCAL-FIRST STORE
            // Existing SQLite database is reused directly.
            // CloudKit only syncs the SAME local database.

            AttachmentMigration.runIfNeeded(
                context: context
            )
            if appSettings.autoDeleteCompletedAttachments {
                try? AttachmentMaintenanceManager.shared.performAutomaticCleanup(
                    context: context,
                    retentionDays: appSettings.attachmentRetentionDays
                )
            }
        }

        Task { @MainActor in
            let context = sharedContainer.mainContext

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
            DebugLog.writeDatabaseSnapshot(context: context)
            // 🔥 Short stabilization.
            // UI no longer depends on CloudKit hydration.
            try? await Task.sleep(for: .milliseconds(250))
            
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
        }
        
        .modelContainer(container)
        .onChange(of: scenePhase) {
            
            switch scenePhase {
                
            case .active:
                Task { @MainActor in
                    let activationStart = CFAbsoluteTimeGetCurrent()

                    @MainActor
                    func logStep(_ name: String) {
                        let elapsed = CFAbsoluteTimeGetCurrent() - activationStart
                        DebugLog.write("⏱️ ACTIVE \(name): \(String(format: "%.3f", elapsed))s")
                    }

                    AppLogger.notifications.info("🟢 App became active")
                    DebugLog.write("🟢 APP ACTIVE")
                    
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
                    
                    // 1️⃣ Applica azioni notifiche
                    NotificationActionProcessor.shared.processAll(using: context)
                    logStep("processAll")

                    DebugLog.writeAttachmentEvent(

                        "Attachment self-healing skipped on app active"

                    )
                    
                    // 2️⃣ 🔥 CLEANUP RECENTLY DELETED (task + attachments)
                    cleanupRecentlyDeleted(context: context)
                    logStep("recentlyDeleted")
                    
                    // 3️⃣ UI refresh
                    NotificationCenter.default.post(
                        name: .attachmentsShouldRefresh,
                        object: nil
                    )
                    
                    // 4️⃣ refresh notifiche (con piccolo delay SAFE)
                    NotificationManager.shared.refresh(force: true)
                    logStep("notificationRefresh")
                    logStep("ACTIVE COMPLETE")

                }
            case .inactive:
                try? container.mainContext.save()
                
            case .background:
                try? container.mainContext.save()
                
            @unknown default:
                break
            }
        }
    }
    
    
    // MARK: - 🔥 CLOUDKIT REALTIME (VERO)
    
    private func startRemoteChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let remoteStart = CFAbsoluteTimeGetCurrent()

                let now = Date()

                guard now.timeIntervalSince(Self.lastRemoteChange) > 2 else {
                    return
                }

                Self.lastRemoteChange = now
                // 🔥 CloudKit remote change
#if DEBUG
                AppLogger.notifications.debug("📡 CloudKit push ricevuto")
#endif
                DebugLog.writeCloudKitEvent("Remote change notification received")

                NotificationManager.shared.refreshFromCloudKit()

                let context = self.container.mainContext

                NotificationActionProcessor.shared.processAll(
                    using: context
                )

                // ✅ trigger UI
                NotificationCenter.default.post(
                    name: .attachmentsShouldRefresh,
                    object: nil
                )
                DebugLog.writeCloudKitEvent(
                    "⏱️ Remote change total: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - remoteStart))s"
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
        
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -settings.recentlyDeletedRetentionDays,
            to: .now
        )!
        
        let descriptor = FetchDescriptor<DeletedItem>()
        
        var deletedSomething = false
        
        guard let items = try? context.fetch(descriptor) else { return }
        
        for item in items {
            
            let deletedAt = item.deletedAt
            
            if deletedAt < cutoff {
                
                // 🔥 delete file if exists
                if let trashName = item.trashFileName,
                   let trashDir = TaskAttachment.trashDirectory {
                    
                    let url = trashDir.appendingPathComponent(trashName)
                    try? FileManager.default.removeItem(at: url)
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
