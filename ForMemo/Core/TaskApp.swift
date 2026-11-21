import SwiftUI
import SwiftData
import UserNotifications
import CoreData
import AppIntents
import os
import CoreLocation
import AuthenticationServices
import AlarmKit

#if canImport(AppKit)
import AppKit
#endif

@main
struct ForMemoApp: App {
    
    // MARK: - App Storage
    
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

    @State private var container: ModelContainer?
    @State private var selectedStoreURL: URL?
    @State private var startupError: String?
    @State private var servicesStarted = false

    
    // MARK: - CloudKit Debounce
    
    private static var remoteChangeDebounceTask: Task<Void, Never>?
    private static var remoteAssetCleanupTask: Task<Void, Never>?

    
    
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

        // SINGLE LOCAL-FIRST STORE. Keep the existing migration and store-selection flow.
        StoreMigrationManager.prepareMigrationIfNeeded()
        StoreMigrationManager.performMigrationIfNeeded()

        let startupStoreURL = Persistence.selectedStoreURLForStartup()
        _selectedStoreURL = State(initialValue: startupStoreURL)

        do {
            let sharedContainer = try Persistence.makeModelContainer(
                cloudKitEnabled: true,
                at: startupStoreURL
            )
            _container = State(initialValue: sharedContainer)
            _startupError = State(initialValue: nil)
        } catch {
            _container = State(initialValue: nil)
            _startupError = State(initialValue: error.localizedDescription)
            AppLogger.persistence.fault(
                "SwiftData startup unavailable: \(error.localizedDescription)"
            )
            // The app has reached its recoverable error screen; this is not a process crash.
            CrashDetector.markLaunchCompleted()
        }
        _servicesStarted = State(initialValue: false)
    }
    
    
    @MainActor
    private func retryPersistence() {
        guard container == nil, let selectedStoreURL else { return }

        do {
            let recoveredContainer = try Persistence.makeModelContainer(
                cloudKitEnabled: true,
                at: selectedStoreURL
            )
            container = recoveredContainer
            startupError = nil
            startServices(using: recoveredContainer)
        } catch {
            startupError = error.localizedDescription
            AppLogger.persistence.fault(
                "SwiftData retry failed: \(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private func startServices(using sharedContainer: ModelContainer) {
        guard !servicesStarted else { return }
        servicesStarted = true

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                guard Persistence.hasICloudIdentity else { return }
                AttachmentMigration.syncLocalAssetsToCloud(
                    context: sharedContainer.mainContext
                )
                NotificationCenter.default.post(
                    name: .attachmentsShouldRefresh,
                    object: nil
                )
            }
        }

        NotificationManager.shared.modelContainer = sharedContainer
        CloudSettingsSync.shared.start()

        let appSettings = AppSettings.shared
        Task { @MainActor in
            let context = sharedContainer.mainContext
            let tAttachmentMigration = ContinuousClock.now
            AttachmentMigration.runIfNeeded(context: context)
            AppLogger.notifications.debug(
                "⏱️ ACTIVE AttachmentMigration: \(ContinuousClock.now - tAttachmentMigration)"
            )
            WalletMigrationService.runIfNeeded(context: context)
            WalletAsset.normalizePersistedKinds(in: context)
            VaultAutoFillManager.shared.synchronize(using: context)

            if appSettings.autoDeleteCompletedAttachments {
                let tAttachmentCleanup = ContinuousClock.now
                try? AttachmentMaintenanceManager.shared.performAutomaticCleanup(
                    context: context,
                    retentionDays: appSettings.attachmentRetentionDays
                )
                AppLogger.notifications.debug(
                    "⏱️ ACTIVE AttachmentCleanup: \(ContinuousClock.now - tAttachmentCleanup)"
                )
            }

            await NotificationManager.shared.configure()
            await ForMemoAlarmManager.shared.removeOrphanedAlarmsAtStartup(context: context)
            AppShortcuts.updateAppShortcutParameters()
            NotificationActionProcessor.shared.processAll(using: context)
            TaskWidgetSnapshotStore.scheduleRefresh(from: context)
            NotificationCenter.default.post(name: .attachmentsShouldRefresh, object: nil)
            NotificationManager.shared.refresh(force: true)
            CrashDetector.markLaunchCompleted()
        }

        startRemoteChangeObserver(using: sharedContainer)
    }

    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    TaskTabView()
                        .modifier(RecurrenceSeriesExtensionPresenter())
                        .modelContainer(container)
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
                } else {
                    PersistenceRecoveryView(
                        errorMessage: startupError ?? String(localized: "Persistence.Startup.UnknownError"),
                        retry: retryPersistence
                    )
                }
            }
            .onAppear {
                if let container {
                    startServices(using: container)
                }
            }
        }
        .onChange(of: scenePhase) {
            guard let container else { return }
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
                    
                    let activationStart = ContinuousClock.now

                    NoteImportService.importPendingNote(
                        in: context
                    )
                    
                    // 1️⃣ Applica azioni notifiche
                    NotificationActionProcessor.shared.processAll(using: context)

                    // Coalesce this refresh with any CloudKit store-change refresh
                    // arriving as the app becomes active.
                    TaskWidgetSnapshotStore.scheduleRefresh(
                        from: context,
                        delay: .milliseconds(400)
                    )

                    // 2️⃣ 🔥 CLEANUP RECENTLY DELETED (task + attachments)
                    
                    let tDeletedCleanup = ContinuousClock.now

                    cleanupRecentlyDeleted(context: context)

                    AppLogger.notifications.debug(
                        "⏱️ ACTIVE DeletedCleanup: \(ContinuousClock.now - tDeletedCleanup)"
                    )
                
                    
                    // 3️⃣ UI refresh
                    NotificationCenter.default.post(
                        name: .attachmentsShouldRefresh,
                        object: nil
                    )
                    
                    // Restore configured alarms that are missing after AlarmKit authorization changes.
                    // When authorization is unavailable, invoke the manager's cleanup path too.
                    // Saved task alarmEnabled settings are preserved by the manager.
                    let alarmManager = ForMemoAlarmManager.shared
                    if alarmManager.authorizationState() == .authorized {
                        do {
                            let configuredAlarmTasks = try context.fetch(
                                FetchDescriptor<TodoTask>(
                                    predicate: #Predicate<TodoTask> { $0.alarmEnabled }
                                )
                            )
                            await alarmManager.restoreMissingConfiguredAlarms(
                                tasks: configuredAlarmTasks
                            )
                        } catch {
                            AppLogger.notifications.error(
                                "Failed to fetch configured tasks for AlarmKit restoration: \(error.localizedDescription)"
                            )
                        }
                    } else {
                        // This cancels any alarms still registered with AlarmKit without
                        // changing the user's saved alarm preferences on tasks.
                        await alarmManager.restoreMissingConfiguredAlarms(tasks: [])
                    }

                    // 4️⃣ refresh notifiche (con piccolo delay SAFE)
                    let tNotificationRefresh = ContinuousClock.now

                    NotificationManager.shared.refresh(force: true)

                    AppLogger.notifications.debug(
                        "⏱️ ACTIVE NotificationRefresh: \(ContinuousClock.now - tNotificationRefresh)"
                    )
                    
                    AppLogger.notifications.debug(
                        "⏱️ ACTIVE TOTAL: \(ContinuousClock.now - activationStart)"
                    )
                }
            case .inactive:
                
                try? container.mainContext.save()
                
            case .background:
