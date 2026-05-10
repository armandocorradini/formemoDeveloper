import Foundation
import AppIntents
import SwiftData


struct GetTasksIntent: AppIntent {
    
    static var title: LocalizedStringResource = LocalizedStringResource("Get Tasks")
    
    static var description = IntentDescription(
        LocalizedStringResource("Get tasks for a selected period.")
    )
    
    static var openAppWhenRun = false
    
    @Parameter(
        title: LocalizedStringResource("Query"),
        requestValueDialog: IntentDialog(
            stringLiteral: String(localized: "Which period or date would you like to check?")
        )
    )
    var query: String
    
    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$query
        }
    }
    
    init() {}
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        
        print("GetTasksIntent started")
        // print("Requested date:", targetDate as Any) // removed as targetDate is gone
        
        let context = ModelContext(Persistence.sharedModelContainer)
        let calendar = Calendar.autoupdatingCurrent

        let normalizedQuery = query
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let referenceDate: Date
        let dateInterval: DateInterval

        if [
            // EN
            "today",

            // IT
            "oggi",

            // FR
            "aujourd hui", "aujourd'hui",

            // ES
            "hoy",

            // DE
            "heute"
        ].contains(where: { normalizedQuery.contains($0) }) {

            referenceDate = Date()

            let start = calendar.startOfDay(for: referenceDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!

            dateInterval = DateInterval(start: start, end: end)

        } else if [
            // EN
            "tomorrow",

            // IT
            "domani",

            // FR
            "demain",

            // ES
            "manana", "mañana",

            // DE
            "morgen"
        ].contains(where: { normalizedQuery.contains($0) }) {

            referenceDate = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()

            let start = calendar.startOfDay(for: referenceDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!

            dateInterval = DateInterval(start: start, end: end)

        } else if [
            // EN
            "day after tomorrow",

            // IT
            "dopodomani",

            // FR
            "apres demain", "après demain",

            // ES
            "pasado manana", "pasado mañana",

            // DE
            "ubermorgen", "übermorgen"
        ].contains(where: { normalizedQuery.contains($0) }) {

            referenceDate = calendar.date(byAdding: .day, value: 2, to: Date()) ?? Date()

            let start = calendar.startOfDay(for: referenceDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!

            dateInterval = DateInterval(start: start, end: end)

        } else if [
            // EN
            "next weekend",

            // IT
            "prossimo weekend", "weekend prossimo", "prossimo fine settimana",

            // FR
            "week end prochain", "weekend prochain",

            // ES
            "proximo fin de semana", "próximo fin de semana",
            "el próximo fin de semana",

            // DE
            "nachstes wochenende", "nächstes wochenende"
        ].contains(where: { normalizedQuery.contains($0) }) {

            let next = calendar.nextWeekend(startingAfter: Date())?.end ?? Date()
            referenceDate = calendar.nextWeekend(startingAfter: next)?.start ?? Date()

            dateInterval = calendar.dateIntervalOfWeekend(containing: referenceDate) ?? DateInterval(start: referenceDate, end: calendar.date(byAdding: .day, value: 2, to: referenceDate)!)

        } else if [
            // EN
            "weekend",

            // IT
            "weekend", "fine settimana",

            // FR
            "week end", "weekend",

            // ES
            "fin de semana",
            "el fin de semana",

            // DE
            "wochenende"
        ].contains(where: { normalizedQuery.contains($0) }) {

            referenceDate = calendar.nextWeekend(startingAfter: Date())?.start ?? Date()

            dateInterval = calendar.dateIntervalOfWeekend(containing: referenceDate) ?? DateInterval(start: referenceDate, end: calendar.date(byAdding: .day, value: 2, to: referenceDate)!)

        } else if [
            // EN
            "next week",

            // IT
            "prossima settimana","settimana prossima",

            // FR
            "semaine prochaine",

            // ES
            "proxima semana", "próxima semana",
            "la próxima semana",

            // DE
            "nächste woche", "nachste woche"
        ].contains(where: { normalizedQuery.contains($0) }) {

            referenceDate = calendar.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()

            dateInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate)!

        } else if [
            // EN
            "this week",

            // IT
            "questa settimana",

            // FR
            "cette semaine",

            // ES
            "esta semana",
            "la semana actual",

            // DE
            "diese woche"
        ].contains(where: { normalizedQuery.contains($0) }) {

            referenceDate = Date()

            dateInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate)!

        } else {

            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
            let nsRange = NSRange(normalizedQuery.startIndex..., in: normalizedQuery)

            guard let match = detector?.firstMatch(in: normalizedQuery, options: [], range: nsRange),
                  let detectedDate = match.date else {

                return .result(
                    dialog: IntentDialog(
                        stringLiteral: String(localized: "I couldn't understand the date or period.")
                    )
                )
            }

            referenceDate = detectedDate

            let start = calendar.startOfDay(for: referenceDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!

            dateInterval = DateInterval(start: start, end: end)
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
            switch ($0.deadLine, $1.deadLine) {
            case let (leftDate?, rightDate?):
                return leftDate < rightDate

            case (_?, nil):
                return true

            case (nil, _?):
                return false

            default:
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        let dateFormatterForTasks = DateFormatter()
        dateFormatterForTasks.locale = Locale.autoupdatingCurrent
        dateFormatterForTasks.setLocalizedDateFormatFromTemplate("EEEE d MMM")

        let limitedTasks = Array(tasks.prefix(7))
        let calendarForGrouping = Calendar.autoupdatingCurrent

        let groupedTasks = Dictionary(grouping: limitedTasks) { task in
            calendarForGrouping.startOfDay(for: task.deadLine ?? Date())
        }

        let sortedDays = groupedTasks.keys.sorted()

        let singleDayInterval = calendarForGrouping.isDate(
            intervalStart,
            inSameDayAs: calendar.date(byAdding: .second, value: -1, to: intervalEnd) ?? intervalStart
        )

        let spokenTasks = sortedDays.compactMap { day -> String? in

            guard let tasksForDay = groupedTasks[day] else {
                return nil
            }

            let sortedTasks = tasksForDay.sorted {
                ($0.deadLine ?? .distantFuture) < ($1.deadLine ?? .distantFuture)
            }

            let spokenEntries = sortedTasks.compactMap { task -> String? in

                let cleanTitle = task.title
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !cleanTitle.isEmpty else {
                    return nil
                }

                if let deadline = task.deadLine {

                    let spokenTaskTime = timeFormatter.string(from: deadline)

                    return String(
                        format: NSLocalizedString(
                            "%1$@ at %2$@",
                            comment: "Task spoken format without repeated date"
                        ),
                        cleanTitle,
                        spokenTaskTime
                    )
                }

                return cleanTitle
            }

            guard !spokenEntries.isEmpty else {
                return nil
            }

            if singleDayInterval {

                return spokenEntries.joined(separator: ", ")

            } else {

                let spokenTaskDate = dateFormatterForTasks.string(from: day)

                return String(
                    format: NSLocalizedString(
                        "%1$@: %2$@",
                        comment: "Grouped tasks for day"
                    ),
                    spokenTaskDate,
                    spokenEntries.joined(separator: ", ")
                )
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let spokenDate: String

        if ["today", "oggi", "aujourd hui", "aujourd'hui", "hoy", "heute"]
            .contains(where: { normalizedQuery.contains($0) }) {
            spokenDate = String(localized: "today")
        } else if ["tomorrow", "domani", "demain", "manana", "mañana", "morgen"]
            .contains(where: { normalizedQuery.contains($0) }) {
            spokenDate = String(localized: "tomorrow")
        } else if ["day after tomorrow", "dopodomani", "apres demain", "après demain", "pasado manana", "pasado mañana", "ubermorgen", "übermorgen"]
            .contains(where: { normalizedQuery.contains($0) }) {
            spokenDate = String(localized: "day after tomorrow")
        } else {
            spokenDate = query
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
        response += spokenTasks.joined(separator: ". ")

        let remainingTasks = Array(tasks.dropFirst(7))

        let remainingCriticalCount = remainingTasks.filter {
            $0.priority == .critical
        }.count

        if tasks.count > 7 {

            let remaining = tasks.count - 7

            response += " "

            if remainingCriticalCount > 0 {

                response += String(
                    format: NSLocalizedString(
                        "And %1$lld more reminders in ForMemo, including %2$lld critical.",
                        comment: "Additional reminders including critical"
                    ),
                    remaining,
                    remainingCriticalCount
                )

            } else {

                response += String(
                    format: NSLocalizedString(
                        "And %lld more reminders in ForMemo",
                        comment: "Additional reminders count"
                    ),
                    remaining
                )
            }
        }

        return .result(
            dialog: IntentDialog(stringLiteral: response)
        )
    }
}
