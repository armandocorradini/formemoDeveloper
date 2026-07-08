import SwiftUI
import LocalAuthentication

struct VaultGateView: View {

    @StateObject private var vaultLock = VaultLock.shared
    @State private var isUnlocking = false

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
                        guard !isUnlocking else { return }
                        isUnlocking = true

                        Task {
                            defer {
                                isUnlocking = false
                            }

                            do {
                                try await vaultLock.unlock()
                            } catch let error as LAError {
                                print("🔐 Vault LAError:", error.code, error.localizedDescription)

                                switch error.code {
                                case .userCancel:
                                    print("User cancelled authentication.")

                                case .userFallback:
                                    print("User requested passcode fallback.")

                                case .systemCancel:
                                    print("Authentication cancelled by the system.")

                                default:
                                    print("Unhandled LAError:", error)
                                }

                            } catch is CancellationError {
                                print("Vault unlock cancelled.")

                            } catch {
                                print("Vault unlock failed:", error)
                            }
                        }
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
        .animation(.snappy, value: vaultLock.isUnlocked)
        .navigationTitle(String(localized: "Vault"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    VaultGateView()
}
