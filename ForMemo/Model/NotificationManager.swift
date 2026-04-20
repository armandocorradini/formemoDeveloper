import Foundation
import UIKit
import SwiftData
@preconcurrency import UserNotifications
import os


final class NotificationManager: NSObject {
    
    static let shared = NotificationManager()
    
    var modelContainer: ModelContainer?
    
    private var lastTasksSignature: String = ""
    private var rebuildTask: Task<Void, Never>?
    private var lastRebuild: Date = .distantPast
    private var pendingRefresh = false
    private var cloudKitDebounceTask: Task<Void, Never>?
    private var isAppLaunching = true
    
    var lastPushHandled: Date = .distantPast
    
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

        // 🔴 Throttle globale anti-loop (CloudKit push storm safe)

        if !force && now.timeIntervalSince(lastRebuild) < 1.0 {

            return

        }

        lastRebuild = now
        
        
        guard let context = modelContainer?.mainContext else { return }
        
        let tasks = fetchTasks(using: context)
        LocationReminderManager.shared.updateRegions(tasks: tasks)
        
        // 🔥 1. Badge immediato (NON CAMBIA)
        let badge = computeBadgeCount(from: tasks)
        let showBadge = UserDefaults.standard.bool(forKey: "showAppBadge")

        applyBadge(showBadge ? badge : 0)
        
        // 🔥 2. evita loop multipli
        if pendingRefresh && !force {
            return
        }
        
        pendingRefresh = true
        
        rebuildTask?.cancel()
        
        rebuildTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            
            // debounce
            try? await Task.sleep(for: .seconds(force ? 0.5 : 1.5))
            
            guard !Task.isCancelled else { return }
            
    #if DEBUG
            AppLogger.notifications.debug("Optimized refresh")
    #endif
            
            guard let context = self.modelContainer?.mainContext else { return }
            
            let tasks = self.fetchTasks(using: context)
            
            let signature = self.signature(for: tasks)
            
            if !force && signature == self.lastTasksSignature {
                self.pendingRefresh = false
                return
            }
            
            self.lastTasksSignature = signature
            
            await self.rebuild(tasks)
            
            self.pendingRefresh = false
        }
    }
    
    func forceFullRefresh(using context: ModelContext) {
        refresh(force: true)
    }
    
    // MARK: - CloudKit Optimized Refresh (coalescing)

    func refreshFromCloudKit() {
        // 🔵 Avoid heavy work during initial app launch
        if isAppLaunching {
            return
        }
        
        cloudKitDebounceTask?.cancel()
        
        cloudKitDebounceTask = Task { [weak self] in
            guard let self else { return }
            
            // aspetta eventuali altri push (coalescing)
            try? await Task.sleep(for: .seconds(1.5))
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.refresh()
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
            if let snooze = task.snoozeUntil, snooze < now {
                task.snoozeUntil = nil
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
    
    // MARK: - REBUILD
    
    private func rebuild(_ tasks: [TodoTask]) async {
        
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
            
            try? await center.add(request)
        }
        
        for task in tasks {
            
            guard !task.isCompleted else { continue }
            
            let base = "task.\(task.id.uuidString)"
            
            // MARK: - SNOOZE
            
            if let snooze = task.snoozeUntil, snooze > now {
                
                let id = "\(base).snooze"
                
                let content = baseContent(
                    task,
                    title: String(localized: "⏰ Snoozed")
                )
                
                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: max(60, snooze.timeIntervalSinceNow),
                    repeats: false
                )
                
                await addOrUpdate(id: id, content: content, trigger: trigger)
                continue
            }
            
            guard let deadline = task.deadLine else { continue }
            
            let leadDays = UserDefaults.standard.object(
                forKey: "notificationLeadTimeDays"
            ) as? Int ?? 1
            
            // MARK: - DEADLINE
            
            if let triggerDate = Calendar.current.date(
                byAdding: .day,
                value: -leadDays,
                to: deadline
            ), triggerDate > now {
                
                let id = "\(base).deadline"
                
                let content = baseContent(
                    task,
                    title: String(localized: "⏱️ \(leadDays) days before!")
                )
                
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: triggerDate
                    ),
                    repeats: false
                )
                
                await addOrUpdate(id: id, content: content, trigger: trigger)
            }
            
            // MARK: - REMINDER
            
            if let minutes = task.reminderOffsetMinutes,
               let date = Calendar.current.date(
                    byAdding: .minute,
                    value: -minutes,
                    to: deadline
               ),
               date > now {
                
                let id = "\(base).reminder"
                
                let content = baseContent(
                    task,
                    title: String(localized: "🔔 Reminder")
                )
                
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: date
                    ),
                    repeats: false
                )
                
                await addOrUpdate(id: id, content: content, trigger: trigger)
            }
        }
        
        let toRemove = existing.keys.filter { id in
            id.starts(with: "task.") && !expectedIDs.contains(id)
        }
        
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
    }
    
    // MARK: - ACTIONS
    
    private func setSnooze(taskID: String, interval: TimeInterval) {
        
        let payload: [String: Any] = [
            "id": taskID,
            "interval": interval
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            UserDefaults.standard.set(data, forKey: "snoozeTaskFromNotification")
        }
    }
    
    
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
        c.userInfo = ["taskID": task.id.uuidString]
        
        return c
    }
    
    // MARK: - BADGE
    
    private func computeBadgeCount(from tasks: [TodoTask]) -> Int {
        
        let leadDays = UserDefaults.standard.object(
            forKey: "notificationLeadTimeDays"
        ) as? Int ?? 1
        
        let includeExpired = UserDefaults.standard.bool(forKey: "badgeIncludeExpired")
        
        return TaskBadgePolicy.badgeCount(
            tasks: tasks,
            referenceDate: Date(),
            leadDays: leadDays,
            includeExpired: includeExpired
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
        
        // 1️⃣ salva azione (come già fai)
        switch response.actionIdentifier {
            
        case UNNotificationDefaultActionIdentifier:
            // 🔥 TAP sulla notifica → completa task
            UserDefaults.standard.set(taskID, forKey: "completeTaskFromNotification")
            
        case "OPEN_APP":
            break // iOS apre già l'app automaticamente
            
        case "SNOOZE_5":
            self.setSnooze(taskID: taskID, interval: 300)
            
        case "SNOOZE_15":
            self.setSnooze(taskID: taskID, interval: 900)
            
        case "SNOOZE_30":
            self.setSnooze(taskID: taskID, interval: 1800)
            
        case "SNOOZE_60":
            self.setSnooze(taskID: taskID, interval: 3600)
            
        default:
            break
        }
        
        // 2️⃣ 🔥 FIX CRITICO — applica SUBITO
        await MainActor.run {
            
            if let container = self.modelContainer {
                let context = container.mainContext
                
                NotificationActionProcessor.shared.processAll(using: context)
                context.processPendingChanges()
            }
            
            NotificationManager.shared.refresh(force: true)
            
            NotificationCenter.default.post(
                name: .attachmentsShouldRefresh,
                object: nil
            )
        }
    }
}
