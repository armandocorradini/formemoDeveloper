//import EventKit
//
//final class CalendarExporter {
//    
//    private let store = EKEventStore()
//    
//    // MARK: - PUBLIC
//    
//    func export(tasks: [TodoTask], to calendar: EKCalendar, completion: @escaping (Result<Int, Error>) -> Void) {
//        
//        requestAccess { granted in
//            guard granted else {
//                completion(.failure(CalendarError.permissionDenied))
//                return
//            }
//            
//            var created = 0
//            
//            for task in tasks {
//                if self.createEvent(from: task, calendar: calendar) {
//                    created += 1
//                }
//            }
//            
//            completion(.success(created))
//        }
//    }
//}
//
//// MARK: - PRIVATE
//
//extension CalendarExporter {
//    
//    func requestAccess(_ completion: @escaping (Bool) -> Void) {
//        store.requestFullAccessToEvents { granted, error in
//            print("Granted:", granted)
//            print("Error:", error?.localizedDescription ?? "none")
//            
//            DispatchQueue.main.async {
//                completion(granted)
//            }
//        }
//    }
//    
//    func availableCalendars() -> [EKCalendar] {
//        store.calendars(for: .event)
//    }
//    
//    func defaultCalendar() -> EKCalendar? {
//        store.defaultCalendarForNewEvents
//    }
//    
//    func createEvent(from task: TodoTask, calendar: EKCalendar) -> Bool {
//        
//        guard let date = task.deadLine else { return false }
//        
//        let event = EKEvent(eventStore: store)
//        
//        event.title = task.title
//        event.notes = task.taskDescription
//        
//        // MARK: - DATE
//        
//        if isMidnight(date) {
//            event.isAllDay = true
//            event.startDate = date
//            event.endDate = date.addingTimeInterval(86400)
//        } else {
//            event.startDate = date
//            event.endDate = date.addingTimeInterval(3600)
//        }
//        
//        // MARK: - LOCATION
//        
//        if let location = task.locationName {
//            event.location = location
//        }
//        
//        // MARK: - CALENDAR
//        
//        event.calendar = calendar
//        
//        // MARK: - REMINDER
//        
//        if let reminder = task.reminderOffsetMinutes {
//            let alarm = EKAlarm(relativeOffset: TimeInterval(-reminder * 60))
//            event.addAlarm(alarm)
//        }
//        
//        // MARK: - SAVE
//        
//        do {
//            try store.save(event, span: .thisEvent)
//            return true
//        } catch {
//            print("❌ Event error:", error)
//            return false
//        }
//    }
//    
//    func isMidnight(_ date: Date) -> Bool {
//        let comp = Calendar.current.dateComponents([.hour, .minute], from: date)
//        return comp.hour == 0 && comp.minute == 0
//    }
//}
//
//// MARK: - ERROR
//
//enum CalendarError: Error {
//    case permissionDenied
//}
