import Foundation

enum DueIconEffect: String, CaseIterable, Identifiable {
    
    case none
    case blink
    case blinkIntermittent
    case rotateIntermittent
    case pulse
    
    var id: String { rawValue }
    
    var title: String {
        
        switch self {
        case .none: return String(localized: "None")
        case .blink: return String(localized: "Blink")
        case .blinkIntermittent: return String(localized: "Blink pulse")
        case .rotateIntermittent: return String(localized: "Rotate 360°")
        case .pulse: return String(localized: "Pulse")
        }
    }
}
