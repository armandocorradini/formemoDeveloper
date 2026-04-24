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

private var triggeredRecently: [String: Date] = {
    if let data = UserDefaults.standard.data(forKey: "locationTriggers"),
       let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
        return decoded
    }
    return [:]
}()
    
    private var isMonitoringActive = false
    
    private var lastLocationRequest: Date = .distantPast

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    // MARK: - Permissions
    
    func requestPermissionIfNeeded() {
        let status = manager.authorizationStatus
        
        if status == .notDetermined {
            manager.requestAlwaysAuthorization()
        }
    }
    
    func refreshMonitoring(tasks: [TodoTask]) {
        
        let enabled = UserDefaults.standard.bool(forKey: "locationRemindersEnabled")
        
        guard enabled else {
            stopAllMonitoring()
            return
        }
        
        let validTasks = tasks
            .filter { !$0.isCompleted }
            .filter { $0.locationReminderEnabled }
            .filter { $0.locationLatitude != nil && $0.locationLongitude != nil }
        
        guard !validTasks.isEmpty else {
            stopAllMonitoring()
            return
        }
        
        requestPermissionIfNeeded()
        
        if !isMonitoringActive {
            manager.startMonitoringSignificantLocationChanges()
            manager.startUpdatingLocation()
            isMonitoringActive = true
        }

        if lastKnownLocation == nil ||
           Date().timeIntervalSince(lastLocationRequest) > 60 {
            manager.requestLocation()
            lastLocationRequest = Date()
        }
        
        updateRegions(tasks: validTasks)
    }

    private func stopAllMonitoring() {
        
        manager.monitoredRegions.forEach {
            manager.stopMonitoring(for: $0)
        }
        
        if isMonitoringActive {
            manager.stopMonitoringSignificantLocationChanges()
            manager.stopUpdatingLocation()
            isMonitoringActive = false
        }
        
        monitoredTaskIDs.removeAll()
    }
    
    // MARK: - Setup Regions
    
    func updateRegions(tasks: [TodoTask]) {
        guard !tasks.isEmpty else { return }
        
        let newIDs = Set(tasks.map { $0.id })

        if newIDs == monitoredTaskIDs {
            return
        }
        
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
            
            let radius = max(150, UserDefaults.standard.integer(forKey: "locationRadius"))
            
            let region = CLCircularRegion(
                center: center,
                radius: CLLocationDistance(radius),
                identifier: task.id.uuidString
            )
            
            region.notifyOnEntry = true
            region.notifyOnExit = false
            
            manager.startMonitoring(for: region)
            monitoredTaskIDs.insert(task.id)
        }
    }
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        if let newLocation = locations.last {
            
            if let old = lastKnownLocation,
               newLocation.distance(from: old) < 50 {
                return
            }
            
            lastKnownLocation = newLocation
        }
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let container = NotificationManager.shared.modelContainer else { return }
            
            let context = container.mainContext
            
            let tasks: [TodoTask]
            do {
                tasks = try context.fetch(
                    FetchDescriptor<TodoTask>(
                        predicate: #Predicate { !$0.isCompleted }
                    )
                )
            } catch {
                return
            }
            
            self.updateRegions(tasks: tasks)
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Required for requestLocation() – prevents crash
#if DEBUG
        print("Location error: \(error.localizedDescription)")
#endif
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
        if let data = try? JSONEncoder().encode(triggeredRecently) {
            UserDefaults.standard.set(data, forKey: "locationTriggers")
        }
        
        if let lastTrigger = triggeredRecently[id] {
            let calendar = Calendar.current
            if calendar.isDate(lastTrigger, inSameDayAs: now) {
                return // 🔥 already triggered today
            }
            
            
        }
        
        triggeredRecently[id] = now
        if let data = try? JSONEncoder().encode(triggeredRecently) {
            UserDefaults.standard.set(data, forKey: "locationTriggers")
        }
        
        var titleText = "You have a task to complete here."
        
        if let uuid = UUID(uuidString: id),
           let container = NotificationManager.shared.modelContainer {
            
            let context = container.mainContext
            
            var descriptor = FetchDescriptor<TodoTask>(
                predicate: #Predicate { $0.id == uuid }
            )
            descriptor.fetchLimit = 1
            
            let result: [TodoTask]
            do {
                result = try context.fetch(descriptor)
            } catch {
                return
            }
            
            if let task = result.first {
                
                guard !task.isCompleted,
                      task.locationReminderEnabled else { return }
                
                titleText = task.title
            }
        }
        
        let content = UNMutableNotificationContent()
        content.title = String(localized:"📍 Nearby")
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
        
        UNUserNotificationCenter.current().add(request) { error in
#if DEBUG
            if let error {
                print("Notification scheduling error: \(error.localizedDescription)")
            }
#endif
        }
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
