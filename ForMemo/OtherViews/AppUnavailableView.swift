import SwiftUI


struct AppUnavailableView: View {
    
    let title: String
    let systemImage: String
    let description: String?
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(
        title: String,
        systemImage: String,
        description: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 20) {
            
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: description.map { Text($0) }
            )
            
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}


extension AppUnavailableView {
    
    static func error(_ message: String) -> some View {
        AppUnavailableView(
            title: String(localized: "Error"),
            systemImage: "exclamationmark.triangle",
            description: message
        )
    }
    
    static func permissionError(_ message: String) -> some View {
        AppUnavailableView(
            title: String(localized: "Attention!"),
            systemImage: "exclamationmark.triangle",
            description: message,
            actionTitle: String(localized: "Open Settings"),
            action: {
                AppSettingsOpener.open()
            }
        )
    }
    
    static func empty(_ title: String, systemImage: String = "tray") -> some View {
        AppUnavailableView(
            title: title,
            systemImage: systemImage
        )
    }
}
