import Foundation
import AppIntents
import SwiftData

struct SearchTasksIntent: AppIntent {
    
    static var title: LocalizedStringResource = "Search Tasks"
    
    static var description = IntentDescription(
        "Search reminders by keyword."
    )
    
    static var openAppWhenRun = false
    
    @Parameter(
        title: "Search",
        requestValueDialog: IntentDialog("What would you like to search for?")
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
        
#if DEBUG
        print("SearchTasksIntent started")
        print("Search query:", query)
#endif
        let context = ModelContext(Persistence.sharedModelContainer)
        
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !normalizedQuery.isEmpty else {
            return .result(
                dialog: IntentDialog(
                    stringLiteral: String(localized: "Please tell me what to search for.")
                )
            )
        }
        
        let descriptor = FetchDescriptor<TodoTask>()
        
        let fetchedTasks: [TodoTask]
        
        do {
            fetchedTasks = try context.fetch(descriptor)
        } catch {
            
#if DEBUG
            print("SearchTasksIntent fetch error:", error)


#endif
            return .result(
                dialog: IntentDialog(
                    stringLiteral: String(localized: "I couldn't access your reminders right now.")
                )
            )
        }
        
        let tasks = fetchedTasks
            .filter {
                !$0.isCompleted &&
                $0.title.localizedCaseInsensitiveContains(normalizedQuery)
            }
            .sorted {
                guard let leftDate = $0.deadLine,
                      let rightDate = $1.deadLine else {
                    return false
                }
                
                return leftDate < rightDate
            }
        
        guard !tasks.isEmpty else {
            return .result(
                dialog: IntentDialog(
                    stringLiteral: String(
                        localized: "I couldn't find any reminders matching \(normalizedQuery)."
                    )
                )
            )
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.autoupdatingCurrent
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.autoupdatingCurrent
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        
        let limitedTasks = Array(tasks.prefix(7))

        let calendar = Calendar.autoupdatingCurrent

        let groupedTasks = Dictionary(grouping: limitedTasks) { task in
            calendar.startOfDay(for: task.deadLine ?? Date())
        }

        let sortedDays = groupedTasks.keys.sorted()

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

                    let spokenTime = timeFormatter.string(from: deadline)
                    let at = String(localized: "date.at")

                    return "\(cleanTitle) \(at) \(spokenTime)"
                }

                return cleanTitle
            }

            guard !spokenEntries.isEmpty else {
                return nil
            }

            let spokenDate = dateFormatter.string(from: day)

            return "\(spokenDate): \(spokenEntries.joined(separator: ", "))"
        }
        
        var response = String(
            localized: "I found \(tasks.count) reminders matching \(normalizedQuery):"
        )
        
        response += " "
        response += spokenTasks.joined(separator: ". ")
        
        if tasks.count > 7 {
            let remaining = tasks.count - 7
            
            response += " "
            response += String(
                localized: "And \(remaining) more reminders in ForMemo"
            )
        }
        
        return .result(
            dialog: IntentDialog(stringLiteral: response)
        )
    }
}
