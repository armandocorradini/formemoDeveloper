import AppIntents
import SwiftUI
import SwiftData
import Foundation

// MARK: - Intent

struct AddTaskIntent: AppIntent {
    
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Add a task using natural language.")
    
    @AppStorage("notificationLeadTimeDays")
    private var notificationLeadTimeDays: Int = 1
    
    // MARK: - Parameters
    
    @Parameter(
        title: "Task",
        requestValueDialog: IntentDialog("What do you want to add?")
    )
    var input: String
    
    @Parameter(
        title: "Date",
        requestValueDialog: IntentDialog("When should I schedule it?")
    )
    var date: Date
    
    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$input)")
    }
    
    // MARK: - Init intelligente
    
    init() {}
    
    init(input: String, date: Date? = nil) {
        self.input = input
        
        let parsed = NaturalLanguageParser.parse(input)
        
        if let parsedDate = parsed.date {
            self.date = parsedDate
        } else if let date {
            self.date = date
        } else {
            self.date = Date() // fallback (non verrà usato perché Siri chiederà)
        }
    }
    
    // MARK: - Perform
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        
        let context = Persistence.shared.mainContext
        let now = Date()
        
        let parsed = NaturalLanguageParser.parse(input)
        let finalTitle = parsed.title
        let dueDate = date
        
        // Validazione minima
        guard dueDate > now else {
            return .result(dialog: IntentDialog("That time is in the past."))
        }
        
        let task = TodoTask(title: finalTitle, deadLine: dueDate)
        
        let reminder = Self.computeReminder(
            now: now,
            deadline: dueDate,
            leadTimeDays: notificationLeadTimeDays
        )
        
        task.reminderOffsetMinutes = reminder.offsetMinutes
        
        context.insert(task)
        try context.save()

        
        NotificationManager.shared.refresh()
        
        let shortResponse = UserDefaults.standard.bool(forKey: "siriShortConfirmation")
        
        if shortResponse {
            return .result(dialog: "Done")
        }
        
        return .result(
            dialog: IntentDialog("Done. \(finalTitle) is scheduled. I’ll remind you \(reminder.info).")
        )
    }
}

struct NaturalLanguageParser {
    
    struct Result {
        let title: String
        let date: Date?
    }
    
    static func parse(_ input: String) -> Result {
        
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let nsRange = NSRange(input.startIndex..., in: input)
        
        var detectedDate: Date?
        var cleaned = input
        
        if let match = detector?.firstMatch(in: input, options: [], range: nsRange),
           let date = match.date {
            
            detectedDate = date
            
            if let range = Range(match.range, in: input) {
                cleaned.removeSubrange(range)
            }
        }
        
        let stopWords = [
            "add", "create", "remind me", "schedule",
            "aggiungi", "crea", "ricordami", "segnami", "metti",
            "añade", "crea", "recuérdame", "apunta", "pon",
            "ajoute", "crée", "rappelle-moi", "planifie",
            "hinzufügen", "erstelle", "erinnere mich", "plane"
        ]
        
        var title = cleaned.lowercased()
        
        for word in stopWords {
            title = title.replacingOccurrences(of: word, with: "")
        }
        
        title = title
            .replacingOccurrences(of: "[^a-zA-Z0-9àèéìòù ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return Result(
            title: title.isEmpty ? input.capitalized : title.capitalized,
            date: detectedDate
        )
    }
}

private extension AddTaskIntent {
    
    static func computeReminder(
        now: Date,
        deadline: Date,
        leadTimeDays: Int
    ) -> (offsetMinutes: Int, info: String) {
        
        let secondsRemaining = deadline.timeIntervalSince(now)
        
        guard secondsRemaining > 0 else {
            return (0, description(forMinutes: 0))
        }
        
        let rules: [(threshold: TimeInterval, offsetHours: Int)] = [
            (3600, 0),
            (4 * 3600, 1),
            (12 * 3600, 3),
            (24 * 3600, 6),
            (48 * 3600, 12),
            (7 * 24 * 3600, 24),
            (Double.infinity, 168)
        ]
        
        var baseOffsetHours = rules
            .first(where: { secondsRemaining <= $0.threshold })?
            .offsetHours ?? 0
        
        if leadTimeDays == 0 {
            baseOffsetHours = (secondsRemaining > 3600) ? 1 : 0
        } else {
            let maxAllowedHours = leadTimeDays * 24
            baseOffsetHours = min(baseOffsetHours, maxAllowedHours)
            
            if baseOffsetHours == maxAllowedHours && baseOffsetHours > 0 {
                baseOffsetHours -= min(6, baseOffsetHours)
            }
        }
        
        if Double(baseOffsetHours * 3600) >= secondsRemaining {
            baseOffsetHours = 0
        }
        
        guard baseOffsetHours > 0 else {
            return (0, description(forMinutes: 0))
        }
        
        let calendar = Calendar.autoupdatingCurrent
        
        guard let baseReminderDate = calendar.date(
            byAdding: .hour,
            value: -baseOffsetHours,
            to: deadline
        ) else {
            return (baseOffsetHours * 60, description(forMinutes: baseOffsetHours * 60))
        }
        
        let finalReminderDate: Date = {
            if isNight(date: baseReminderDate, calendar: calendar) {
                return adjustedDateAvoidingNight(
                    from: baseReminderDate,
                    deadline: deadline,
                    calendar: calendar
                ) ?? baseReminderDate
            } else {
                return baseReminderDate
            }
        }()
        
        guard finalReminderDate > now else {
            return (0, description(forMinutes: 0))
        }
        
        let offsetMinutes = max(
            Int(deadline.timeIntervalSince(finalReminderDate) / 60),
            0
        )
        
        return (offsetMinutes, description(forMinutes: offsetMinutes))
    }
    
    static func isNight(date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 22 || hour < 7
    }
    
    static func adjustedDateAvoidingNight(
        from date: Date,
        deadline: Date,
        calendar: Calendar
    ) -> Date? {
        
        let hour = calendar.component(.hour, from: date)
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        
        if hour >= 22 {
            components.hour = 21
            components.minute = 0
        } else if hour < 7 {
            components.hour = 7
            components.minute = 0
        }
        
        guard let candidate = calendar.date(from: components),
              candidate < deadline else {
            return nil
        }
        
        return candidate
    }
    
    static func description(forMinutes minutes: Int) -> String {
        
        if minutes == 0 {
            return String(localized: "At time of event")
        }
        
        if minutes < 60 {
            return String(localized: "\(minutes) minutes before")
        }
        
        let hours = minutes / 60
        
        if hours == 1 {
            return String(localized: "one hour before")
        }
        
        if hours < 24 {
            return String(localized: "\(hours) hours before")
        }
        
        let days = hours / 24
        
        return days == 1
        ? String(localized: "1 day before")
        : String(localized: "\(days) days before")
    }
}



