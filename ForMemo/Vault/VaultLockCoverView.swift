
import SwiftUI
import os

struct VaultLockCoverView: View {

    @StateObject private var vaultLock = VaultLock.shared
    @State private var isUnlocking = false

    var onUnlocked: (() -> Void)? = nil

    var body: some View {

        ZStack {
            AppGlassBackground()

            VStack(spacing: 28) {

                Image(
                    systemName: VaultLock.hasBiometricAuthentication
                    ? "faceid"
                    : "lock.fill"
                )
                .font(.system(size: 56))

                Text(String(localized: "Vault Locked"))
                    .font(.largeTitle.bold())

                Text(
                    VaultLock.hasBiometricAuthentication
                    ? String(localized: "Authenticate with Face ID to continue.")
                    : String(localized: "Authenticate with your device passcode to continue.")
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

                Button {

                    guard !isUnlocking else { return }

                    Task {

                        isUnlocking = true

                        defer {
                            isUnlocking = false
                        }

                        do {

                            try await vaultLock.unlock(

                                reason: String(localized: "Unlock Vault")

                            )

                            await MainActor.run {

                                onUnlocked?()

                            }
                        }catch {
                            
                            AppLogger.app.error(
                                "Vault unlock failed: \(error.localizedDescription)"
                            )
                        }
                    }

                } label: {

                    Label(
                        VaultLock.hasBiometricAuthentication
                        ? String(localized: "Unlock with Face ID")
                        : String(localized: "Unlock"),
                        systemImage:
                            VaultLock.hasBiometricAuthentication
                            ? "faceid"
                            : "lock.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUnlocking)

                if isUnlocking {
                    ProgressView()
                }
            }
            .padding(32)
            .frame(maxWidth: 420)
            .background(
                .regularMaterial,
                in: RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
            )
            .padding()
        }
    }
}
