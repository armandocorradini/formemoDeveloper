import UIKit
import SwiftUI
@preconcurrency import UserNotifications
import os

final class AppDelegate: NSObject, UIApplicationDelegate {
    
    // MARK: - App Launch
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        
        application.registerForRemoteNotifications()
        
        return true
    }
    
    // MARK: - Permission
    
    private func requestNotificationPermission() {
        
        let center = UNUserNotificationCenter.current()
        
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            

            AppLogger.notifications.info("Permission granted: \(granted)")

            
            if let error {
                AppLogger.notifications.error("Permission error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - APNs
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        
#if DEBUG
        AppLogger.notifications.debug("APNs token: \(token)")
#endif
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        AppLogger.notifications.error("APNs error: \(error.localizedDescription)")
    }
    
    // MARK: - Silent Push (CloudKit)
    
    nonisolated func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        
#if DEBUG
        await AppLogger.notifications.debug("CloudKit push received")
#endif
        
        await MainActor.run {
            
            let now = Date()

            // 🔴 HARD FILTER (early drop – storm protection)
            if now.timeIntervalSince(NotificationManager.shared.lastPushHandledSafe) < 1.5 {
#if DEBUG
                AppLogger.notifications.debug("CloudKit push ignored (burst)")
#endif
                return
            }

            // 🔵 SOFT DEBOUNCE (coalescing window)
            if now.timeIntervalSince(NotificationManager.shared.lastPushHandledSafe) < 4.0 {
#if DEBUG
                AppLogger.notifications.debug("CloudKit push coalesced")
#endif
                return
            }

            NotificationManager.shared.setLastPushHandled(now)

#if DEBUG
            AppLogger.notifications.debug("CloudKit UI refresh (final)")
#endif

            NotificationManager.shared.refreshFromCloudKit()
        }
        
        return .newData
    }
}
