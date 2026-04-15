import SwiftUI


let backColor1: Color = .blue.opacity(0.4)
let backColor2: Color = .purple.opacity(0.2)


// Ricava il display name dell'app
let appName: String = {
    
    let bundle = Bundle.main
    
    return bundle.infoDictionary?["CFBundleDisplayName"] as? String
    ?? bundle.infoDictionary?["CFBundleName"] as? String
    ?? "App"
}()