//                VaultLock.shared.lock()
                try? container.mainContext.save()
                
                // Write immediately before suspension/background execution.
                TaskWidgetSnapshotStore.refresh(from: container.mainContext)
                
            @unknown default:
                break
            }
        }
    }
    
    
    // MARK: - 🔥 CLOUDKIT REALTIME (VERO)
    
    // MARK: - iCLOUD IDENTITY

    private func startRemoteChangeObserver(using container: ModelContainer) {

        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                TaskWidgetSnapshotStore.scheduleRefresh(
                    from: container.mainContext,
                    delay: .milliseconds(400)
                )

                // Keep lightweight CloudKit-dependent services responsive to
                // every store event, while coalescing UI and maintenance work.
                NotificationManager.shared.refreshFromCloudKit()

                // A true trailing debounce: every incoming event cancels and
                // restarts the pending refresh. The final event in a burst is
                // therefore guaranteed to schedule one UI refresh.
                Self.remoteChangeDebounceTask?.cancel()
                Self.remoteChangeDebounceTask = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(600))
                        try Task.checkCancellation()
                    } catch {
                        return
                    }

                    // 🔥 CloudKit remote change
#if DEBUG
                    AppLogger.notifications.debug("📡 CloudKit remote change settled")
#endif

                    let context = container.mainContext

                    // Local First: a remote deletion removes the SwiftData record,
                    // but does not automatically remove our separately managed
                    // local asset file. Reconcile physical assets only after the
                    // remote change has had time to settle.
                    Self.scheduleRemoteAssetCleanup(context: context)

                    NotificationActionProcessor.shared.processAll(
                        using: context
                    )
                    VaultAutoFillManager.shared.synchronize(using: context)

                    // Refresh every task view after the final imported transaction.
                    NotificationCenter.default.post(
                        name: .taskDidChange,
                        object: nil
                    )

                    NotificationCenter.default.post(
                        name: .attachmentsShouldRefresh,
                        object: nil
                    )
                }
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
    // MARK: - REMOTE ASSET CLEANUP


    @MainActor
    private static func scheduleRemoteAssetCleanup(
        context: ModelContext
    ) {
        remoteAssetCleanupTask?.cancel()

        remoteAssetCleanupTask = Task { @MainActor in
            do {
                // Let SwiftData finish applying the remote transaction(s)
                // before calculating which physical files are orphaned.
                try await Task.sleep(for: .seconds(2))
                try Task.checkCancellation()

                try RemoteAssetCleanupCoordinator.shared.cleanup(
                    context: context
                )
            } catch is CancellationError {
                // A newer remote change superseded this cleanup.
            } catch {
                AppLogger.persistence.error(
                    "Remote asset cleanup failed: \(error.localizedDescription)"
                )
            }
        }
        
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
                
                if let trashName = item.trashFileName {

                    let trashURL: URL?

                    switch item.type {
                    case "attachment":
                        trashURL = TaskAttachment.trashFileURL(
                            trashFileName: trashName
                        )

                    case "walletAsset":
                        trashURL = WalletAssetStore.trashFileURL(
                            trashFileName: trashName
                        )

                    case "documentAsset":
                        trashURL = DocumentAssetStore.trashFileURL(
                            trashFileName: trashName
                        )

                    default:
                        trashURL = nil
                    }

                    if let trashURL {
                        try? FileManager.default.removeItem(at: trashURL)
                    }
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


private struct PersistenceRecoveryView: View {
    let errorMessage: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 42))
                .accessibilityHidden(true)
            Text("Persistence.Startup.Title")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Persistence.Startup.Message")
                .multilineTextAlignment(.center)
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Button(action: retry) {
                Text("Persistence.Startup.Retry")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Notification.Name {
    static let locationPermissionAutoDisabled = Notification.Name("locationPermissionAutoDisabled")

}
