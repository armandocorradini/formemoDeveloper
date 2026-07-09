import SwiftUI
import LocalAuthentication

struct VaultGateView: View {

    @StateObject private var vaultLock = VaultLock.shared
    @State private var isUnlocking = false

    private func unlockVault() {

        guard !isUnlocking else { return }

        isUnlocking = true

        Task {

            defer {
                isUnlocking = false
            }

            do {

                try await vaultLock.unlock()

            } catch {

                NotificationCenter.default.post(
                    name: Notification.Name("VaultAuthenticationFailed"),
                    object: nil
                )
            }
        }
    }
    
    
    
    var body: some View {
        ZStack {
            if vaultLock.isUnlocked {
                VaultView()
            } else {
                VStack(spacing: 28) {

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                        .symbolRenderingMode(.hierarchical)

                    VStack(spacing: 8) {
                        Text(String(localized: "Vault"))
                            .font(.largeTitle.bold())

                        Text(String(localized: "Unlock to access your secure credentials."))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }

                     Button {
                        unlockVault()
                    } label: {
                        if isUnlocking {
                            ProgressView()
                                .controlSize(.regular)
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(String(localized: "Unlock"), systemImage: "faceid")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isUnlocking)
                    .accessibilityIdentifier("vault.unlock")
                }
                .padding(32)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
        }
        .onAppear {
            guard !vaultLock.isUnlocked else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard !vaultLock.isUnlocked else { return }
                unlockVault()
            }
        }
        .onDisappear {
            isUnlocking = false
        }
        .animation(.snappy, value: vaultLock.isUnlocked)
        .navigationTitle(String(localized: "Vault"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    VaultGateView()
}
