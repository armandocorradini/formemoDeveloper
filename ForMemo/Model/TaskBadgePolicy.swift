import Foundation
import SwiftData

struct TaskBadgePolicy {
    
    static func badgeCount(
        tasks: [TodoTask],
        referenceDate: Date
    ) -> Int {

        let badgeMode = UserDefaults.standard.integer(forKey: "badgeMode")
        let leadDays = UserDefaults.standard.integer(forKey: "notificationLeadTimeDays")

        return tasks.reduce(0) { count, task in

            guard !task.isCompleted,
                  let deadline = task.deadLine else {
                return count
            }

            // 🔵 Classic mode → badge only at deadline
            if badgeMode == 0 {

                if deadline <= referenceDate {
                    return count + 1
                }

                return count
            }

            // 🔵 Global notification mode
            if leadDays > 0 {

                let triggerDate = Calendar.current.date(
                    byAdding: .day,
                    value: -leadDays,
                    to: deadline
                ) ?? deadline

                if triggerDate <= referenceDate {
                    return count + 1
                }

                return count
            }

            // fallback
            if deadline <= referenceDate {
                return count + 1
            }

            return count
        }
    }
}
