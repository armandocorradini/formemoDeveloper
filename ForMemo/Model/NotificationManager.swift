import Foundation
import UIKit
import SwiftData
@preconcurrency import UserNotifications
import os


@MainActor
final class NotificationManager: NSObject {
    
    static let shared = NotificationManager()
    
    var modelContainer: ModelContainer?
    
    private var lastTasksSignature: String = ""
    private var rebuildTask: Task<Void, Never>?
    private var lastRebuild: Date = .distantPast
    private var pendingRefresh = false
  
    private var cloudKitDebounceTask: Task<Void, Never>?
    private var isAppLaunching = true
    private var cloudKitRefreshScheduled = false
    private var isProcessingCloudKit = false
    
    private let refreshQueue = DispatchQueue(label: "notification.refresh.serial")

    // 🔵 Safe access for AppDelegate (nonisolated)
    private(set) var lastPushHandledSafe: Date = .distantPast

    func setLastPushHandled(_ date: Date) {
        lastPushHandledSafe = date
    }
    
    
    private override init() {
        super.init()
    }
    
    // MARK: - Setup
    
    func configure() async {
        
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        
        let actions = [
            UNNotificationAction(
                identifier: "OPEN_APP",
                title: String(localized: "Open \(appName)"),
                options: [.foreground]
            ),
            UNNotificationAction(
                identifier: "SNOOZE_5",
                title: String(localized: "Snooze 5 min")
            ),
            UNNotificationAction(
                identifier: "SNOOZE_15",
                title: String(localized: "Snooze 15 min")
            ),
            UNNotificationAction(
                identifier: "SNOOZE_30",
                title: String(localized: "Snooze 30 min")
            ),
            UNNotificationAction(
                identifier: "SNOOZE_60",
                title: String(localized: "Snooze 1 hour")
            )
        ]
        
        let category = UNNotificationCategory(
            identifier: "TASK_REMINDER",
            actions: actions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        center.setNotificationCategories([category])

        // 🔵 Mark end of launch phase after short delay
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.0))
            self?.isAppLaunching = false
        }
    }
    
    // MARK: - PUBLIC REFRESH
    

    func refresh(force: Bool = false) {
        let now = Date()

        // 🔴 Throttle più morbido (evita drop di aggiornamenti reali)
        if !force && now.timeIntervalSince(lastRebuild) < 0.5 {
            return
        }

        lastRebuild = now

        guard let context = modelContainer?.mainContext else { return }

        let tasksInitial = fetchTasks(using: context)
        LocationReminderManager.shared.refreshMonitoring(tasks: tasksInitial)

        // 🔥 Badge immediato
        let badge = computeBadgeCount(from: tasksInitial)
        let showBadge = UserDefaults.standard.bool(forKey: "showAppBadge")
        applyBadge(showBadge ? badge : 0)

        // 🔥 evita loop multipli
        if pendingRefresh  {
            return
        }

        pendingRefresh = true

        rebuildTask?.cancel()

        rebuildTask = Task(priority: .utility) { [weak self] in
            
            print("🔥 REBUILD SCHEDULED")
            
            guard let self else { return }

            try? await Task.sleep(for: .seconds(force ? 0.5 : 1.5))
            guard !Task.isCancelled else { return }

            // --- MAIN ACTOR: fetch + signature ---
            var tasks: [TodoTask] = []
            var shouldRebuild = false

            await MainActor.run {
#if DEBUG
                AppLogger.notifications.debug("Optimized refresh")
#endif

                guard let context = self.modelContainer?.mainContext else {
                    return
                }

                let fetched = self.fetchTasks(using: context)
                let signature = self.signature(for: fetched)

                if !force && signature == self.lastTasksSignature {
                    self.refreshQueue.sync {
                        self.pendingRefresh = false
                    }
                    return
                }

                self.lastTasksSignature = signature
                tasks = fetched
                shouldRebuild = true
            }

            // --- OUTSIDE MAIN ACTOR: heavy work ---
            if shouldRebuild {

                print("🔥 REBUILD ESEGUITO")

                await self.rebuild(tasks)

            }

            // --- CLEANUP ---
            await MainActor.run {
                self.pendingRefresh = false
            }
        }
    }
    
    func forceFullRefresh(using context: ModelContext) {
        refresh(force: true)
    }
    
    // MARK: - CloudKit Optimized Refresh (coalescing)

    func refreshFromCloudKit() {
        let now = Date()

        // 🔥 HARD throttle globale (anti storm)
        if now.timeIntervalSince(self.lastPushHandledSafe) < 8.0 {
            return
        }

        // 🔥 Skip durante launch
        if self.isAppLaunching { return }

        // 🔥 Se già in corso → STOP
        if self.isProcessingCloudKit { return }

        self.isProcessingCloudKit = true

        cloudKitDebounceTask?.cancel()

        cloudKitDebounceTask = Task { [weak self] in
            guard let self else { return }

            // 🔥 Coalescing forte
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.refresh(force: true)
                self.lastPushHandledSafe = Date()
            }

            // 🔥 cooldown anti-loop
            try? await Task.sleep(for: .seconds(3.0))

            await MainActor.run {
                self.isProcessingCloudKit = false
            }
        }
    }
    

    
    // MARK: - FETCH
    
    private func fetchTasks(using context: ModelContext) -> [TodoTask] {
        
        let tasks = (try? context.fetch(FetchDescriptor<TodoTask>(
            predicate: #Predicate { !$0.isCompleted }
        ))) ?? []
        
        let now = Date()
        var needsSave = false
        
        for task in tasks {
            // 🔴 Skip debug stress-test tasks (no notifications)
            if task.isDebugTask { continue }
            if let snooze = task.snoozeUntil, snooze <= now {
                task.snoozeUntil = nil
                needsSave = true
            }
            if let snooze = task.snoozeUntil,
               let deadline = task.deadLine,
               snooze >= deadline {
                task.snoozeUntil = deadline.addingTimeInterval(-1)
                needsSave = true
            }
            
            // 🔵 MIGRATION: remove legacy "at deadline"
            if task.reminderOffsetMinutes == 0 {
                task.reminderOffsetMinutes = nil
                needsSave = true
            }
        }
        
        if needsSave {
            try? context.save()
        }
        
        return tasks
    }
    
    // MARK: - SIGNATURE
    
    private func signature(for tasks: [TodoTask]) -> String {
        
        guard !tasks.isEmpty else { return "EMPTY" }
        
        let body = tasks
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                "\($0.id.uuidString)-\($0.deadLine?.timeIntervalSince1970 ?? 0)-\($0.reminderOffsetMinutes ?? 0)-\($0.snoozeUntil?.timeIntervalSince1970 ?? 0)"
            }
            .joined(separator: "|")
        
        return "\(tasks.count)-" + body
    }
    
    // MARK: - NEXT TRIGGER (single source of truth)

    private func nextTrigger(for task: TodoTask, now: Date) -> (id: String, date: Date, type: String)? {
        
        guard let deadline = task.deadLine else { return nil }
        // 🔥 RUNTIME SAFETY: clean expired snooze also here (defensive)
        if let snooze = task.snoozeUntil, snooze <= now {
            task.snoozeUntil = nil
        }
        
        // 🔥 DEFINITIVE FIX: snooze domina SEMPRE e blocca tutta la pipeline
        if let snooze = task.snoozeUntil, snooze > now {

            if let deadline = task.deadLine, snooze >= deadline {
                return ("task.\(task.id.uuidString).deadline", deadline, "deadline")
            }

            return ("task.\(task.id.uuidString).snooze", snooze, "snooze")
        }

        var events: [(id: String, date: Date, type: String)] = []

        let leadDays = NotificationLeadTime(
            safeRawValue: UserDefaults.standard.integer(forKey: "notificationLeadTimeDays")
        ).rawValue

       // GLOBAL (skip when none / disabled)
        if leadDays >= 1 {
            let calendar = Calendar.current

            if var globalDate = calendar.date(byAdding: .day, value: -leadDays, to: deadline) {

                // 🔵 UX FIX: normalize to evening (18:00)
                globalDate = calendar.date(
                    bySettingHour: 18,
                    minute: 0,
                    second: 0,
                    of: globalDate
                ) ?? globalDate

                // 🔥 FAIL-SAFE: never lose GLOBAL
                if globalDate > now {
                    events.append(("task.\(task.id.uuidString).global", globalDate, "global"))
                }
            }
        }
//#if DEBUG
//        print("---- DEBUG GLOBAL ----")
//        print("leadDays:", leadDays)
//        print("now:", now)
//        print("deadline:", deadline)
//
//        if leadDays >= 1 {
//            let calendar = Calendar.current
//            if var globalDate = calendar.date(byAdding: .day, value: -leadDays, to: deadline) {
//                globalDate = calendar.date(
//                    bySettingHour: 18,
//                    minute: 0,
//                    second: 0,
//                    of: globalDate
//                ) ?? globalDate
//
//                let isFuture = globalDate > now
//                print("globalDate:", globalDate)
//                print("global > now ?", isFuture)
//            }
//        }
//        print("----------------------")
//#endif

        // REMINDER
        if let minutes = task.reminderOffsetMinutes,
           let reminderDate = Calendar.current.date(byAdding: .minute, value: -minutes, to: deadline) {
            if reminderDate > now {
                events.append(("task.\(task.id.uuidString).reminder", reminderDate, "reminder"))
            }
        }

        // DEADLINE (only if no snooze already returned above)
        if deadline > now {
            events.append(("task.\(task.id.uuidString).deadline", deadline, "deadline"))
        }

        events.sort { $0.date < $1.date }

        if let first = events.first {
            return first
        }

        // 🔥 FALLBACK SAFE: if nothing else, always return deadline
        if deadline > now {
            return ("task.\(task.id.uuidString).deadline", deadline, "deadline")
        }

        return nil
    }
    
    
    // MARK: - REBUILD
    
    private func rebuild(_ tasks: [TodoTask]) async {
        let rebuildStart = Date()
        let center = UNUserNotificationCenter.current()
        let now = Date()
       
        let requests = await center.pendingNotificationRequests()
        
        var existing: [String: UNNotificationRequest] = [:]
        for req in requests {
            existing[req.identifier] = req
        }
        
        var expectedIDs: Set<String> = []
        
        func addOrUpdate(
            id: String,
            content: UNNotificationContent,
            trigger: UNNotificationTrigger
        ) async {
            
            expectedIDs.insert(id)
            
            if let existingReq = existing[id] {
                
                // 🔥 controlla TUTTO, non solo body
                // 🔥 FIX: considera anche il trigger (data)

                var isSame = false

                if let oldTrigger = existingReq.trigger as? UNCalendarNotificationTrigger,
                   let newTrigger = trigger as? UNCalendarNotificationTrigger {
                    
                    isSame = oldTrigger.nextTriggerDate() == newTrigger.nextTriggerDate()
                }
                else if let oldTrigger = existingReq.trigger as? UNTimeIntervalNotificationTrigger,
                        let newTrigger = trigger as? UNTimeIntervalNotificationTrigger {
                    
                    isSame = abs(oldTrigger.timeInterval - newTrigger.timeInterval) < 1
                }

                if isSame &&
                   existingReq.content.body == content.body &&
                   existingReq.content.title == content.title {
                    return
                }
                
                center.removePendingNotificationRequests(withIdentifiers: [id])
            }
            
            let request = UNNotificationRequest(
                identifier: id,
                content: content,
                trigger: trigger
            )
            
            do {
                try await center.add(request)
            } catch {
            #if DEBUG
                AppLogger.notifications.error("Notification scheduling failed: \(error.localizedDescription)")
            #endif
            }
        }
        
        for task in tasks {
            
            guard !task.isCompleted else { continue }
            
            guard let next = nextTrigger(for: task, now: now) else {
                continue
            }
            let badgeAtTrigger = computeBadgeCount(at: next.date, tasks: tasks)

            let content: UNMutableNotificationContent
            
            switch next.type {
            case "snooze":
                content = baseContent(task, title: String(localized: "⏰ Snoozed"))

            case "reminder":
                content = baseContent(task, title: String(localized: "🔔 Reminder"))

            case "global":
                let leadDays = NotificationLeadTime(
                    safeRawValue: UserDefaults.standard.integer(forKey: "notificationLeadTimeDays")
                ).rawValue
                
                let title: String
                if leadDays == 1 {
                    title = String(localized: "⏱️ 1 day before!")
                } else {
                    title = String(localized: "⏱️ \(leadDays) days before!")
                }
                content = baseContent(task, title: title)

            case "deadline":
                content = baseContent(task, title: String(localized: "⏱️ Expired"))
                content.badge = NSNumber(value: badgeAtTrigger)

            default:
                content = baseContent(task, title: String(localized: "Reminder"))
            }
            content.userInfo["type"] = next.type
            
            let interval = next.date.timeIntervalSinceNow

            // 🔥 FIX: avoid immediate triggers ONLY for reminder/global
            // Deadline must ALWAYS fire
            if (next.type == "reminder" || next.type == "global") && interval <= 2 {
                continue
            }

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: interval,
                repeats: false
            )
            
            await addOrUpdate(
                id: next.id,
                content: content,
                trigger: trigger
            )
        }
        
        // 🚨 evita che rebuild vecchi sovrascrivano nuovi (SNOOZE FIX)
        guard rebuildStart >= self.lastRebuild else { return }
        
        let toRemove = existing.keys.filter { id in
            id.starts(with: "task.") && !expectedIDs.contains(id)
        }
        
        center.removePendingNotificationRequests(withIdentifiers: toRemove)

        // 🔥 FINAL SYNC: ensure badge always matches latest state
        let finalBadge = computeBadgeCount(from: tasks)
        let showBadge = UserDefaults.standard.bool(forKey: "showAppBadge")
        applyBadge(showBadge ? finalBadge : 0)
    }
    
    // MARK: - ACTIONS
    
    
    
    // MARK: - CONTENT (UI IDENTICA)
    
    private func baseContent(_ task: TodoTask, title: String) -> UNMutableNotificationContent {
        
        let c = UNMutableNotificationContent()
        
        c.title = title              // 🔥 UI ORIGINALE
        c.body = task.title         // 🔥 UI ORIGINALE
        
        let soundName = UserDefaults.standard.string(forKey: "notificationSoundName") ?? ""
        
        if soundName.isEmpty {
            c.sound = .default
        } else {
            c.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundName))
        }
        c.categoryIdentifier = "TASK_REMINDER"
        c.userInfo["taskID"] = task.id.uuidString
        
        return c
    }
    
    // MARK: - BADGEù
    private func computeBadgeCount(at date: Date, tasks: [TodoTask]) -> Int {
        
        tasks.reduce(0) { count, task in
            
            guard !task.isCompleted,
                  let deadline = task.deadLine else {
                return count
            }
            
            if deadline <= date {
                return count + 1
            }
            
            return count
        }
    }
    
    
    
    private func computeBadgeCount(from tasks: [TodoTask]) -> Int {
        
        TaskBadgePolicy.badgeCount(
            tasks: tasks,
            referenceDate: Date()
        )
    }
    
    private func applyBadge(_ count: Int) {
        
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
#if DEBUG
            if let error {
                AppLogger.notifications.error("Badge error: \(error.localizedDescription)")
            }
#endif
        }
    }
}

