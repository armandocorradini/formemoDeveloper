import EventKit

final class CalendarExportEngine {
    
    private static let sharedStore = EKEventStore()
    private var store: EKEventStore { Self.sharedStore }
    
    // MARK: - PERMISSION
    
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
                        userInfo: [
                            NSLocalizedDescriptionKey: String(localized: "error.calendar.accessDenied")
                        ]
                    ))
                    return
                }
                
                cont.resume()
            }
        }
    }
    
    // MARK: - EXPORT
    
    func export(
        items: [TaskTransferObject],
        to calendar: EKCalendar
    ) throws -> Int {
        
        var count = 0
        
        // 🔍 Range eventi esistenti
        let start = Date().addingTimeInterval(-60 * 60 * 24 * 365) // -1 anno
        let end = Date().addingTimeInterval(60 * 60 * 24 * 365 * 2) // +2 anni
        
        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: [calendar]
        )
        
        let existingEvents = store.events(matching: predicate)
        
        // 🔐 chiavi uniche eventi già presenti
        var existingKeys = Set(existingEvents.map {
            "\(($0.title ?? "").lowercased())|\($0.startDate.timeIntervalSince1970)"
        })
        
        // 🚀 export
        
        for item in items {
            
            guard let date = item.deadline else { continue }
            
            let key = "\(item.title.lowercased())|\(date.timeIntervalSince1970)"
            
            // 🚫 skip duplicati
            if existingKeys.contains(key) { continue }
            
            let event = EKEvent(eventStore: store)
            
            event.title = item.title
            event.notes = item.description
            event.startDate = date
            
            // 🔥 ALL DAY vs NORMAL
            
            if Calendar.current.component(.hour, from: date) == 0 &&
               Calendar.current.component(.minute, from: date) == 0 {
                
                event.isAllDay = true
                event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: date)
                
            } else {
                
                event.endDate = Calendar.current.date(byAdding: .minute, value: 30, to: date)
            }
            
            event.calendar = calendar
            
            // 🔔 REMINDER
            
            if let minutes = item.reminderOffsetMinutes {
                let alarm = EKAlarm(relativeOffset: TimeInterval(-minutes * 60))
                event.addAlarm(alarm)
            }
            
            // 💾 SAVE
            
            try store.save(event, span: .thisEvent)
            
            // 🔁 aggiorna set → evita duplicati nella stessa sessione
            existingKeys.insert(key)
            
            count += 1
        }
        
        return count
    }
    
    // MARK: - HELPERS
    
    func defaultCalendar() -> EKCalendar? {
        store.defaultCalendarForNewEvents
    }
    
    func availableCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
    }
}
