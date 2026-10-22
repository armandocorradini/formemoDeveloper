import UIKit
import BackgroundTasks
@preconcurrency import UserNotifications
import os

final class AppDelegate: NSObject, UIApplicationDelegate {
    
    // MARK: - App Launch
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerWeatherRefreshTask()
        scheduleWeatherRefresh()
        application.registerForRemoteNotifications()
        return true
    }
    

    // MARK: - Background Weather Refresh

    private let weatherRefreshTaskIdentifier = "corradini.armando.NewTask.weather-refresh"

    private func registerWeatherRefreshTask() {
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: weatherRefreshTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleWeatherRefresh(task: refreshTask)
        }

        if !registered {
            AppLogger.app.error("Unable to register background weather refresh task")
        }
    }

    private func scheduleWeatherRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: weatherRefreshTaskIdentifier)
        // This is an earliest start time, not a guaranteed execution time.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLogger.app.error("Unable to schedule background weather refresh: \(error.localizedDescription)")
        }
    }

    private func handleWeatherRefresh(task: BGAppRefreshTask) {
        // Submit the next opportunity before starting this refresh.
        scheduleWeatherRefresh()

        let operation = Task { @MainActor in
            await WeatherManager.shared.refresh()
            guard !Task.isCancelled else {
                task.setTaskCompleted(success: false)
                return
            }
            task.setTaskCompleted(success: !WeatherManager.shared.lastLoadFailed)
        }

        task.expirationHandler = {
            operation.cancel()
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
        await AppLogger.notifications.info(
            "WIDGET_DIAG: didReceiveRemoteNotification at \(Date().ISO8601Format()); userInfoKeys=\(userInfo.keys.map { String(describing: $0) }.sorted().joined(separator: ","))"
        )
        
        await MainActor.run {
            AppLogger.notifications.info(
                "WIDGET_DIAG: CloudKit push received; waiting for the persistent-store import event"
            )
        }
        
        return .newData
    }
}
