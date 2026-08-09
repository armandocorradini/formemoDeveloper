import Foundation

enum AppError: LocalizedError {
    
    case remindersAccessDenied
    case calendarAccessDenied
    case generic(String)
    
    var errorDescription: String? {
        switch self {
        case .remindersAccessDenied:
            return String(localized: "error.reminders.accessDenied")
        case .calendarAccessDenied:
            return String(localized: "error.calendar.accessDenied")
        case .generic(let message):
            return message
        }
    }
    
    var isPermissionError: Bool {
        switch self {
        case .remindersAccessDenied, .calendarAccessDenied:
            return true
        default:
            return false
        }
    }
}
