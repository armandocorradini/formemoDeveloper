import UIKit
@preconcurrency import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    
    // MARK: - App Launch
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        
        // 🔥 NON impostare delegate qui (lo fa NotificationManager)
        // 🔥 NON creare actions qui (lo fa NotificationManager)
        
        requestNotificationPermission()
        
        application.registerForRemoteNotifications()
        
        return true
    }
    
    // MARK: - Permission
    
    private func requestNotificationPermission() {
        
        let center = UNUserNotificationCenter.current()
        
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            
#if DEBUG
            print("🔔 Permission granted:", granted)
#endif
            
            if let error {
                print("❌ Permission error:", error.localizedDescription)
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
        print("📱 APNs token:", token)
#endif
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ APNs error:", error.localizedDescription)
    }
    
    // MARK: - Silent Push (CloudKit)
    
    nonisolated func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        
#if DEBUG
        print("🔥 CLOUDKIT PUSH ARRIVATO")
#endif
        
        await MainActor.run {
            NotificationManager.shared.refresh()
        }
        
        return .newData
    }
}
