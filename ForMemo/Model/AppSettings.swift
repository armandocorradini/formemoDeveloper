import SwiftUI
import Observation

@Observable
@MainActor
final class AppSettings {
    
    static let shared = AppSettings()
    
    private let backupExcludedKeys: Set<String> = []
    
    func exportSettings() -> [String: Any] {
        
        let dictionary = UserDefaults.standard.dictionaryRepresentation()
        
        return dictionary.filter { key, _ in
            !backupExcludedKeys.contains(key)
        }
    }
    
    func importSettings(from dictionary: [String: Any]) {
        
        let defaults = UserDefaults.standard
        
        for (key, value) in dictionary {
            guard !backupExcludedKeys.contains(key) else {
                continue
            }
            
            defaults.set(value, forKey: key)
        }
        
        defaults.synchronize()
        reloadFromUserDefaults()
    }

    @MainActor
    private func loadFromUserDefaults(_ defaults: UserDefaults) {
        iconStyle = TaskIconStyle(
            rawValue: defaults.string(forKey: TaskListAppearanceKeys.iconStyle) ?? ""
        ) ?? .polychrome

        showBadge = defaults.object(forKey: TaskListAppearanceKeys.showBadge) as? Bool ?? true
        showAttachments = defaults.object(forKey: TaskListAppearanceKeys.showAttachments) as? Bool ?? true
        showLocation = defaults.object(forKey: TaskListAppearanceKeys.showLocation) as? Bool ?? true
        showPriority = defaults.object(forKey: TaskListAppearanceKeys.showPriority) as? Bool ?? true
        showBadgeOnlyWithPriority = defaults.object(forKey: TaskListAppearanceKeys.showBadgeOnlyWithPriority) as? Bool ?? true
        highlightEnabled = defaults.object(forKey: "tasklist.highlightEnabled") as? Bool ?? true
        highlightColorHex = defaults.string(forKey: "tasklist.highlightColor") ?? (Color.red.toHex() ?? "")
        showTodayExpiredLabel = defaults.object(forKey: TaskListAppearanceKeys.showTodayExpiredLabel) as? Bool ?? true
        selectedTaskRowStyle = defaults.object(forKey: "selectedTaskRowStyle") as? Int ?? 0
        dueIconEffectRaw = defaults.string(forKey: "dueIconEffect") ?? DueIconEffect.blink.rawValue
        
        let rawValue = defaults.string(forKey: "TaskListStyle")
        taskListStyle = TaskListStyle(rawValue: rawValue ?? TaskListStyle.grouped.rawValue) ?? .plain
        
        showDateEveryRow = defaults.object(forKey: "TaskListShowDateEveryRow") as? Bool ?? false
        confirmTaskDeletion = defaults.object(forKey: "confirmTaskDeletion") as? Bool ?? true
        taskWeekDays = defaults.object(forKey: "TaskWeekDays") as? Int ?? 3
        startupTab = defaults.object(forKey: "startupTab") as? Int ?? 1
        notificationLeadTimeDays = defaults.object(forKey: "notificationLeadTimeDays") as? Int ?? 1
        showWeatherForecast = defaults.object(forKey: "showWeatherForecast") as? Bool ?? true
        siriAutoReminderEnabled = defaults.object(forKey: "siriAutoReminderEnabled") as? Bool ?? true
        navigationAppID = defaults.string(forKey: "navigationApp") ?? "apple"
        backgroundColor1Hex = defaults.string(forKey: "backgroundColor1Hex") ?? (defaultBackColor1.toHex() ?? "")
        backgroundColor2Hex = defaults.string(forKey: "backgroundColor2Hex") ?? (defaultBackColor2.toHex() ?? "")
        badgeMode = defaults.object(forKey: "badgeMode") as? Int ?? 1
        showAppBadge = defaults.object(forKey: "showAppBadge") as? Bool ?? true
        selectedTheme = AppTheme(rawValue: defaults.integer(forKey: "selectedTheme")) ?? .system
        autoDeleteCompletedAttachments = defaults.object(forKey: "autoDeleteCompletedAttachments") as? Bool ?? true
        attachmentRetentionDays = defaults.object(forKey: "attachmentRetentionDays") as? Int ?? 30
        recentlyDeletedRetentionDays = defaults.object(forKey: "recentlyDeletedRetentionDays") as? Int ?? 30
        locationRemindersEnabled = defaults.object(forKey: "locationRemindersEnabled") as? Bool ?? false
        locationRadius = defaults.object(forKey: "locationRadius") as? Int ?? 150
    }

