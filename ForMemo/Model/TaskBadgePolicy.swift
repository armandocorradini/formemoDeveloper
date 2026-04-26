import Foundation
import SwiftData

struct TaskBadgePolicy {
    
    static func badgeCount(
        tasks: [TodoTask],
        referenceDate: Date
    ) -> Int {
        
        tasks.reduce(0) { count, task in
            
            guard !task.isCompleted,
                  let deadline = task.deadLine else {
                return count
            }

            if deadline <= referenceDate {
                // 🔵 Option B: always count overdue tasks, even if snoozed
                return count + 1
            }
            
            return count
        }
    }
}
