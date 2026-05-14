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
    
    @AppStorage("showAppBadge")
    private var showAppBadge: Bool = true
    
    @AppStorage("badgeIncludeExpired")
    private var badgeIncludeExpired: Bool = true
    
    @AppStorage("autoDeleteCompletedAttachments")
    private var autoDeleteCompletedAttachments: Bool = false

    @AppStorage("attachmentRetentionDays")
    private var attachmentRetentionDays: Int = 30

    @AppStorage("recentlyDeletedRetentionDays")
    private var recentlyDeletedRetentionDays: Int = 30
    
    @AppStorage("selectedTheme")
    private var selectedTheme: AppTheme = .system
    
    
    // MARK: - Environment
    
    @Environment(\.scenePhase)
    private var scenePhase
    
    
    // MARK: - App Delegate
    
    @UIApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate
    
    
    // MARK: - Persistence
    
    private let container: ModelContainer
    
    
    // MARK: - Init
    
    init() {
        
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
        
        
        let sharedContainer = Persistence.sharedModelContainer
        self.container = sharedContainer
        
        NotificationManager.shared.modelContainer = sharedContainer
        
        Task { @MainActor in
            let context = sharedContainer.mainContext
            
            // 🔥 Wait initial SwiftData / CloudKit stabilization
            try? await Task.sleep(for: .seconds(2.0))

            // 🔥 Attachment migration after stabilization
            AttachmentMigration.runIfNeeded(context: context)
        }

        Task { @MainActor in
            let context = sharedContainer.mainContext
            
            let descriptor = FetchDescriptor<TodoTask>()
            let allTasks = (try? context.fetch(descriptor)) ?? []

            let grouped = Dictionary(grouping: allTasks, by: \.id)

            var removedDuplicates = false

            func taskScore(_ task: TodoTask) -> Int {

                var score = 0

                // 🔥 attachments = priorità massima
                score += (task.attachments?.count ?? 0) * 100

                // 🔥 descrizione
                if !task.taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    score += 20
                }

                // 🔥 location
                if task.locationName != nil {
                    score += 20
                }

                // 🔥 reminder
                if task.reminderOffsetMinutes != nil {
                    score += 10
                }

                // 🔥 deadline
                if task.deadLine != nil {
                    score += 10
                }

                // 🔥 task completato = leggermente preferito
                if task.isCompleted {
                    score += 5
                }

                return score
            }

            for (id, tasks) in grouped where tasks.count > 1 {

                let sortedTasks = tasks.sorted {

                    // 🔥 priorità ai task NON completati
                    if $0.isCompleted != $1.isCompleted {
                        return !$0.isCompleted
                    }

                    let leftScore = taskScore($0)
                    let rightScore = taskScore($1)

                    // 🔥 poi score completezza
                    if leftScore != rightScore {
                        return leftScore > rightScore
                    }

                    // 🔥 infine createdAt più recente
                    return $0.createdAt > $1.createdAt
                }

                guard let keptTask = sortedTasks.first else {
                    continue
                }

#if DEBUG
                print("🧹 Duplicate cleanup for ID: \(id.uuidString)")
                print("✅ Keeping task: \(keptTask.title) | completed: \(keptTask.isCompleted)")
#endif

                for duplicate in sortedTasks.dropFirst() {
#if DEBUG
                    print("⚠️ Duplicate detected (not deleted): \(duplicate.title) | completed: \(duplicate.isCompleted)")
#endif
                    // context.delete(duplicate)
                    removedDuplicates = true
                }
            }

            if removedDuplicates {
#if DEBUG
                print("⚠️ Duplicate tasks detected during startup")
#endif
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
            
            // 4️⃣ Wait migration / CloudKit materialization
            try? await Task.sleep(for: .seconds(3.0))
            
            // 5️⃣ Final notification rebuild
            NotificationManager.shared.refresh(force: true)
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
                .preferredColorScheme(selectedTheme.colorScheme)
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
                    
                    // 1️⃣ Applica azioni notifiche
                    NotificationActionProcessor.shared.processAll(using: context)

                    // 🔥 Retry attachment migration/self-healing
                    // after app becomes active and CloudKit stabilizes.
                    try? await Task.sleep(for: .seconds(1.5))
                    AttachmentMigration.runIfNeeded(context: context)
                    
                    // 2️⃣ 🔥 CLEANUP ALLEGATI (QUI è il punto giusto)
                    if autoDeleteCompletedAttachments {
                        try? AttachmentMaintenanceManager.shared.performAutomaticCleanup(
                            context: context,
                            retentionDays: attachmentRetentionDays
                        )
                    }

                    // 3️⃣ 🔥 CLEANUP RECENTLY DELETED (task + attachments)
                    cleanupRecentlyDeleted(context: context)
                    
                    // 3️⃣ UI refresh
                    NotificationCenter.default.post(
                        name: .attachmentsShouldRefresh,
                        object: nil
                    )
                    
                    // 4️⃣ refresh notifiche (con piccolo delay SAFE)
                    try? await Task.sleep(for: .milliseconds(300))
                    NotificationManager.shared.refresh(force: true)
                    
                    // 🔥 SECOND PASS (fix CloudKit delayed pull on macOS)
                    try? await Task.sleep(for: .seconds(1.5))
                    NotificationManager.shared.refresh(force: true)
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
                
                // 🔥 COALESCING CLOUDKIT PUSH
#if DEBUG
                AppLogger.notifications.debug("📡 CloudKit push ricevuto")
#endif

                NotificationManager.shared.refreshFromCloudKit()
                
                let context = self.container.mainContext
                NotificationActionProcessor.shared.processAll(using: context)
                
                _ = try? context.fetch(FetchDescriptor<TodoTask>())
                
                // ✅ trigger UI
                NotificationCenter.default.post(
                    name: .attachmentsShouldRefresh,
                    object: nil
                )
            }
        }
    }
    
    
    // MARK: - STARTUP
    
    @MainActor
    private func appStartup() async {

        // 🔥 FONDAMENTALE — PRIMA DI TUTTO
        await NotificationManager.shared.configure()

        try? await Task.sleep(for: .milliseconds(200))

        NotificationManager.shared.refresh(force: true)
        
      
    }
    
    
    // MARK: - Scene Activation
    
    @MainActor
    private func handleSceneActivation() async {
        
        let context = container.mainContext
        
        if autoDeleteCompletedAttachments {
            try? AttachmentMaintenanceManager.shared.performAutomaticCleanup(
                context: context,
                retentionDays: attachmentRetentionDays
            )
        }
        
        // 🔥 trigger leggero sync
        _ = try? context.fetch(FetchDescriptor<TodoTask>())
        
        NotificationManager.shared.refresh()
        
        
    }
    
    
    // MARK: - LIGHT SYNC (foreground)
    
    @MainActor
    private func handleLightSync() {
        
        let context = container.mainContext
        
        _ = try? context.fetch(FetchDescriptor<TodoTask>())
        
        NotificationManager.shared.refresh()
        
        NotificationCenter.default.post(
            name: .attachmentsShouldRefresh,
            object: nil
        )
    }
    
    
    // MARK: - COMPLETAMENTO DA NOTIFICA
    
   
    // MARK: - Badge
    
    @MainActor
    private func updateBadge(using context: ModelContext) {
        
        let center = UNUserNotificationCenter.current()
        
        guard showAppBadge else {
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
            value: -recentlyDeletedRetentionDays,
            to: .now
        )!
        
        let descriptor = FetchDescriptor<DeletedItem>()
        
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
            }
        }
        
        try? context.save()
    }
}

extension Notification.Name {
    static let locationPermissionAutoDisabled = Notification.Name("locationPermissionAutoDisabled")

}
