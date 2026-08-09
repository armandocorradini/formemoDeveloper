
import Foundation
import SwiftUI

enum SurfaceBorderStyle: Int, CaseIterable, Codable, Sendable, Identifiable {
    case off
    case hairline
    case thin
    case medium

    var id: Self { self }

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .off: return "Off"
        case .hairline: return "Hairline"
        case .thin: return "Thin"
        case .medium: return "Medium"
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .off: return 0
        case .hairline: return 0.5
        case .thin: return 1
        case .medium: return 2
        }
    }
}



enum SurfaceMaterialStyle: Int, CaseIterable, Codable, Sendable, Identifiable {
    case none
    case transparent
    case soft
    case medium
    case strong
    case extraStrong

    var id: Self { self }

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .none:        return "None"
        case .transparent: return "Transparent"
        case .soft:        return "Soft"
        case .medium:      return "Medium"
        case .strong:      return "Strong"
        case .extraStrong: return "Extra Strong"
        }
    }
}

struct SurfaceSettings: Codable, Sendable {

    var cornerRadius: Double = 22

    var border: SurfaceBorderStyle = .hairline

    var material: SurfaceMaterialStyle = .strong
}


extension SurfaceMaterialStyle {

    var shapeStyle: AnyShapeStyle {
        switch self {
        case .none:
            return AnyShapeStyle(Color(.systemBackground))
        case .transparent:
            return AnyShapeStyle(Color.clear)
        case .soft:
            return AnyShapeStyle(.ultraThinMaterial)
        case .medium:
            return AnyShapeStyle(.thinMaterial)
        case .strong:
            return AnyShapeStyle(.regularMaterial)
        case .extraStrong:
            return AnyShapeStyle(.thickMaterial)
        }
    }
}
