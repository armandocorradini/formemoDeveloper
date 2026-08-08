import Foundation

enum SystemEventHistory {

    private static let key = "SystemEventHistory"

    private static let maximumEvents = 100

    static func add(_ event: SystemEvent) {

        var events = all()
        
        if let last = events.first,
           last.sessionID == event.sessionID,
           last.category == event.category,
           last.event == event.event,
           last.details == event.details {

            return

        }

        events.insert(event, at: 0)

        if events.count > maximumEvents {
            events.removeLast(events.count - maximumEvents)
        }

        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: key)
        }

    }

    static func all() -> [SystemEvent] {

        guard
            let data = UserDefaults.standard.data(forKey: key),
            let events = try? JSONDecoder().decode(
                [SystemEvent].self,
                from: data
            )
        else {

            return []

        }

        return events

    }
    
    static func currentSession() -> [SystemEvent] {

        all().filter {

            $0.sessionID == DebugLog.sessionID

        }

    }

    static func clear() {

        UserDefaults.standard.removeObject(forKey: key)

    }

}


struct SystemEvent: Codable, Identifiable {

    let id: UUID

    let sessionID: String

    let date: Date

    let category: Category

    let event: Event

    let result: Result

    let details: String?

}

enum Category: String, Codable {

    case assetRecovery

    case attachment

    case wallet

    case document

    case backup

    case restore

    case cloudKit

    case migration

    case vault

}

enum Event: String, Codable {

    case detected

    case started

    case completed

    case cancelled

    case skipped

    case failed

}

enum Result: String, Codable {

    case success

    case warning

    case failure

}

