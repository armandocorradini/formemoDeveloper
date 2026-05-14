import SwiftUI


//let backColor1: Color = .blue.opacity(0.4)
//let backColor2: Color = .purple.opacity(0.2)

//let backColor1: Color = Color(red: 0.78, green: 0.86, blue: 1.0).opacity(0.35)
//let backColor2: Color = Color(red: 0.92, green: 0.88, blue: 1.0).opacity(0.22)

//let backColor1: Color = .white.opacity(0.20)
//let backColor2: Color = Color.blue.opacity(0.10)
//
//let backColor1: Color = Color(
//    red: 0.52,
//    green: 0.68,
//    blue: 1.0
//).opacity(0.28)
//
//let backColor2: Color = Color(
//    red: 0.72,
//    green: 0.78,
//    blue: 1.0
//).opacity(0.18)

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
