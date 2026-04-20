import Foundation
import CoreLocation
import SwiftData
import UserNotifications

@MainActor
final class LocationReminderManager: NSObject, CLLocationManagerDelegate {
    
    static let shared = LocationReminderManager()
    
    private let manager = CLLocationManager()
    
    private var monitoredTaskIDs: Set<UUID> = []
    
    private var lastKnownLocation: CLLocation?

    private var triggeredRecently: [String: Date] = [:]
    
    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        manager.startUpdatingLocation()
    }
    
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        lastKnownLocation = locations.last
        
        Task { @MainActor in
            // 🔥 ricalcola regioni dinamicamente
            if let container = NotificationManager.shared.modelContainer {
                let context = container.mainContext
                let tasks = (try? context.fetch(FetchDescriptor<TodoTask>(
                    predicate: #Predicate { !$0.isCompleted }

                ))) ?? []
                updateRegions(tasks: tasks)
            }
        }
    }
    
    
    // MARK: - Permissions
    
    func requestPermissionIfNeeded() {
        let status = manager.authorizationStatus
        
        if status == .notDetermined {
            manager.requestAlwaysAuthorization()
        }
    }
    
    // MARK: - Setup Regions
    
    func updateRegions(tasks: [TodoTask]) {
        
        
        let enabled = UserDefaults.standard.bool(forKey: "locationRemindersEnabled")
        guard enabled else {
            manager.monitoredRegions.forEach {
                manager.stopMonitoring(for: $0)
            }
            return
        }
        
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        
        manager.monitoredRegions.forEach {
            manager.stopMonitoring(for: $0)
        }
        
        monitoredTaskIDs.removeAll()
        
        let validTasks = tasks
            .filter { !$0.isCompleted }
            .filter { $0.locationReminderEnabled }
            .filter { $0.locationLatitude != nil && $0.locationLongitude != nil }
        
        let scoredTasks = validTasks.map { task -> (task: TodoTask, score: Double) in
            
            var score: Double = 0
            
            // 📍 DISTANCE SCORE
            if let userLocation = lastKnownLocation,
               let lat = task.locationLatitude,
               let lon = task.locationLongitude {
                
                let taskLocation = CLLocation(latitude: lat, longitude: lon)
                let distance = userLocation.distance(from: taskLocation)
                
                // più vicino = punteggio più alto
                score += max(0, 10000 - distance) / 100
            }
            
            // ⏱️ DEADLINE SCORE
            if let deadline = task.deadLine {
                let time = deadline.timeIntervalSinceNow
                
                if time > 0 {
                    score += max(0, 100000 - time) / 1000
                } else {
                    score += 200 // già scaduto → alta priorità
                }
            }
            
            return (task, score)
        }
        .sorted { $0.score > $1.score }
        .map { $0.task }

        let limited = Array(scoredTasks.prefix(20))
        
        for task in limited {
            guard let lat = task.locationLatitude,
                  let lon = task.locationLongitude else { continue }
            
            let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            
            let region = CLCircularRegion(
                center: center,
                radius: CLLocationDistance(
                    max(100, UserDefaults.standard.integer(forKey: "locationRadius"))
                ),
                identifier: task.id.uuidString
            )
            
            region.notifyOnEntry = true
            region.notifyOnExit = false
            
            manager.startMonitoring(for: region)
            monitoredTaskIDs.insert(task.id)
        }
    }
}

extension LocationReminderManager {
    
    func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        guard let circular = region as? CLCircularRegion else { return }
        
        triggerNotification(for: circular.identifier)
    }
    
    private func triggerNotification(for id: String) {
        
        let now = Date()
        
        // 🔥 cleanup old entries (> 2 days)
        triggeredRecently = triggeredRecently.filter {
            Calendar.current.dateComponents([.day], from: $0.value, to: now).day ?? 0 < 2
        }
        
        if let lastTrigger = triggeredRecently[id] {
            let calendar = Calendar.current
            if calendar.isDate(lastTrigger, inSameDayAs: now) {
                return // 🔥 already triggered today
            }
        }
        
        triggeredRecently[id] = now
        
        var titleText = "You have a task to complete here."
        
        if let uuid = UUID(uuidString: id),
           let container = NotificationManager.shared.modelContainer {
            
            let context = container.mainContext
            
            let descriptor = FetchDescriptor<TodoTask>(
                predicate: #Predicate { $0.id == uuid }
            )
            
            if let task = try? context.fetch(descriptor).first {
                titleText = task.title
            }
        }
        
        let content = UNMutableNotificationContent()
        content.title = String(localized:"📍 You're near your task")
        content.body = titleText
        let soundName = UserDefaults.standard.string(forKey: "notificationSoundName") ?? ""
        if soundName.isEmpty {
            content.sound = .default
        } else {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundName))
        }
        
        let request = UNNotificationRequest(
            identifier: "location.\(id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}




//extension LocationReminderManager {
//
//
//
//    func debugTrigger(for task: TodoTask) {
//
//        guard let id = task.id.uuidString as String? else { return }
//
//
//
//        print("🧪 DEBUG: Simulating region entry for \(task.title)")
//
//
//
//        triggerNotification(for: id)
//
//    }
//
//}
