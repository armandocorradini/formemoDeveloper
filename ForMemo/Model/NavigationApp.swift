import SwiftUI

//enum NavigationApp: String, CaseIterable, Identifiable, Hashable {
//    case appleMaps
//    case googleMaps
//    
//    var id: String { rawValue }
//    
//    var title: String {
//        switch self {
//        case .appleMaps: return "Apple Maps"
//        case .googleMaps: return "Google Maps"
//        }
//    }
//}

struct NavigationApp: Identifiable, Hashable {

    let id: String
    let title: String
    let scheme: String?

    static let appleMaps = NavigationApp(
        id: "apple",
        title: "Apple Maps",
        scheme: nil
    )

    static let googleMaps = NavigationApp(
        id: "google",
        title: "Google Maps",
        scheme: "comgooglemaps://"
    )

    static let waze = NavigationApp(
        id: "waze",
        title: "Waze",
        scheme: "waze://"
    )

    static let chooseApp = NavigationApp(
        id: "chooser",
        title: String(localized: "Choose Every Time"),
        scheme: nil
    )

}
extension NavigationApp {

    static let allApps: [NavigationApp] = [
        .appleMaps,
        .googleMaps,
        .waze,
        .chooseApp,

    ]

    static func app(for id: String) -> NavigationApp {
        allApps.first(where: { $0.id == id })
            ?? .appleMaps
    }
}

extension NavigationApp {

    static var availableApps: [NavigationApp] {

        allApps.filter { app in

            guard let scheme = app.scheme else {
                return true
            }

            guard let url = URL(string: scheme) else {
                return false
            }

            return UIApplication.shared.canOpenURL(url)
        }
    }
}