    @MainActor
    func reloadFromUserDefaults() {
        let defaults = UserDefaults.standard
        loadFromUserDefaults(defaults)
    }
    
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
    
    
    //migrato
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
    
    var navigationAppID: String {
        didSet {
            UserDefaults.standard.set(
                navigationAppID,
                forKey: "navigationApp"
            )
        }
    }
    
    var navigationApp: NavigationApp {
        get {
            NavigationApp.app(for: navigationAppID)
        }
        set {
            navigationAppID = newValue.id
        }
    }
    
    var backgroundColor1Hex: String {
        didSet {
            UserDefaults.standard.set(
                backgroundColor1Hex,
                forKey: "backgroundColor1Hex"
            )
        }
    }
    
    var backgroundColor2Hex: String {
        didSet {
            UserDefaults.standard.set(
                backgroundColor2Hex,
                forKey: "backgroundColor2Hex"
            )
        }
    }
    
    var badgeMode: Int {
        didSet {
            UserDefaults.standard.set(
                badgeMode,
                forKey: "badgeMode"
            )
        }
    }
    
    var showAppBadge: Bool {
        didSet {
            UserDefaults.standard.set(
                showAppBadge,
                forKey: "showAppBadge"
            )
        }
    }
    
    var selectedTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(
                selectedTheme.rawValue,
                forKey: "selectedTheme"
            )
        }
    }
    
    var autoDeleteCompletedAttachments: Bool {
        didSet {
            UserDefaults.standard.set(
                autoDeleteCompletedAttachments,
                forKey: "autoDeleteCompletedAttachments"
            )
        }
    }
    
    var attachmentRetentionDays: Int {
        didSet {
            UserDefaults.standard.set(
                attachmentRetentionDays,
                forKey: "attachmentRetentionDays"
            )
        }
    }
    
    var recentlyDeletedRetentionDays: Int {
        didSet {
            UserDefaults.standard.set(
                recentlyDeletedRetentionDays,
                forKey: "recentlyDeletedRetentionDays"
            )
        }
    }
    
    var locationRemindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                locationRemindersEnabled,
                forKey: "locationRemindersEnabled"
            )
        }
    }
    
    var locationRadius: Int {
        didSet {
            UserDefaults.standard.set(
                locationRadius,
                forKey: "locationRadius"
            )
        }
    }
    
    
    private init() {
        iconStyle = .polychrome
        showBadge = true
        showAttachments = true
        showLocation = true
        showPriority = true
        showBadgeOnlyWithPriority = true
        highlightEnabled = true
        highlightColorHex = Color.red.toHex() ?? ""
        showTodayExpiredLabel = true
        selectedTaskRowStyle = 0
        dueIconEffectRaw = DueIconEffect.blink.rawValue
        taskListStyle = .plain
        showDateEveryRow = false
        confirmTaskDeletion = true
        taskWeekDays = 3
        startupTab = 1
        notificationLeadTimeDays = 1
        showWeatherForecast = true
        siriAutoReminderEnabled = true
        navigationAppID = "apple"
        backgroundColor1Hex = defaultBackColor1.toHex() ?? ""
        backgroundColor2Hex = defaultBackColor2.toHex() ?? ""
        badgeMode = 1
        showAppBadge = true
        selectedTheme = .system
        autoDeleteCompletedAttachments = true
        attachmentRetentionDays = 30
        recentlyDeletedRetentionDays = 30
        locationRemindersEnabled = false
        locationRadius = 150

        loadFromUserDefaults(.standard)
    }
}
