
import SwiftUI

struct VaultSecureTextField: View {

    let title: LocalizedStringKey

    @Binding var text: String

    var keyboardType: UIKeyboardType = .default
    var authenticateBeforeEditing = false

    var autoHideAfter: TimeInterval = 15

    @State private var isRevealed = false
    @State private var autoHideTask: Task<Void, Never>?
    
    var body: some View {

        HStack(spacing: 10) {

            Group {

                if isRevealed {

                    TextField(title, text: $text,
                    axis: .vertical
                  )
                } else {

                    SecureField(title, text: $text)

                }

            }
            .keyboardType(keyboardType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {

                Task {

                    if authenticateBeforeEditing && !isRevealed {

                        do {

                            try await VaultLock.shared.authenticate(
                                reason: String(localized: "Show Secret")
                            )

                        } catch {

                            return

                        }

                    }

                    await MainActor.run {

                        if isRevealed {

                            autoHideTask?.cancel()
                            autoHideTask = nil

                            isRevealed = false

                        } else {

                            isRevealed = true

                            autoHideTask?.cancel()

                            autoHideTask = Task {

                                try? await Task.sleep(
                                    for: .seconds(autoHideAfter)
                                )

                                guard !Task.isCancelled else {
                                    return
                                }

                                await MainActor.run {

                                    isRevealed = false

                                }
                            }
                        }
                    }
                }

            } label: {

                Image(systemName: isRevealed ? "eye.slash" : "eye")

            }
            .buttonStyle(.plain)
        }
        .onDisappear {

            autoHideTask?.cancel()

            isRevealed = false

        }
    }
    
}
