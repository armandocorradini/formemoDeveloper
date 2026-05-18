import Foundation
import SwiftUI

@MainActor
final class CloudSettingsSync {
    
    static let shared = CloudSettingsSync()
    
    private init() {}
    
    private let store = NSUbiquitousKeyValueStore.default
    
    private var isApplyingRemoteChange = false
    private var started = false
    
    // MARK: - Keys
    
    private enum Keys {
        static let badgeMode = "badgeMode"
        static let notificationLeadTimeDays = "notificationLeadTimeDays"
    }
    
    // MARK: - Startup
    
    func start() {
        
        guard !started else { return }
        started = true
        
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { _ in
            
            Task { @MainActor in
                CloudSettingsSync.shared.applyRemoteChanges()
            }
        }
        
        store.synchronize()
        pushLocalValuesIfNeeded()
        applyRemoteChanges()
    }
    
    // MARK: - Public Sync
    
    func syncBadgeMode(_ value: Int) {
        
        guard !isApplyingRemoteChange else { return }
        
        let current = store.longLong(forKey: Keys.badgeMode)
        
        guard current != Int64(value) else { return }
        
        store.set(Int64(value), forKey: Keys.badgeMode)
        store.synchronize()
    }
    
    func syncNotificationLeadTimeDays(_ value: Int) {
        
        guard !isApplyingRemoteChange else { return }
        
        let current = store.longLong(forKey: Keys.notificationLeadTimeDays)
        
        guard current != Int64(value) else { return }
        
        store.set(Int64(value), forKey: Keys.notificationLeadTimeDays)
        store.synchronize()
    }
    
    // MARK: - Remote Merge
    
    private func applyRemoteChanges() {
        
        isApplyingRemoteChange = true
        defer { isApplyingRemoteChange = false }
        
        let defaults = UserDefaults.standard
        
        var didChange = false
        
        if let remoteBadgeMode = store.object(

            forKey: Keys.badgeMode

        ) as? Int64 {
            
            let localBadgeMode = defaults.integer(forKey: Keys.badgeMode)
            
            if localBadgeMode != Int(remoteBadgeMode) {
                defaults.set(Int(remoteBadgeMode), forKey: Keys.badgeMode)
                didChange = true
            }
        }
        
        if let remoteLeadTime = store.object(forKey: Keys.notificationLeadTimeDays) as? Int64 {
            
            let localLeadTime = defaults.integer(forKey: Keys.notificationLeadTimeDays)
            
            if localLeadTime != Int(remoteLeadTime) {
                defaults.set(Int(remoteLeadTime), forKey: Keys.notificationLeadTimeDays)
                didChange = true
            }
        }
        
        guard didChange else { return }
        
        NotificationManager.shared.refresh(force: true)
    }
    
    
    private func pushLocalValuesIfNeeded() {

        let defaults = UserDefaults.standard

        let localBadgeMode = defaults.integer(
            forKey: Keys.badgeMode
        )

        let localLeadTime = defaults.integer(
            forKey: Keys.notificationLeadTimeDays
        )

        if store.object(forKey: Keys.badgeMode) == nil {
            store.set(
                Int64(localBadgeMode),
                forKey: Keys.badgeMode
            )
        }

        if store.object(forKey: Keys.notificationLeadTimeDays) == nil {
            store.set(
                Int64(localLeadTime),
                forKey: Keys.notificationLeadTimeDays
            )
        }

        store.synchronize()
    }
}
