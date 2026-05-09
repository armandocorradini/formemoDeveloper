import Foundation
import AppIntents
import SwiftData

enum TaskPeriod: String, AppEnum {
    
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Period")
    )
    
    static var caseDisplayRepresentations: [TaskPeriod: DisplayRepresentation] = [
        .today: DisplayRepresentation(title: LocalizedStringResource("Today")),
        .tomorrow: DisplayRepresentation(title: LocalizedStringResource("Tomorrow")),
        .weekend: DisplayRepresentation(title: LocalizedStringResource("Weekend")),
        .thisWeekend: DisplayRepresentation(title: LocalizedStringResource("This Weekend")),
        .nextWeekend: DisplayRepresentation(title: LocalizedStringResource("Next Weekend")),
        .thisWeek: DisplayRepresentation(title: LocalizedStringResource("This Week")),
        .nextWeek: DisplayRepresentation(title: LocalizedStringResource("Next Week")),
        .customDate: DisplayRepresentation(title: LocalizedStringResource("Specific Day"))
    ]
    
    case today
    case tomorrow
    case weekend
    case thisWeekend
    case nextWeekend
    case thisWeek
    case nextWeek
    case customDate
}

struct GetTasksIntent: AppIntent {
    
    static var title: LocalizedStringResource = LocalizedStringResource("Get Tasks")
    
    static var description = IntentDescription(
        LocalizedStringResource("Get tasks for a selected period.")
    )
    
    static var openAppWhenRun = false
    
    @Parameter(
        title: LocalizedStringResource("Period"),
        requestValueDialog: IntentDialog(
            stringLiteral: String(localized: "Which period would you like to check? Today, tomorrow, weekend, or next week?")
        )
    )
    var period: TaskPeriod
    
