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
        
        print("SearchTasksIntent started")
        print("Search query:", query)
        
        let context = ModelContext(Persistence.sharedModelContainer)
        
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !normalizedQuery.isEmpty else {
            return .result(
                dialog: IntentDialog(
                    stringLiteral: "Please tell me what to search for."
                )
            )
        }
        
        let descriptor = FetchDescriptor<TodoTask>()
        
        let fetchedTasks: [TodoTask]
        
        do {
            fetchedTasks = try context.fetch(descriptor)
        } catch {
            print("SearchTasksIntent fetch error:", error)
            
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
                    stringLiteral: "I couldn't find any reminders matching \(normalizedQuery)."
                )
            )
        }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        
        let limitedTasks = Array(tasks.prefix(7))
        
        let spokenTasks = limitedTasks.compactMap { task -> String? in
            let cleanTitle = task.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !cleanTitle.isEmpty else {
                return nil
            }
            
            if let deadline = task.deadLine {
                return String(
                    localized: "\(cleanTitle) at \(formatter.string(from: deadline))"
                )
            }
            
            return cleanTitle
        }
        
        var response = String(
            localized: "I found \(tasks.count) reminders matching \(normalizedQuery):"
        )
        
        response += " "
        response += spokenTasks.joined(separator: ", ")
        
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
