import SwiftUI

/// Central configuration for recurring-task generation and its confirmation UI.
/// Change these two values to adjust the per-operation cap and confirmation threshold
/// throughout the app without changing the recurrence logic or messages individually.
///
enum RecurrenceGenerationConfiguration {
    static let defaultMaximumOccurrencesPerOperation = 500
    static let defaultConfirmationThreshold = 50

    private static let maximumOccurrencesKey = "recurrence.maximumOccurrencesPerOperation"
    private static let confirmationThresholdKey = "recurrence.confirmationThreshold"

    static var maximumOccurrencesPerOperation: Int {
        let storedValue = UserDefaults.standard.object(forKey: maximumOccurrencesKey) as? Int
            ?? defaultMaximumOccurrencesPerOperation
        return min(max(storedValue, 1), 2_000)
    }

    static var confirmationThreshold: Int {
        let storedValue = UserDefaults.standard.object(forKey: confirmationThresholdKey) as? Int
            ?? defaultConfirmationThreshold
        return min(max(storedValue, 1), maximumOccurrencesPerOperation)
    }

    static func setMaximumOccurrencesPerOperation(_ value: Int) {
        let maximum = min(max(value, 1), 2_000)
        UserDefaults.standard.set(maximum, forKey: maximumOccurrencesKey)

        let threshold = confirmationThreshold
        if threshold > maximum {
            UserDefaults.standard.set(maximum, forKey: confirmationThresholdKey)
        }
    }

    static func setConfirmationThreshold(_ value: Int) {
        let threshold = min(max(value, 1), maximumOccurrencesPerOperation)
        UserDefaults.standard.set(threshold, forKey: confirmationThresholdKey)
    }
}


let defaultBackColor1 = Color(uiColor: UIColor { trait in
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

let defaultBackColor2 = Color(uiColor: UIColor { trait in
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

struct AppBackgroundColors {
    
    private static let color1Key = "backgroundColor1Hex"
    private static let color2Key = "backgroundColor2Hex"

    static var color1: Color {
        let hex = UserDefaults.standard.string(forKey: color1Key)
        return Color(hex: hex ?? "") ?? defaultBackColor1
    }

    static var color2: Color {
        let hex = UserDefaults.standard.string(forKey: color2Key)
        return Color(hex: hex ?? "") ?? defaultBackColor2
    }

    static func setColor1(_ color: Color) {
        UserDefaults.standard.set(
            color.toHex(),
            forKey: color1Key
        )
    }

    static func setColor2(_ color: Color) {
        UserDefaults.standard.set(
            color.toHex(),
            forKey: color2Key
        )
    }

    static func restoreDefaults() {
        UserDefaults.standard.set(
            defaultBackColor1.toHex(),
            forKey: color1Key
        )

        UserDefaults.standard.set(
            defaultBackColor2.toHex(),
            forKey: color2Key
        )
    }
}

struct AppGlassBackground: View {

    @Bindable var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Group {
                if settings.backgroundStyle == .system {
                    Color(.systemBackground)

                } else if settings.backgroundStyle == .theme {
                    colorScheme == .dark ? Color.black : Color.white

                } else {
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(hex: settings.backgroundColor1Hex) ?? defaultBackColor1,
                                Color(hex: settings.backgroundColor2Hex) ?? defaultBackColor2
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        Rectangle()
                            .fill(.ultraThinMaterial)
                    }
                }
            }

            if let assetName = settings.backgroundPattern.assetName {
                Color.clear
                    .ignoresSafeArea()
                    .overlay {
                        Image(assetName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFill()
                            .ignoresSafeArea()
                            .foregroundStyle(.primary)
                            .opacity(settings.backgroundPatternOpacity)
                            .allowsHitTesting(false)
                    }
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

struct AppGlassBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            AppGlassBackground()
                .ignoresSafeArea()

            content
        }
    }
}

extension View {
    func appGlassBackground() -> some View {
        modifier(AppGlassBackgroundModifier())
    }
}

// Ricava il display name dell'app
let appName: String = {
    
    let bundle = Bundle.main
    
    return bundle.infoDictionary?["CFBundleDisplayName"] as? String
    ?? bundle.infoDictionary?["CFBundleName"] as? String
    ?? "App"
}()





enum AppSettingsOpener {
    
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}



