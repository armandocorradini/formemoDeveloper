import SwiftUI
import Observation

@Observable
@MainActor
final class AppSettings {

    static let shared = AppSettings()

    // MARK: - Task List Appearance

    var iconStyle: TaskIconStyle {
        didSet {
            UserDefaults.standard.set(
                iconStyle.rawValue,
                forKey: TaskListAppearanceKeys.iconStyle
            )
        }
    }

    var showBadge: Bool {
        didSet {
            UserDefaults.standard.set(
                showBadge,
                forKey: TaskListAppearanceKeys.showBadge
            )
        }
    }

    var showAttachments: Bool {
        didSet {
            UserDefaults.standard.set(
                showAttachments,
                forKey: TaskListAppearanceKeys.showAttachments
            )
        }
    }

    var showLocation: Bool {
        didSet {
            UserDefaults.standard.set(
                showLocation,
                forKey: TaskListAppearanceKeys.showLocation
            )
        }
    }

    var showPriority: Bool {
        didSet {
            UserDefaults.standard.set(
                showPriority,
                forKey: TaskListAppearanceKeys.showPriority
            )
        }
    }

    var showBadgeOnlyWithPriority: Bool {
        didSet {
            UserDefaults.standard.set(
                showBadgeOnlyWithPriority,
                forKey: TaskListAppearanceKeys.showBadgeOnlyWithPriority
            )
        }
    }

    var highlightEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                highlightEnabled,
                forKey: "tasklist.highlightEnabled"
            )
        }
    }

    var highlightColorHex: String {
        didSet {
            UserDefaults.standard.set(
                highlightColorHex,
                forKey: "tasklist.highlightColor"
            )
        }
    }

    var showTodayExpiredLabel: Bool {
        didSet {
            UserDefaults.standard.set(
                showTodayExpiredLabel,
                forKey: TaskListAppearanceKeys.showTodayExpiredLabel
            )
        }
    }

    var selectedTaskRowStyle: Int {
        didSet {
            UserDefaults.standard.set(
                selectedTaskRowStyle,
                forKey: "selectedTaskRowStyle"
            )
        }
    }

    var selectedRowStyle: Int {
        get { selectedTaskRowStyle }
        set { selectedTaskRowStyle = newValue }
    }

    var dueIconEffectRaw: String {
        didSet {
            UserDefaults.standard.set(
                dueIconEffectRaw,
                forKey: "dueIconEffect"
            )
        }
    }
    var dueIconEffect: DueIconEffect {
        get {
            DueIconEffect(rawValue: dueIconEffectRaw) ?? .blink
        }
        set {
            dueIconEffectRaw = newValue.rawValue
        }
    }

    var taskListStyle: TaskListStyle {
        didSet {
            UserDefaults.standard.set(
                taskListStyle.rawValue,
                forKey: "TaskListStyle"
            )
        }
    }

    var showDateEveryRow: Bool {
        didSet {
            UserDefaults.standard.set(
                showDateEveryRow,
                forKey: "TaskListShowDateEveryRow"
            )
        }
    }

    var confirmTaskDeletion: Bool {
        didSet {
            UserDefaults.standard.set(
                confirmTaskDeletion,
                forKey: "confirmTaskDeletion"
            )
        }
    }

    var taskWeekDays: Int {
        didSet {
            UserDefaults.standard.set(
                taskWeekDays,
                forKey: "TaskWeekDays"
            )
        }
    }

    var startupTab: Int {
        didSet {
            UserDefaults.standard.set(
                startupTab,
                forKey: "startupTab"
            )
        }
    }

    var notificationLeadTimeDays: Int {
        didSet {
            UserDefaults.standard.set(
                notificationLeadTimeDays,
                forKey: "notificationLeadTimeDays"
            )
        }
    }

    var showWeatherForecast: Bool {
        didSet {
            UserDefaults.standard.set(
                showWeatherForecast,
                forKey: "showWeatherForecast"
            )
        }
    }

    var siriAutoReminderEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                siriAutoReminderEnabled,
                forKey: "siriAutoReminderEnabled"
            )
        }
    }

    var navigationAppRaw: String {
        didSet {
            UserDefaults.standard.set(
                navigationAppRaw,
                forKey: "navigationApp"
            )
        }
    }
    var navigationApp: NavigationApp {
        get {
            NavigationApp(rawValue: navigationAppRaw) ?? .appleMaps
        }
        set {
            navigationAppRaw = newValue.rawValue
        }
    }

    private init() {

        let defaults = UserDefaults.standard

        iconStyle =
            TaskIconStyle(
                rawValue: defaults.string(
                    forKey: TaskListAppearanceKeys.iconStyle
                ) ?? ""
            ) ?? .polychrome

        showBadge =
            defaults.object(
                forKey: TaskListAppearanceKeys.showBadge
            ) as? Bool ?? true

        showAttachments =
            defaults.object(
                forKey: TaskListAppearanceKeys.showAttachments
            ) as? Bool ?? true

        showLocation =
            defaults.object(
                forKey: TaskListAppearanceKeys.showLocation
            ) as? Bool ?? true

        showPriority =
            defaults.object(
                forKey: TaskListAppearanceKeys.showPriority
            ) as? Bool ?? true

        showBadgeOnlyWithPriority =
            defaults.object(
                forKey: TaskListAppearanceKeys.showBadgeOnlyWithPriority
            ) as? Bool ?? true

        highlightEnabled =
            defaults.object(
                forKey: "tasklist.highlightEnabled"
            ) as? Bool ?? true

        highlightColorHex =
            defaults.string(
                forKey: "tasklist.highlightColor"
            ) ?? (Color.red.toHex() ?? "")

        showTodayExpiredLabel =
            defaults.object(
                forKey: TaskListAppearanceKeys.showTodayExpiredLabel
            ) as? Bool ?? true

        selectedTaskRowStyle =
            defaults.object(
                forKey: "selectedTaskRowStyle"
            ) as? Int ?? 0

        dueIconEffectRaw =
            defaults.string(
                forKey: "dueIconEffect"
            ) ?? DueIconEffect.blink.rawValue

        taskListStyle =
            TaskListStyle(
                rawValue: defaults.string(
                    forKey: "TaskListStyle"
                ) ?? "plain"
            ) ?? .plain

        showDateEveryRow =
            defaults.object(
                forKey: "TaskListShowDateEveryRow"
            ) as? Bool ?? false

        confirmTaskDeletion =
            defaults.object(
                forKey: "confirmTaskDeletion"
            ) as? Bool ?? true

        taskWeekDays =
            defaults.object(
                forKey: "TaskWeekDays"
            ) as? Int ?? 3

        startupTab =
            defaults.object(
                forKey: "startupTab"
            ) as? Int ?? 0

        notificationLeadTimeDays =
            defaults.object(
                forKey: "notificationLeadTimeDays"
            ) as? Int ?? 1

        showWeatherForecast =
            defaults.object(
                forKey: "showWeatherForecast"
            ) as? Bool ?? true

        siriAutoReminderEnabled =
            defaults.object(
                forKey: "siriAutoReminderEnabled"
            ) as? Bool ?? true

        navigationAppRaw =
            defaults.string(
                forKey: "navigationApp"
            ) ?? "appleMaps"
    }
}
