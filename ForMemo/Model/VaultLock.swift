import Foundation
import Combine
import LocalAuthentication
import os

enum VaultLockError: Error {
    case authenticationFailed
    case authenticationUnavailable
    case appSettingsUnavailable
}

@MainActor
final class VaultLock: ObservableObject {

    static let shared = VaultLock()
    
    static var hasBiometricAuthentication: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
    }
    
    private let settings = AppSettings.shared

    @Published private(set) var isUnlocked = false

    private var lockTask: Task<Void, Never>?
    private var authenticationContext: LAContext?

    private var timeout: TimeInterval {
        TimeInterval(settings.vaultAutoLockInterval)
    }

    private init() {}

    func unlock(reason: String = String(localized: "vault.unlock")) async throws {
        
#if targetEnvironment(simulator)

isUnlocked = true
scheduleAutoLock()

#else
        
        let context = authenticationContext ?? LAContext()
        authenticationContext = context

        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw VaultLockError.authenticationUnavailable
        }

        let policy: LAPolicy = .deviceOwnerAuthentication

        do {
            let success = try await context.evaluatePolicy(
                policy,
                localizedReason: reason
            )

            guard !Task.isCancelled else {
                throw CancellationError()
            }

            guard success else {
                throw VaultLockError.authenticationFailed
            }

            isUnlocked = true
            scheduleAutoLock()

        } catch let error as LAError {

            AppLogger.app.error(
                "Vault authentication failed: \(error.localizedDescription)"
            )
            throw error

        }
#endif
    }

    func authenticate(
        reason: String
    ) async throws {

    #if targetEnvironment(simulator)

        return

    #else

        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0

        var error: NSError?

        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &error
        ) else {
            throw VaultLockError.authenticationUnavailable
        }

        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: reason
        )

        guard success else {
            throw VaultLockError.authenticationFailed
        }

    #endif
    }
    
    func authenticateIfRequired(
        for item: VaultItem,
        reason: String = String(localized: "Show Password")
    ) async throws {

        authenticationContext?.invalidate()
        authenticationContext = nil

        try await unlock(reason: reason)
    }
    
    
    func lock() {
//        print("LOCK ESEGUITO")
        lockTask?.cancel()
        lockTask = nil
        isUnlocked = false
        authenticationContext?.invalidate()
        authenticationContext = nil
        VaultCrypto.clearCachedKey()
    }

    func userDidAccessVault() {
        guard isUnlocked else { return }
        scheduleAutoLock()
    }

    private func scheduleAutoLock() {
        lockTask?.cancel()

        guard timeout > 0 else { return }

        lockTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: .seconds(self.timeout))
            guard !Task.isCancelled else { return }

            guard self.isUnlocked else { return }
//            print("AUTOLOCK SCATTATO")
            self.lock()
        }
    }
}
