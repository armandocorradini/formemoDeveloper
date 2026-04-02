import SwiftUI

enum NotificationLeadTime: Int, CaseIterable, Identifiable {
    
    case sameDay = 0
    case oneDay = 1
    case twoDays = 2
    case threeDays = 3
    case fourDays = 4
    case fiveDays = 5
    case sixDays = 6
    case sevenDays = 7
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .sameDay:
            return String(localized: "At time of event")
        case .oneDay:
            return String(localized: "1 day before")
        default:
            // Forza la traduzione di una chiave generica usando un parametro
            return String(localized: "\(rawValue) days before")
        }
    }
}