    @Parameter(
        title: LocalizedStringResource("Date"),
        requestValueDialog: IntentDialog(
            stringLiteral: String(localized: "Which specific day would you like to check?")
        )
    )
    var customDate: Date?
    
    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$period
            \.$customDate
        }
    }
    
    init() {}
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        
        print("GetTasksIntent started")
        print("Requested date:", customDate as Any)
        
        let context = ModelContext(Persistence.sharedModelContainer)
        let calendar = Calendar.autoupdatingCurrent

        let now = Date()
        
        let referenceDate: Date
        
        switch period {
        case .today:
            referenceDate = now
            
        case .tomorrow:
            referenceDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            
        case .weekend, .thisWeekend:
            referenceDate = calendar.nextWeekend(startingAfter: now)?.start ?? now
            
        case .nextWeekend:
            let next = calendar.nextWeekend(startingAfter: now)?.end ?? now
            referenceDate = calendar.nextWeekend(startingAfter: next)?.start ?? now
            
        case .thisWeek:
            referenceDate = now
            
        case .nextWeek:
            referenceDate = calendar.date(byAdding: .weekOfYear, value: 1, to: now) ?? now
            
        case .customDate:
            guard let customDate else {
                throw $customDate.needsValueError()
            }
            referenceDate = customDate
        }

        let dateInterval: DateInterval

        switch period {
        case .today, .tomorrow, .customDate:
            let startOfDay = calendar.startOfDay(for: referenceDate)
            let endOfDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: startOfDay
            )!

            dateInterval = DateInterval(
                start: startOfDay,
                end: endOfDay
            )

        case .weekend, .thisWeekend:
            if let weekendInterval = calendar.dateIntervalOfWeekend(containing: referenceDate) {
                dateInterval = weekendInterval
            } else {
                let startOfDay = calendar.startOfDay(for: referenceDate)

                dateInterval = DateInterval(
                    start: startOfDay,
                    end: calendar.date(byAdding: .day, value: 2, to: startOfDay)!
                )
            }

        case .nextWeekend:
            if let weekendInterval = calendar.dateIntervalOfWeekend(containing: referenceDate) {
                dateInterval = weekendInterval
            } else {
                let startOfDay = calendar.startOfDay(for: referenceDate)

                dateInterval = DateInterval(
                    start: startOfDay,
                    end: calendar.date(byAdding: .day, value: 2, to: startOfDay)!
                )
            }

        case .thisWeek, .nextWeek:
            if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) {
                dateInterval = weekInterval
            } else {
                let startOfDay = calendar.startOfDay(for: referenceDate)

                dateInterval = DateInterval(
                    start: startOfDay,
                    end: calendar.date(byAdding: .day, value: 7, to: startOfDay)!
                )
            }
        }

        let intervalStart = dateInterval.start
        let intervalEnd = dateInterval.end

        let predicate = #Predicate<TodoTask> { task in
            if let deadline = task.deadLine {
                return task.isCompleted == false &&
                       deadline >= intervalStart &&
                       deadline < intervalEnd
            } else {
                return false
            }
        }

        let descriptor = FetchDescriptor<TodoTask>(
            predicate: predicate
        )

        let fetchedTasks: [TodoTask]

        do {
            fetchedTasks = try context.fetch(descriptor)
        } catch {
            print("GetTasksIntent fetch error:", error)
            
            return .result(
                dialog: IntentDialog(
                    stringLiteral: String(localized: "I couldn't access your reminders right now.")
                )
            )
        }

        let tasks = fetchedTasks.sorted {
            guard let leftDate = $0.deadLine,
                  let rightDate = $1.deadLine else {
                return false
            }
            
            return leftDate < rightDate
        }

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        let dateFormatterForTasks = DateFormatter()
        dateFormatterForTasks.dateStyle = .short
        dateFormatterForTasks.timeStyle = .none

        let criticalTasks = tasks.filter {
            $0.priority == .critical
        }

        let regularTasks = tasks.filter {
            $0.priority != .critical
        }

        var limitedTasks: [TodoTask] = criticalTasks

        let remainingSlots = max(0, 7 - criticalTasks.count)
        limitedTasks += regularTasks.prefix(remainingSlots)

        let spokenTasks = limitedTasks.compactMap { task -> String? in
            let cleanTitle = task.title
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            guard !cleanTitle.isEmpty else {
                return nil
            }
            
            if let deadline = task.deadLine {
                let spokenTaskDate = dateFormatterForTasks.string(from: deadline)
                let spokenTaskTime = timeFormatter.string(from: deadline)
                
                return String(
                    format: NSLocalizedString(
                        "%1$@ on %2$@ at %3$@",
                        comment: "Task spoken format"
                    ),
                    cleanTitle,
                    spokenTaskDate,
                    spokenTaskTime
                )
            }
            
            return cleanTitle
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let spokenDate: String

        switch period {
        case .today:
            spokenDate = String(localized: "today")

        case .tomorrow:
            spokenDate = String(localized: "tomorrow")

        case .weekend:
            spokenDate = String(localized: "weekend")

        case .thisWeekend:
            spokenDate = String(localized: "this weekend")

        case .nextWeekend:
            spokenDate = String(localized: "next weekend")

        case .thisWeek:
            spokenDate = String(localized: "this week")

        case .nextWeek:
            spokenDate = String(localized: "next week")

        case .customDate:
            spokenDate = dateFormatter.string(from: referenceDate)
        }

        guard !tasks.isEmpty else {
            return .result(
                dialog: IntentDialog(
                    stringLiteral: String(localized: "You have nothing planned for \(spokenDate).")
                )
            )
        }

        var response = String(
            format: NSLocalizedString(
                "Here’s what’s planned for %1$@:",
                comment: "Tasks intro"
            ),
            spokenDate
        )
        
        response += " "
        response += spokenTasks.joined(separator: ", ")

        if tasks.count > 7 {
            let remaining = tasks.count - 7
            
            response += " "
            response += String(
                format: NSLocalizedString(
                    "And %lld more reminders in ForMemo",
                    comment: "Additional reminders count"
                ),
                remaining
            )
        }

        return .result(
            dialog: IntentDialog(stringLiteral: response)
        )
    }
}
