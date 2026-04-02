import Foundation
import SwiftData

struct TaskBadgePolicy {
    
    static func badgeCount(
        tasks: [TodoTask],
        referenceDate: Date,
        leadDays: Int,
        includeExpired: Bool
    ) -> Int {
        
        let calendar = Calendar.autoupdatingCurrent
        
        return tasks.reduce(0) { count, task in
            
            guard !task.isCompleted,
                  let deadline = task.deadLine,
                  let trigger = calendar.date(
                    byAdding: .day,
                    value: -leadDays,
                    to: deadline
                  )
            else { return count }
            
            if includeExpired {
                return referenceDate >= trigger ? count + 1 : count
            } else {
                return (referenceDate >= trigger && referenceDate <= deadline)
                ? count + 1
                : count
            }
        }
    }
}

