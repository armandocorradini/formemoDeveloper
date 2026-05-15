import Foundation

struct TaskDaySection: Identifiable {
    
    let id: Date
    let date: Date
    let tasks: [TodoTask]
    
    init(date: Date, tasks: [TodoTask]) {
        self.id = Calendar.current.startOfDay(for: date)
        self.date = Calendar.current.startOfDay(for: date)
        self.tasks = tasks
    }
}

enum TaskRowPosition {
    case single
    case first
    case middle
    case last
}

extension TaskDaySection {
    
    static func grouped(from tasks: [TodoTask]) -> [TaskDaySection] {
        
        let calendar = Calendar.current
        
        let grouped = Dictionary(grouping: tasks) { task in
            calendar.startOfDay(for: task.deadLine ?? .now)
        }
        
        return grouped
            .map { date, tasks in
                TaskDaySection(
                    date: date,
                    tasks: tasks.sorted {
                        ($0.deadLine ?? .distantFuture) < ($1.deadLine ?? .distantFuture)
                    }
                )
            }
            .sorted { $0.date < $1.date }
    }
}

extension TaskDaySection {
    
    static func rowPosition(index: Int, total: Int) -> TaskRowPosition {
        
        if total <= 1 {
            return .single
        }
        
        if index == 0 {
            return .first
        }
        
        if index == total - 1 {
            return .last
        }
        
        return .middle
    }
}
