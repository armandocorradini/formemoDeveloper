import SwiftUI

enum NavigationApp: String, CaseIterable, Identifiable, Hashable {
    case appleMaps
    case googleMaps
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .appleMaps: return "Apple Maps"
        case .googleMaps: return "Google Maps"
        }
    }
}

