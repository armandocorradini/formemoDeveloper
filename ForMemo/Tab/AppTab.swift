import SwiftUI

@MainActor
enum AppTab: Int, CaseIterable, Identifiable {
    case dashboard = 10
    case tasks = 1
    case calendar = 3
    case wallet = 6
    case start = 0
    case vault = 11
    case trips = 7
    case documents = 8
    case today = 4
    case forecast = 9
    case map = 5
    case settings = 2

    // Preserves the current tab bar and More menu order for existing users.
    static let defaultOrder: [AppTab] = [
        .dashboard, .tasks, .calendar, .wallet,
        .start, .vault, .trips, .documents,
        .today, .forecast, .map, .settings
    ]

    var id: Int { rawValue }

    var icon: String {
        switch self {
        case .dashboard: "house"
        case .tasks: "checklist"
        case .calendar: "calendar"
        case .wallet: "wallet.bifold"
        case .start: "info"
        case .vault: "key.shield"
        case .trips: "suitcase.rolling"
        case .documents: "doc.text"
        case .today: "calendar.day.timeline.right"
        case .forecast: "cloud.sun"
        case .map: "map"
        case .settings: "gear"
        }
    }

    func title(using settings: AppSettings) -> String {
        switch self {
        case .dashboard: "Dashboard"
        case .tasks: String(localized: "list_tab")
        case .calendar: String(localized: "calendar_tab")
        case .wallet: String(localized: "wallet_tab")
        case .start: String(localized: "Start_tab")
        case .vault: String(localized: "Vault")
        case .trips: String(localized: "Trips")
        case .documents: String(localized: "Documents")
        case .today:
            settings.taskWeekDays == 1
                ? String(localized: "today_tab")
                : String(localized: "\(settings.taskWeekDays) days_tab")
        case .forecast: String(localized: "Forecast")
        case .map: String(localized: "map_tab")
        case .settings: String(localized: "settings_tab")
        }
    }

    func isVisible(using settings: AppSettings) -> Bool {
        switch self {
        case .vault: settings.showVault
        case .forecast: settings.showWeatherForecast
        default: true
        }
    }
}
