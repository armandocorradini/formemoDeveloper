import SwiftUI

let backColor1 = Color(

    red: 0.42,

    green: 0.64,

    blue: 1.0

).opacity(0.52)

let backColor2 = Color(

    red: 0.76,

    green: 0.58,

    blue: 1.0

).opacity(0.42)

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
