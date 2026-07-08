import Foundation
import UIKit

extension Notification.Name {
    static let secureClipboardDidCopy = Notification.Name("SecureClipboardDidCopy")
}

@MainActor
enum SecureClipboard {

    private static var clearTask: Task<Void, Never>?


    static func copy(
        _ text: String,
        autoClearAfter interval: Duration? = nil
    ) {

        clearTask?.cancel()
        let interval = interval ?? .seconds(AppSettings.shared.vaultClipboardClearInterval)

        guard interval > .zero else {
            UIPasteboard.general.string = text

            NotificationCenter.default.post(
                name: .secureClipboardDidCopy,
                object: nil
            )
            return
        }

        UIPasteboard.general.string = text

        NotificationCenter.default.post(
            name: .secureClipboardDidCopy,
            object: nil
        )

        clearTask = Task { @MainActor in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }

            guard UIPasteboard.general.string == text else {
                return
            }

            clear()
            clearTask = nil
            NotificationCenter.default.post(
                name: .secureClipboardDidCopy,
                object: nil
            )
        }
    }

    static func clear() {
        clearTask?.cancel()
        clearTask = nil
        UIPasteboard.general.items = []
    }
}
