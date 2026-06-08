import SwiftUI

let backColor1 = Color(uiColor: UIColor { trait in
    if trait.userInterfaceStyle == .dark {
        return UIColor(
            red: 0.42,
            green: 0.64,
            blue: 1.0,
            alpha: 0.52
        )
    } else {
        return UIColor(
            red: 0.16,
            green: 0.48,
            blue: 1.00,
            alpha: 0.38
        )
    }
})

let backColor2 = Color(uiColor: UIColor { trait in
    if trait.userInterfaceStyle == .dark {
        return UIColor(
            red: 0.76,
            green: 0.58,
            blue: 1.0,
            alpha: 0.42
        )
    } else {
        return UIColor(
            red: 0.82,
            green: 0.38,
            blue: 1.00,
            alpha: 0.30
        )
    }
})

// Ricava il display name dell'app
let appName: String = {
    
    let bundle = Bundle.main
    
    return bundle.infoDictionary?["CFBundleDisplayName"] as? String
    ?? bundle.infoDictionary?["CFBundleName"] as? String
    ?? "App"
}()



import UIKit

enum AppSettingsOpener {
    
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
