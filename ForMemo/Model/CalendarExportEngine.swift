import EventKit

final class CalendarExportEngine {
    
    private static let sharedStore = EKEventStore()
    private var store: EKEventStore { Self.sharedStore }
    
    func requestAccess() async throws {
        
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            
            store.requestFullAccessToEvents { granted, error in
                
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                
                guard granted else {
                    cont.resume(throwing: NSError(
                        domain: "Calendar",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Access denied"]
                    ))
                    return
                }
                
                cont.resume()
            }
        }
    }
    
    func export(
        items: [TaskTransferObject],
        to calendar: EKCalendar
    ) throws -> Int {
        
        var count = 0
        let start = Date().addingTimeInterval(-60 * 60 * 24 * 365)
        let end = Date().addingTimeInterval(60 * 60 * 24 * 365)

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        let existingEvents = store.events(matching: predicate)

        let existingKeys = Set(existingEvents.map {
            "\($0.title ?? "")-\($0.startDate?.timeIntervalSince1970 ?? 0)"
        })
        
        
        
        for item in items {
            
            guard let date = item.deadline else { continue }
            
            let key = "\(item.title)-\(date.timeIntervalSince1970)"

            if existingKeys.contains(key) {
                continue // 🚫 skip duplicato
            }
            
            let event = EKEvent(eventStore: store)
            
            event.title = item.title
            event.notes = item.description

            event.startDate = date

            // 🔥 END DATE OBBLIGATORIA + ALL DAY LOGIC
            if Calendar.current.component(.hour, from: date) == 0 &&
               Calendar.current.component(.minute, from: date) == 0 {
                
                // all-day event
                event.isAllDay = true
                event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: date)
                
            } else {
                
                // normal event
                event.endDate = Calendar.current.date(byAdding: .minute, value: 30, to: date)
            }
            
            event.calendar = calendar
            
            // 🔔 reminder
            if let minutes = item.reminderOffsetMinutes {
                let alarm = EKAlarm(relativeOffset: TimeInterval(-minutes * 60))
                event.addAlarm(alarm)
            }
            
            try store.save(event, span: .thisEvent)
            count += 1
        }
        
        return count
    }
    
    func defaultCalendar() -> EKCalendar? {
        store.defaultCalendarForNewEvents
    }
    
    func availableCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
    }
}
