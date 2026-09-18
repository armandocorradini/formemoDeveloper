
import Foundation
import SwiftData

struct TaskBadgePolicy {

    // MARK: - Optimized Index

    struct Index {

        private let dates: [Date]

        init(tasks: [TodoTask]) {

            let badgeMode = UserDefaults.standard.integer(
                forKey: "badgeMode"
            )

            let leadDays = UserDefaults.standard.integer(
                forKey: "notificationLeadTimeDays"
            )

            var dates: [Date] = []
            dates.reserveCapacity(tasks.count)

            for task in tasks {

                guard !task.isCompleted,
                      let deadline = task.deadLine else {
                    continue
                }

                // Classic mode → badge only at deadline
                if badgeMode == 0 {
                    dates.append(deadline)
                    continue
                }

                // Global notification mode
                if leadDays > 0 {
                    let triggerDate = Calendar.current.date(
                        byAdding: .day,
                        value: -leadDays,
                        to: deadline
                    ) ?? deadline

                    dates.append(triggerDate)
                    continue
                }

                // Fallback
                dates.append(deadline)
            }

            self.dates = dates.sorted()
        }

        /// Numero di Task che devono risultare nel badge
        /// alla data indicata.
        func count(at referenceDate: Date) -> Int {

            var low = 0
            var high = dates.count

            // Upper bound:
            // conta tutte le date <= referenceDate.
            while low < high {
                let mid = low + (high - low) / 2

                if dates[mid] <= referenceDate {
                    low = mid + 1
                } else {
                    high = mid
                }
            }

            return low
        }
    }

    // MARK: - Compatibility API

    static func badgeCount(
        tasks: [TodoTask],
        referenceDate: Date
    ) -> Int {

        Index(tasks: tasks).count(at: referenceDate)
    }
}












//import Foundation
//import SwiftData
//
//struct TaskBadgePolicy {
//    
//    static func badgeCount(
//        tasks: [TodoTask],
//        referenceDate: Date
//    ) -> Int {
//
//        let badgeMode = UserDefaults.standard.integer(forKey: "badgeMode")
//        let leadDays = UserDefaults.standard.integer(forKey: "notificationLeadTimeDays")
//
//        return tasks.reduce(0) { count, task in
//
//            guard !task.isCompleted,
//                  let deadline = task.deadLine else {
//                return count
//            }
//
//            // 🔵 Classic mode → badge only at deadline
//            if badgeMode == 0 {
//
//                if deadline <= referenceDate {
//                    return count + 1
//                }
//
//                return count
//            }
//
//            // 🔵 Global notification mode
//            if leadDays > 0 {
//
//                let triggerDate = Calendar.current.date(
//                    byAdding: .day,
//                    value: -leadDays,
//                    to: deadline
//                ) ?? deadline
//
//                if triggerDate <= referenceDate {
//                    return count + 1
//                }
//
//                return count
//            }
//
//            // fallback
//            if deadline <= referenceDate {
//                return count + 1
//            }
//
//            return count
//        }
//    }
//}
