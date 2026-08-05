import SwiftUI

enum NotificationLeadTime: Int, CaseIterable, Identifiable {
    
    case none = -1
    case oneDay = 1
    case twoDays = 2
    case threeDays = 3
    case fourDays = 4
    case fiveDays = 5
    case sixDays = 6
    case sevenDays = 7
    
    static var selectableCases: [NotificationLeadTime] {
        return [.none, .oneDay, .twoDays, .threeDays, .fourDays, .fiveDays, .sixDays, .sevenDays]
    }
    
    init(safeRawValue: Int) {
        self = NotificationLeadTime(rawValue: safeRawValue) ?? .oneDay
    }
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .none:
            return String(localized: "None")
        case .oneDay:
            return String(localized: "1 day before")
        default:
            let days = rawValue
            return String(localized: "\(days) days before")
        }
    }
    
    var isNone: Bool {
        self == .none
    }
}