// MARK: - DELEGATE

extension NotificationManager: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        
        guard let taskID = response.notification.request.content.userInfo["taskID"] as? String else { return }
        
        let type = response.notification.request.content.userInfo["type"] as? String
        
        // 1️⃣ salva azione (come già fai)
        switch response.actionIdentifier {
            
        case UNNotificationDefaultActionIdentifier:
            // 🔥 TAP sulla notifica → completa task
            UserDefaults.standard.set(taskID, forKey: "completeTaskFromNotification")
            
        case "OPEN_APP":
            break // iOS apre già l'app automaticamente
            
        case "SNOOZE_5", "SNOOZE_15", "SNOOZE_30", "SNOOZE_60":
            if let container = self.modelContainer {
                let context = container.mainContext

                let interval: TimeInterval
                switch response.actionIdentifier {
                case "SNOOZE_5": interval = 300
                case "SNOOZE_15": interval = 900
                case "SNOOZE_30": interval = 1800
                case "SNOOZE_60": interval = 3600
                default: interval = 300
                }

                if let uuid = UUID(uuidString: taskID) {
                    let descriptor = FetchDescriptor<TodoTask>(
                        predicate: #Predicate { $0.id == uuid }
                    )

                    if let task = try? context.fetch(descriptor).first {
                        let rawDate = Date().addingTimeInterval(interval)

                        if let deadline = task.deadLine {
                            task.snoozeUntil = min(rawDate, deadline.addingTimeInterval(-1))
                        } else {
                            task.snoozeUntil = rawDate
                        }

                        try? context.save()
                        context.processPendingChanges()
                    }
                }
            }
            
        default:
            break
        }
        
        // 2️⃣ 🔥 FIX CRITICO — applica SUBITO
        await MainActor.run {
            
            if let container = self.modelContainer {
                let context = container.mainContext
                
                NotificationActionProcessor.shared.processAll(using: context)
                context.processPendingChanges()
                
                // 🔥 HARDCORE: aggiorna badge IMMEDIATAMENTE
                let tasks = self.fetchTasks(using: context)
                let badge = self.computeBadgeCount(from: tasks)
                let showBadge = UserDefaults.standard.bool(forKey: "showAppBadge")
                self.applyBadge(showBadge ? badge : 0)
            }
            
            NotificationManager.shared.refresh()
            
            NotificationCenter.default.post(
                name: .attachmentsShouldRefresh,
                object: nil
            )
        }
    }
}
