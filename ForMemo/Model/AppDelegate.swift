import UIKit
@preconcurrency import UserNotifications
import os

final class AppDelegate: NSObject, UIApplicationDelegate {
    
    // MARK: - App Launch
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
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
#if DEBUG
            AppLogger.notifications.debug("CloudKit refresh trigger")
#endif

            NotificationManager.shared.refreshFromCloudKit()
        }
        
        return .newData
    }
}
