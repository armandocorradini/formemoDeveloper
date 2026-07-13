import SwiftUI

struct VaultPasswordField: View {

    @Binding var password: String
    var requireBiometricEveryTime: Bool = false
    var authenticateBeforeEditing: Bool = false
    var authenticateBeforeGenerating: Bool = false

    @State private var isRevealed = false
    @State private var strength: PasswordStrength = .veryWeak
    @State private var entropy: Double = 0
    @State private var autoHideTask: Task<Void, Never>?

    private var strengthProgress: Double {
        min(entropy / 128.0, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Group {
                    if isRevealed {
                        TextField(String(localized: "Password"), text: $password)
                    } else {
                        SecureField(String(localized: "Password"), text: $password)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    toggleReveal()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: isRevealed ? "Hide password" : "Show password"))
                .accessibilityHint(String(localized: "Shows or hides the password"))

                Button {
                    if authenticateBeforeGenerating {
                        Task {
                            do {
                                try await VaultLock.shared.unlock(reason: String(localized: "vault.unlock"))
                                await MainActor.run {
                                    password = PasswordGenerator.generate().value
                                }
                            } catch {
                                // Authentication cancelled or failed.
                            }
                        }
                    } else {
                        password = PasswordGenerator.generate().value
                    }
                } label: {
                    Image(systemName: "dice")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Generate password"))
                .accessibilityHint(String(localized: "Creates a new secure password"))

                Button {
                    guard !password.isEmpty else { return }
                    SecureClipboard.copy(password)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Copy password"))
                .accessibilityHint(String(localized: "Copies the password securely"))
                .disabled(password.isEmpty)
            }

            ProgressView(value: strengthProgress)

            HStack {
                Text(strength.localizedKey)
                Spacer()
                Text(String(format: "%.0f bits", entropy))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .onAppear(perform: updateMetrics)
        .onDisappear {
            autoHideTask?.cancel()
            isRevealed = false
        }
        .onChange(of: password) { _, _ in
            updateMetrics()
        }
    }

    private func toggleReveal() {
        guard requireBiometricEveryTime || authenticateBeforeEditing else {
            withAnimation(.snappy) {
                isRevealed.toggle()
            }
            if isRevealed {
                scheduleAutoHide()
            }
            return
        }

        Task {
            do {
                try await VaultLock.shared.unlock(reason: String(localized: "vault.unlock"))
                withAnimation(.snappy) {
                    isRevealed.toggle()
                }
                if isRevealed {
                    scheduleAutoHide()
                }
            } catch {
                // L'utente ha annullato o l'autenticazione è fallita.
            }
        }
    }

    private func scheduleAutoHide() {

        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.snappy) {
                    isRevealed = false
                }
            }
        }
    }

    private func updateMetrics() {
        let evaluation = PasswordGenerator.evaluate(password)
        strength = evaluation.strength
        entropy = evaluation.entropy
    }
}
